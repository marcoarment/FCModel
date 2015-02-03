//
//  FCModel.m
//
//  Created by Marco Arment on 7/18/13.
//  Copyright (c) 2013-2014 Marco Arment. See included LICENSE file.
//

#import <objc/runtime.h>
#import <string.h>
#import "FCModel.h"
#import "FCModelCachedObject.h"
#import "FCModelInstanceCache.h"
#import "FCModelDatabaseQueue.h"
#import "FCModelNotificationCenter.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import <sqlite3.h>
#import <Security/Security.h>

NSString * const FCModelException = @"FCModelException";
NSString * const FCModelChangeNotification = @"FCModelChangeNotification";
NSString * const FCModelInstanceKey = @"FCModelInstanceKey";
NSString * const FCModelChangedFieldsKey = @"FCModelChangedFieldsKey";

NSString * const FCModelWillSendChangeNotification = @"FCModelWillSendChangeNotification"; // for FCModelCachedObject

static FCModelDatabaseQueue *g_databaseQueue = NULL;
static NSDictionary *g_fieldInfo = NULL;
static NSDictionary *g_ignoredFieldNames = NULL;
static NSDictionary *g_primaryKeyFieldName = NULL;
static FCModelInstanceCache *g_instanceCache = NULL;

typedef NS_ENUM(char, FCModelInDatabaseStatus) {
    FCModelInDatabaseStatusNotYetInserted = 0,
    FCModelInDatabaseStatusRowExists,
    FCModelInDatabaseStatusDeleted
};

@interface FCModel () {
    FCModelInDatabaseStatus _inDatabaseStatus;
}
@property (nonatomic, copy) NSDictionary *_rowValuesInDatabase;
+ (void)postChangeNotificationWithChangedFields:(NSSet *)changedFields;
@end

static inline void onMainThreadAsync(void (^block)())
{
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

static inline BOOL checkForOpenDatabaseFatal(BOOL fatal)
{
    if (! g_databaseQueue) {
        if (fatal) NSCAssert(0, @"[FCModel] Database is closed");
        else NSLog(@"[FCModel] Warning: Attempting to access database while closed. Open it first.");
        return NO;
    }
    return YES;
}

@interface FCModelFieldInfo ()
@property (nonatomic) BOOL nullAllowed;
@property (nonatomic) FCModelFieldType type;
@property (nonatomic) id defaultValue;
@property (nonatomic) Class propertyClass;
@property (nonatomic) NSString *propertyTypeEncoding;
@end

@implementation FCModelFieldInfo
- (NSString *)description
{
    return [NSString stringWithFormat:@"<FCModelFieldInfo {%@ %@, default=%@}>",
        (_type == FCModelFieldTypeText ? @"text" : (_type == FCModelFieldTypeInteger ? @"integer" : (_type == FCModelFieldTypeDouble ? @"double" : (_type == FCModelFieldTypeBool ? @"bool" : @"other")))),
        _nullAllowed ? @"NULL" : @"NOT NULL",
        _defaultValue ? _defaultValue : @"NULL"
    ];
}
@end



@implementation FCModel

- (BOOL)isDeleted { return _inDatabaseStatus == FCModelInDatabaseStatusDeleted; }
- (BOOL)existsInDatabase { return _inDatabaseStatus == FCModelInDatabaseStatusRowExists; }
- (void)didInit { } // For subclasses to override

+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue { return [self instanceWithPrimaryKey:primaryKeyValue databaseRowValues:nil createIfNonexistent:YES]; }
+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue createIfNonexistent:(BOOL)create { return [self instanceWithPrimaryKey:primaryKeyValue databaseRowValues:nil createIfNonexistent:create]; }

+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue databaseRowValues:(NSDictionary *)fieldValues createIfNonexistent:(BOOL)create
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;

    if (! primaryKeyValue || primaryKeyValue == NSNull.null) return (create ? [self new] : nil);
    
    FCModel *instance = instance = fieldValues ? [[self alloc] initWithFieldValues:fieldValues existsInDatabaseAlready:YES] : [self instanceFromDatabaseWithPrimaryKey:primaryKeyValue];
    if (instance) [g_instanceCache saveInstance:instance];
    if (! instance && create) instance = [[self alloc] initWithFieldValues:@{ g_primaryKeyFieldName[self] : primaryKeyValue } existsInDatabaseAlready:NO];
    return instance;
}

+ (instancetype)instanceFromDatabaseWithPrimaryKey:(id)key
{
    id existing = [g_instanceCache instanceOfClass:self withPrimaryKeyValue:key];
    if (existing) return [existing copy];

    __block FCModel *model = NULL;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *s = [db executeQuery:[self expandQuery:@"SELECT * FROM \"$T\" WHERE \"$PK\"=?"], key];
        if (! s) [self queryFailedInDatabase:db];
        if ([s next]) model = [[self alloc] initWithFieldValues:s.resultDictionary existsInDatabaseAlready:YES];
        [s close];
    }];
    
    return model;
}

- (BOOL)reload { return [self reloadAndSave:nil]; }
- (BOOL)reloadAndSave:(void (^)())modificiationsBlock
{
    __block BOOL success = NO;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        if (self.isDeleted) return;
        FMResultSet *s = [db executeQuery:[self.class expandQuery:@"SELECT * FROM \"$T\" WHERE \"$PK\"=?"], self.primaryKey];
        if (! s) [self.class queryFailedInDatabase:db];
        if ([s next]) {
            [g_fieldInfo[self.class] enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
                id suppliedValue = s.resultDictionary[key];
                if (suppliedValue) [self decodeFieldValue:suppliedValue intoPropertyName:key];
            }];

            self._rowValuesInDatabase = s.resultDictionary;
        }
        [s close];
        
        if (modificiationsBlock) {
            modificiationsBlock();
            success = [self save];
        }
    }];
    return success;
}

#pragma mark - Mapping properties to database fields

- (id)serializedDatabaseRepresentationOfValue:(id)instanceValue forPropertyNamed:(NSString *)propertyName
{
    if (instanceValue == NSNull.null) instanceValue = nil;

    NSValueTransformer *transformer = [self.class valueTransformerForFieldName:propertyName];
    return transformer ? [transformer reverseTransformedValue:instanceValue] : instanceValue;
}

- (id)encodedValueForFieldName:(NSString *)fieldName
{
    id value = [self serializedDatabaseRepresentationOfValue:[self valueForKey:fieldName] forPropertyNamed:fieldName];
    return value ?: NSNull.null;
}

- (id)unserializedRepresentationOfDatabaseValue:(id)databaseValue forPropertyNamed:(NSString *)propertyName
{
    if (databaseValue == NSNull.null) databaseValue = nil;

    NSValueTransformer *transformer = [self.class valueTransformerForFieldName:propertyName];
    return transformer ? [transformer transformedValue:databaseValue] : databaseValue;
}

- (void)decodeFieldValue:(id)value intoPropertyName:(NSString *)propertyName
{
    value = [self unserializedRepresentationOfDatabaseValue:value forPropertyNamed:propertyName];
    [self setValue:value forKeyPath:propertyName];
}

+ (NSArray *)databaseFieldNames     { return checkForOpenDatabaseFatal(NO) ? [g_fieldInfo[self] allKeys] : nil; }
+ (NSString *)primaryKeyFieldName   { return checkForOpenDatabaseFatal(NO) ? g_primaryKeyFieldName[self] : nil; }
+ (FCModelFieldInfo *)infoForFieldName:(NSString *)fieldName { return checkForOpenDatabaseFatal(NO) ? g_fieldInfo[self][fieldName] : nil; }
+ (NSValueTransformer *)valueTransformerForFieldName:(NSString *)fieldName { return nil; }

#pragma mark - Find methods

+ (NSArray *)cachedInstancesWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)arguments
{
    return [self cachedInstancesWhere:queryAfterWHERE arguments:arguments ignoreFieldsForInvalidation:nil];
}

+ (NSArray *)cachedInstancesWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)arguments ignoreFieldsForInvalidation:(NSSet *)ignoredFields
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;
    return [FCModelLiveResultArray arrayWithModelClass:self queryAfterWHERE:queryAfterWHERE arguments:arguments ignoreFieldsForInvalidation:nil].allObjects;
}

+ (id)cachedObjectWithIdentifier:(id)identifier generator:(id (^)(void))generatorBlock
{
    return [self cachedObjectWithIdentifier:identifier ignoreFieldsForInvalidation:nil generator:generatorBlock];
}

+ (id)cachedObjectWithIdentifier:(id)identifier ignoreFieldsForInvalidation:(NSSet *)ignoredFields generator:(id (^)(void))generatorBlock
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;
    return [FCModelCachedObject objectWithModelClass:self cacheIdentifier:identifier ignoreFieldsForInvalidation:ignoredFields generator:generatorBlock].value;
}

+ (void)_executeUpdateQuery:(NSString *)query withVAList:(va_list)va_args arguments:(NSArray *)array_args
{
    checkForOpenDatabaseFatal(YES);

    __block NSDictionary *changedFieldsToNotify = nil;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        BOOL mustQueueNotificationsLocally = ! g_databaseQueue.isQueuingNotifications;
        if (mustQueueNotificationsLocally) g_databaseQueue.isQueuingNotifications = YES;
        
        BOOL success = va_args ? [db executeUpdate:[self expandQuery:query] withVAList:va_args] : [db executeUpdate:[self expandQuery:query] withArgumentsInArray:array_args];
        if (! success) [self queryFailedInDatabase:db];

        if (mustQueueNotificationsLocally) {
            g_databaseQueue.isQueuingNotifications = NO;
            changedFieldsToNotify = [g_databaseQueue.enqueuedChangedFieldsByClass copy];
            [g_databaseQueue.enqueuedChangedFieldsByClass removeAllObjects];
        }
    }];
    
    // Send notifications
    if (changedFieldsToNotify) {
        onMainThreadAsync(^{
            [changedFieldsToNotify enumerateKeysAndObjectsUsingBlock:^(Class class, NSDictionary *changedFields, BOOL *stop) {
                [NSNotificationCenter.defaultCenter postNotificationName:FCModelWillSendChangeNotification object:class userInfo:@{ FCModelChangedFieldsKey : changedFields }];
            }];
            [changedFieldsToNotify enumerateKeysAndObjectsUsingBlock:^(Class class, NSDictionary *changedFields, BOOL *stop) {
                [NSNotificationCenter.defaultCenter postNotificationName:FCModelChangeNotification object:class userInfo:@{ FCModelChangedFieldsKey : changedFields }];
            }];
        });
    }
}
+ (void)executeUpdateQuery:(NSString *)query arguments:(NSArray *)args { [self _executeUpdateQuery:query withVAList:NULL arguments:args]; }
+ (void)executeUpdateQuery:(NSString *)query, ... { va_list args; va_start(args, query); [self _executeUpdateQuery:query withVAList:args arguments:nil]; va_end(args); }

+ (id)_instancesWhere:(NSString *)query argsArray:(NSArray *)argsArray orVAList:(va_list)va_args onlyFirst:(BOOL)onlyFirst
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;
    NSMutableArray *instances = onlyFirst ? nil : [NSMutableArray array];
    __block FCModel *instance = nil;
    
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        NSString *pkName = g_primaryKeyFieldName[self];
        NSString *expandedQuery = query ? [self expandQuery:[@"SELECT * FROM \"$T\" WHERE " stringByAppendingString:query]] : [self expandQuery:@"SELECT * FROM \"$T\""];
        FMResultSet *s = va_args ? [db executeQuery:expandedQuery withVAList:va_args] : [db executeQuery:expandedQuery withArgumentsInArray:argsArray];
        if (! s) [self queryFailedInDatabase:db];

        while ([s next]) {
            NSDictionary *rowDictionary = s.resultDictionary;
            instance = [self instanceWithPrimaryKey:rowDictionary[pkName] databaseRowValues:rowDictionary createIfNonexistent:NO];
            if (onlyFirst) break;
            [instances addObject:instance];
        }
        [s close];
    }];
    
    return onlyFirst ? instance : instances;
}

+ (NSArray *)allInstances { return [self _instancesWhere:nil argsArray:nil orVAList:NULL onlyFirst:NO]; }

+ (instancetype)firstInstanceWhere:(NSString *)query arguments:(NSArray *)args { return [self _instancesWhere:query argsArray:args orVAList:NULL onlyFirst:YES]; }
+ (instancetype)firstInstanceWhere:(NSString *)query, ...
{
    va_list args;
    va_start(args, query);
    id instance = [self _instancesWhere:query argsArray:nil orVAList:args onlyFirst:YES];
    va_end(args);
    return instance;
}

+ (NSArray *)instancesWhere:(NSString *)query arguments:(NSArray *)args { return [self _instancesWhere:query argsArray:args orVAList:NULL onlyFirst:NO]; }
+ (NSArray *)instancesWhere:(NSString *)query, ...
{
    va_list args;
    va_start(args, query);
    NSArray *instances = [self _instancesWhere:query argsArray:nil orVAList:args onlyFirst:NO];
    va_end(args);
    return instances;
}

+ (instancetype)firstInstanceOrderedBy:(NSString *)query, ...
{
    va_list args;
    va_start(args, query);
    id instance = [self _instancesWhere:[@"1 ORDER BY " stringByAppendingString:query] argsArray:nil orVAList:args onlyFirst:YES];
    va_end(args);
    return instance;
}
+ (instancetype)firstInstanceOrderedBy:(NSString *)query arguments:(NSArray *)args { return [self _instancesWhere:[@"1 ORDER BY " stringByAppendingString:query] argsArray:args orVAList:NULL onlyFirst:YES]; }

+ (NSArray *)instancesOrderedBy:(NSString *)query, ...
{
    va_list args;
    va_start(args, query);
    NSArray *instances = [self _instancesWhere:[@"1 ORDER BY " stringByAppendingString:query] argsArray:nil orVAList:args onlyFirst:NO];
    va_end(args);
    return instances;
}

+ (NSArray *)instancesOrderedBy:(NSString *)query arguments:(NSArray *)args { return [self _instancesWhere:[@"1 ORDER BY " stringByAppendingString:query] argsArray:args orVAList:NULL onlyFirst:NO]; }

+ (NSUInteger)_numberOfInstancesWhere:(NSString *)queryAfterWHERE withVAList:(va_list)va_args arguments:(NSArray *)args
{
    if (! checkForOpenDatabaseFatal(NO)) return 0;
    
    __block NSUInteger count = 0;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        NSString *expandedQuery = [self expandQuery:(queryAfterWHERE ? [@"SELECT COUNT(*) FROM $T WHERE " stringByAppendingString:queryAfterWHERE] : @"SELECT COUNT(*) FROM $T")];
        FMResultSet *s = va_args ? [db executeQuery:expandedQuery withVAList:va_args] : [db executeQuery:expandedQuery withArgumentsInArray:args];
        if (! s) [self queryFailedInDatabase:db];
        if ([s next]) {
            NSNumber *value = [s objectForColumnIndex:0];
            if (value) count = value.unsignedIntegerValue;
        }
        [s close];
    }];
    return count;
}
+ (NSUInteger)numberOfInstancesWhere:(NSString *)query arguments:(NSArray *)args { return [self _numberOfInstancesWhere:query withVAList:NULL arguments:args]; };
+ (NSUInteger)numberOfInstancesWhere:(NSString *)query, ... { va_list args; va_start(args, query); NSUInteger c = [self _numberOfInstancesWhere:query withVAList:args arguments:nil]; va_end(args); return c; }
+ (NSUInteger)numberOfInstances { return [self _numberOfInstancesWhere:nil withVAList:NULL arguments:nil]; }

+ (NSArray *)_firstColumnArrayFromQuery:(NSString *)query withVAList:(va_list)va_args arguments:(NSArray *)arguments
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;
    
    NSMutableArray *columnArray = [NSMutableArray array];
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *s = va_args ? [db executeQuery:[self expandQuery:query] withVAList:va_args] : [db executeQuery:[self expandQuery:query] withArgumentsInArray:arguments];
        if (! s) [self queryFailedInDatabase:db];
        while ([s next]) [columnArray addObject:[s objectForColumnIndex:0]];
        [s close];
    }];
    return columnArray;
}
+ (NSArray *)firstColumnArrayFromQuery:(NSString *)query arguments:(NSArray *)arguments { return [self _firstColumnArrayFromQuery:query withVAList:NULL arguments:arguments]; }
+ (NSArray *)firstColumnArrayFromQuery:(NSString *)query, ... { va_list args; va_start(args, query); NSArray *r = [self _firstColumnArrayFromQuery:query withVAList:args arguments:nil]; va_end(args); return r; }

+ (NSArray *)_resultDictionariesFromQuery:(NSString *)query withVAList:(va_list)va_args arguments:(NSArray *)arguments
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;

    NSMutableArray *rows = [NSMutableArray array];
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *s = va_args ? [db executeQuery:[self expandQuery:query] withVAList:va_args] : [db executeQuery:[self expandQuery:query] withArgumentsInArray:arguments];
        if (! s) [self queryFailedInDatabase:db];
        while ([s next]) [rows addObject:s.resultDictionary];
        [s close];
    }];
    return rows;
}
+ (NSArray *)resultDictionariesFromQuery:(NSString *)query arguments:(NSArray *)arguments { return [self _resultDictionariesFromQuery:query withVAList:NULL arguments:arguments]; }
+ (NSArray *)resultDictionariesFromQuery:(NSString *)query, ... { va_list args; va_start(args, query); NSArray *r = [self _resultDictionariesFromQuery:query withVAList:args arguments:nil]; va_end(args); return r; }

+ (id)_firstValueFromQuery:(NSString *)query withVAList:(va_list)va_args arguments:(NSArray *)arguments
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;

    __block id firstValue = nil;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *s = va_args ? [db executeQuery:[self expandQuery:query] withVAList:va_args] : [db executeQuery:[self expandQuery:query] withArgumentsInArray:arguments];
        if (! s) [self queryFailedInDatabase:db];
        if ([s next]) firstValue = [[s objectForColumnIndex:0] copy];
        [s close];
    }];
    return firstValue;
}
+ (id)firstValueFromQuery:(NSString *)query arguments:(NSArray *)arguments { return [self _firstValueFromQuery:query withVAList:NULL arguments:arguments]; }
+ (id)firstValueFromQuery:(NSString *)query, ... { va_list args; va_start(args, query); id r = [self _firstValueFromQuery:query withVAList:args arguments:nil]; va_end(args); return r; }

+ (NSArray *)instancesWithPrimaryKeyValues:(NSArray *)primaryKeyValues
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;
    
    if (primaryKeyValues.count == 0) return @[];
    
    __block int maxParameterCount = 0;
    [self inDatabaseSync:^(FMDatabase *db) {
        maxParameterCount = sqlite3_limit(db.sqliteHandle, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
    }];

    __block NSArray *allFoundInstances = nil;
    NSMutableArray *valuesArray = [NSMutableArray arrayWithCapacity:MIN(primaryKeyValues.count, maxParameterCount)];
    NSMutableString *whereClause = [NSMutableString stringWithFormat:@"%@ IN (", g_primaryKeyFieldName[self]];
    NSUInteger whereClauseLength = whereClause.length;
    
    void (^fetchChunk)() = ^{
        if (valuesArray.count == 0) return;
        [whereClause appendString:@")"];
        NSArray *newInstancesThisChunk = [self _instancesWhere:whereClause argsArray:valuesArray orVAList:NULL onlyFirst:NO];
        allFoundInstances = allFoundInstances ? [allFoundInstances arrayByAddingObjectsFromArray:newInstancesThisChunk] : newInstancesThisChunk;
        
        // reset state for next chunk
        [whereClause deleteCharactersInRange:NSMakeRange(whereClauseLength, whereClause.length - whereClauseLength)];
        [valuesArray removeAllObjects];
    };
    
    for (id pkValue in primaryKeyValues) {
        [whereClause appendString:(valuesArray.count ? @",?" : @"?")];
        [valuesArray addObject:pkValue];
        if (valuesArray.count == maxParameterCount) fetchChunk();
    }
    fetchChunk();
    
    return allFoundInstances;
}

+ (void)queryFailedInDatabase:(FMDatabase *)db
{
    [[NSException exceptionWithName:FCModelException reason:[NSString stringWithFormat:@"Query failed with SQLite error %d: %@", db.lastErrorCode, db.lastErrorMessage] userInfo:nil] raise];
}

#pragma mark - Attributes and CRUD

+ (NSSet *)ignoredFieldNames { return [NSSet set]; }

+ (id)primaryKeyValueForNewInstance
{
    // Issue random 64-bit signed ints
    uint64_t urandom;
    if (0 != SecRandomCopyBytes(kSecRandomDefault, sizeof(uint64_t), (uint8_t *) (&urandom))) {
        arc4random_stir();
        urandom = ( ((uint64_t) arc4random()) << 32) | (uint64_t) arc4random();
    }

    int64_t random = (int64_t) (urandom & 0x7FFFFFFFFFFFFFFF);
    return @(random);
}

+ (instancetype)new  { return [[self alloc] initWithFieldValues:@{} existsInDatabaseAlready:NO]; }
- (instancetype)init { return [self initWithFieldValues:@{} existsInDatabaseAlready:NO]; }

- (instancetype)initWithFieldValues:(NSDictionary *)fieldValues existsInDatabaseAlready:(BOOL)existsInDB
{
    if ( (self = [super init]) ) {
        _inDatabaseStatus = existsInDB ? FCModelInDatabaseStatusRowExists : FCModelInDatabaseStatusNotYetInserted;
        
        [g_fieldInfo[self.class] enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
            FCModelFieldInfo *info = (FCModelFieldInfo *)obj;
            
            id suppliedValue = fieldValues[key];
            if (suppliedValue) {
                [self decodeFieldValue:suppliedValue intoPropertyName:key];
            } else {
                if ([key isEqualToString:g_primaryKeyFieldName[self.class]]) {
                    NSAssert(! existsInDB, @"Primary key not provided to initWithFieldValues:existsInDatabaseAlready:YES");
                    _inDatabaseStatus = FCModelInDatabaseStatusNotYetInserted;
                
                    // No supplied value to primary key for a new record. Generate a unique key value.
                    BOOL conflict = NO;
                    int attempts = 0;
                    do {
                        attempts++;
                        NSAssert1(attempts < 100, @"FCModel subclass %@ is not returning usable, unique values from primaryKeyValueForNewInstance", NSStringFromClass(self.class));
                        
                        id newKeyValue = [self.class primaryKeyValueForNewInstance];
                        if ([self.class instanceFromDatabaseWithPrimaryKey:newKeyValue]) continue; // already exists in database
                        [self setValue:newKeyValue forKey:key];
                    } while (conflict);
                    
                } else if (info.defaultValue) {
                    [self decodeFieldValue:info.defaultValue intoPropertyName:key];
                }
            }
        }];

        self._rowValuesInDatabase = _inDatabaseStatus == FCModelInDatabaseStatusRowExists ? fieldValues : nil;
        [self didInit];
    }
    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    if (_inDatabaseStatus != FCModelInDatabaseStatusRowExists) [[NSException exceptionWithName:FCModelException reason:@"Only FCModel instances written to the database can be copied" userInfo:nil] raise];

    NSMutableDictionary *fieldValues = [NSMutableDictionary dictionary];
    [g_fieldInfo[self.class] enumerateKeysAndObjectsUsingBlock:^(NSString *fieldName, id fieldInfo, BOOL *stop) {
        id value = [self encodedValueForFieldName:fieldName];
        if (value) fieldValues[fieldName] = value;
    }];
    
    return [[self.class alloc] initWithFieldValues:fieldValues existsInDatabaseAlready:YES];
}

- (void)revertUnsavedChanges
{
    if (! self._rowValuesInDatabase) return;
    [self.unsavedChanges enumerateKeysAndObjectsUsingBlock:^(NSString *fieldName, id obj, BOOL *stop) {
        [self revertUnsavedChangeToFieldName:fieldName];
    }];
}

- (void)revertUnsavedChangeToFieldName:(NSString *)fieldName
{
    id oldValue = self._rowValuesInDatabase ? self._rowValuesInDatabase[fieldName] : nil;
    [self decodeFieldValue:oldValue intoPropertyName:fieldName];
}

- (BOOL)hasUnsavedChanges { return _inDatabaseStatus == FCModelInDatabaseStatusNotYetInserted || self.unsavedChanges.count; }

- (NSDictionary *)unsavedChanges
{
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    
    [g_fieldInfo[self.class] enumerateKeysAndObjectsUsingBlock:^(NSString *fieldName, FCModelFieldInfo *info, BOOL *stop) {
        if ([fieldName isEqualToString:g_primaryKeyFieldName[self.class]]) return;

        NSDictionary *rowValuesInDatabase = self._rowValuesInDatabase;
        id oldValue = rowValuesInDatabase && [rowValuesInDatabase isKindOfClass:NSDictionary.class] ? rowValuesInDatabase[fieldName] : nil;
        oldValue = [self unserializedRepresentationOfDatabaseValue:oldValue forPropertyNamed:fieldName];
        
        id newValue = [self valueForKey:fieldName];
        if ((oldValue || newValue) && (! oldValue || (oldValue && ! newValue) || (oldValue && newValue && ! [newValue isEqual:oldValue]))) {
            changes[fieldName] = newValue ?: NSNull.null;
        }
    }];

    return [changes copy];
}

- (NSArray *)changedFieldNames { return self.unsavedChanges.allKeys; }

- (BOOL)save
{
    checkForOpenDatabaseFatal(YES);
    if (_inDatabaseStatus == FCModelInDatabaseStatusDeleted) [[NSException exceptionWithName:FCModelException reason:@"Cannot save deleted instance" userInfo:nil] raise];

    __block BOOL hadChanges = NO;
    __block NSSet *changedFields;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
    
        NSDictionary *changes = self.unsavedChanges;
        BOOL dirty = changes.count;
        if (! dirty && _inDatabaseStatus == FCModelInDatabaseStatusRowExists) { hadChanges = NO; return; }
        
        BOOL update = (_inDatabaseStatus == FCModelInDatabaseStatusRowExists);
        NSArray *columnNames;
        NSMutableArray *values;
        
        NSString *tableName = NSStringFromClass(self.class);
        NSString *pkName = g_primaryKeyFieldName[self.class];
        id primaryKey = [self encodedValueForFieldName:pkName];
        NSAssert1(primaryKey && (primaryKey != NSNull.null), @"Cannot update %@ without primary key value", NSStringFromClass(self.class));
       
        if (update) {
            columnNames = [changes allKeys];
            changedFields = [NSSet setWithArray:columnNames];
        } else {
            changedFields = [NSSet setWithArray:self.class.databaseFieldNames];
            NSMutableSet *columnNamesMinusPK = [[NSSet setWithArray:[g_fieldInfo[self.class] allKeys]] mutableCopy];
            [columnNamesMinusPK removeObject:pkName];
            columnNames = [columnNamesMinusPK allObjects];
        }

        // Validate NOT NULL columns
        [g_fieldInfo[self.class] enumerateKeysAndObjectsUsingBlock:^(id key, FCModelFieldInfo *info, BOOL *stop) {
            if (info.nullAllowed) return;
        
            id value = [self valueForKey:key];
            if (! value || value == NSNull.null) {
                [[NSException exceptionWithName:FCModelException reason:[NSString stringWithFormat:@"Cannot save NULL to NOT NULL property %@.%@", tableName, key] userInfo:nil] raise];
            }
        }];

        values = [NSMutableArray arrayWithCapacity:columnNames.count];
        [columnNames enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [values addObject:[self encodedValueForFieldName:obj]];
        }];
        [values addObject:primaryKey];

        NSString *query;
        if (update) {
            query = [NSString stringWithFormat:
                @"UPDATE \"%@\" SET \"%@\"=? WHERE \"%@\"=?",
                tableName,
                [columnNames componentsJoinedByString:@"\"=?,\""],
                pkName
            ];
        } else {
            if (columnNames.count > 0) {
                query = [NSString stringWithFormat:
                    @"INSERT INTO \"%@\" (\"%@\",\"%@\") VALUES (%@?)",
                    tableName,
                    [columnNames componentsJoinedByString:@"\",\""],
                    pkName,
                    [@"" stringByPaddingToLength:(columnNames.count * 2) withString:@"?," startingAtIndex:0]
                ];
            } else {
                query = [NSString stringWithFormat:
                    @"INSERT INTO \"%@\" (\"%@\") VALUES (?)",
                    tableName,
                    pkName
                ];
            }
        }

        g_databaseQueue.isInInternalWrite = YES;
        BOOL success = NO;
        success = [db executeUpdate:query withArgumentsInArray:values];
        g_databaseQueue.isInInternalWrite = NO;
        if (! success) [self.class queryFailedInDatabase:db];
        
        NSDictionary *rowValuesInDatabase = self._rowValuesInDatabase;
        NSMutableDictionary *newRowValues = rowValuesInDatabase ? [rowValuesInDatabase mutableCopy] : [NSMutableDictionary dictionary];
        [changes enumerateKeysAndObjectsUsingBlock:^(NSString *fieldName, id obj, BOOL *stop) {
            obj = [self serializedDatabaseRepresentationOfValue:obj forPropertyNamed:fieldName];
            newRowValues[fieldName] = obj ?: NSNull.null;
        }];
        self._rowValuesInDatabase = newRowValues;
        _inDatabaseStatus = FCModelInDatabaseStatusRowExists;

        hadChanges = YES;
    }];
    
    [g_instanceCache saveInstance:self];
    if (hadChanges) [self.class postChangeNotificationWithChangedFields:changedFields];
    return hadChanges;
}

- (void)delete
{
    checkForOpenDatabaseFatal(YES);
    __block id pkValue = nil;
    
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        if (_inDatabaseStatus == FCModelInDatabaseStatusDeleted) return;
        pkValue = self.primaryKey;
        
        __block BOOL success = NO;
        NSString *query = [self.class expandQuery:@"DELETE FROM \"$T\" WHERE \"$PK\" = ?"];
        g_databaseQueue.isInInternalWrite = YES;
        success = [db executeUpdate:query, [self primaryKey]];
        g_databaseQueue.isInInternalWrite = NO;
        if (! success) [self.class queryFailedInDatabase:db];

        _inDatabaseStatus = FCModelInDatabaseStatusDeleted;
    }];

    [g_instanceCache removeInstanceOfClass:self.class withPrimaryKeyValue:pkValue];
    [self.class postChangeNotificationWithChangedFields:nil];
}

#pragma mark - Utilities

- (id)primaryKey { return [self valueForKey:g_primaryKeyFieldName[self.class]]; }

+ (NSString *)expandQuery:(NSString *)query
{
    if (self == FCModel.class) return query;
    query = [query stringByReplacingOccurrencesOfString:@"$PK" withString:g_primaryKeyFieldName[self]];
    return [query stringByReplacingOccurrencesOfString:@"$T" withString:NSStringFromClass(self)];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@#%@: 0x%p>", NSStringFromClass(self.class), self.primaryKey, self];
}

- (NSDictionary *)allFields
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [[self.class databaseFieldNames] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        id value = [self valueForKey:obj];
        if (value) [dictionary setObject:value forKey:obj];
    }];
    return dictionary;
}

- (NSUInteger)hash
{
    return NSStringFromClass(self.class).hash ^ ((NSObject *)self.primaryKey).hash;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (self.class != [object class]) return NO;
    id selfKey = self.primaryKey;
    id objectKey = [object primaryKey];
    return selfKey && objectKey && [selfKey isEqual:objectKey];
}

+ (void)addObserver:(id)target selector:(SEL)action forChangedFields:(NSSet *)fieldNamesToWatch
{
    if (self == FCModel.class) [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Must call [FCModel addObserver:selector:forChangedFields:] on an FCModel subclass" userInfo:nil] raise];
    [FCModelNotificationCenter.defaultCenter addObserver:target selector:action class:self changedFields:fieldNamesToWatch];
}

+ (void)addObserver:(id)target selector:(SEL)action forAnyChangedFieldsExcept:(NSSet *)fieldNamesToIgnore
{
    if (self == FCModel.class) [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Must call [FCModel addObserver:selector:forAnyChangedFieldsExcept:] on an FCModel subclass" userInfo:nil] raise];
    NSMutableSet *fieldsToWatch = [NSSet setWithArray:self.databaseFieldNames].mutableCopy;
    [fieldsToWatch minusSet:fieldNamesToIgnore];
    [FCModelNotificationCenter.defaultCenter addObserver:target selector:action class:self changedFields:fieldsToWatch];
}

+ (void)removeObserverForFieldChanges:(id)target { [FCModelNotificationCenter.defaultCenter removeFieldChangeObservers:target]; }


#pragma mark - Database management

+ (void)openDatabaseAtPath:(NSString *)path withDatabaseInitializer:(void (^)(FMDatabase *db))databaseInitializer schemaBuilder:(void (^)(FMDatabase *db, int *schemaVersion))schemaBuilder
{
    g_databaseQueue = [[FCModelDatabaseQueue alloc] initWithDatabasePath:path];
    NSMutableDictionary *mutableFieldInfo = [NSMutableDictionary dictionary];
    NSMutableDictionary *mutableIgnoredFieldNames = [NSMutableDictionary dictionary];
    NSMutableDictionary *mutablePrimaryKeyFieldName = [NSMutableDictionary dictionary];
    
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        if (databaseInitializer) databaseInitializer(db);

        int startingSchemaVersion = 0;
        FMResultSet *rs = [db executeQuery:@"PRAGMA user_version"];
        if ([rs next]) startingSchemaVersion = [rs intForColumnIndex:0];
        [rs close];
        
        int newSchemaVersion = startingSchemaVersion;
        schemaBuilder(db, &newSchemaVersion);
        if (newSchemaVersion != startingSchemaVersion) {
            [db executeUpdate:[NSString stringWithFormat:@"PRAGMA user_version = %d", newSchemaVersion]];
        }
        
        // Scan for legacy AUTOINCREMENT usage
        FMResultSet *autoincRS = [db executeQuery:@"SELECT name FROM sqlite_master WHERE UPPER(sql) LIKE '%AUTOINCREMENT%'"];
        if ([autoincRS next]) [[NSException exceptionWithName:FCModelException reason:[NSString stringWithFormat:@"Table %@ uses AUTOINCREMENT, which FCModel does not support", [autoincRS stringForColumnIndex:0]] userInfo:nil] raise];
        [autoincRS close];
        
        // Read schema for field names and primary keys
        FMResultSet *tablesRS = [db executeQuery:
            @"SELECT DISTINCT tbl_name FROM (SELECT * FROM sqlite_master UNION ALL SELECT * FROM sqlite_temp_master) WHERE type != 'meta' AND name NOT LIKE 'sqlite_%'"
       ];
        while ([tablesRS next]) {
            NSString *tableName = [tablesRS stringForColumnIndex:0];
            Class tableModelClass = NSClassFromString(tableName);
            if (! tableModelClass || ! [tableModelClass isSubclassOfClass:self]) continue;
            
            NSString *primaryKeyName = nil;
            int primaryKeyColumnCount = 0;
            NSMutableDictionary *fields = [NSMutableDictionary dictionary];
            NSMutableSet *ignoredFieldNames = [([tableModelClass ignoredFieldNames] ?: [NSSet set]) mutableCopy];
            
            FMResultSet *columnsRS = [db executeQuery:[NSString stringWithFormat: @"PRAGMA table_info('%@')", tableName]];
            while ([columnsRS next]) {
                NSString *fieldName = [columnsRS stringForColumnIndex:1];
                if ([ignoredFieldNames containsObject:fieldName]) continue;
                
                objc_property_t property = class_getProperty(tableModelClass, fieldName.UTF8String);
                if (! property) {
                    NSLog(@"[FCModel] ignoring column %@.%@, no matching model property", tableName, fieldName);
                    [ignoredFieldNames addObject:fieldName];
                    continue;
                }
                
                NSArray *propertyAttributes = [[NSString stringWithCString:property_getAttributes(property) encoding:NSASCIIStringEncoding]componentsSeparatedByString:@","];
                if ([propertyAttributes containsObject:@"R"]) {
                    NSLog(@"[FCModel] ignoring column %@.%@, matching model property is readonly", tableName, fieldName);
                    [ignoredFieldNames addObject:fieldName];
                    continue;
                }
                
                Class propertyClass;
                NSString *propertyClassName, *typeString = propertyAttributes.count ? propertyAttributes[0] : nil;
                if (typeString) {
                    if (
                        [typeString hasPrefix:@"T@\""] && [typeString hasSuffix:@"\""] && typeString.length > 4 &&
                        (propertyClassName = [typeString substringWithRange:NSMakeRange(3, typeString.length - 4)])
                    ) {
                        propertyClass = NSClassFromString(propertyClassName);
                    } else if ([typeString isEqualToString:@"T@"]) {
                        // Property is defined as "id". It's not technically correct to use NSObject here, but I don't think there's a better option.
                        // The only negative side effects in practice should be if your code looks at FCModelFieldInfo directly and does something with
                        //  this property, *and* you need to accommodate for objects that aren't NSObjects, *and* you somehow forget that when using this
                        //  type info. But if you're in the business of declaring "id" properties and typeless columns to SQLite, I think that's an
                        //  acceptable risk.
                        propertyClass = NSObject.class;
                    }
                }
                
                int isPK = [columnsRS intForColumnIndex:5];
                if (isPK) {
                    primaryKeyColumnCount++;
                    primaryKeyName = fieldName;
                }

                NSString *fieldType = [columnsRS stringForColumnIndex:2];
                FCModelFieldInfo *info = [FCModelFieldInfo new];
                info.propertyClass = propertyClass;
                info.propertyTypeEncoding = [typeString substringFromIndex:1];
                info.nullAllowed = ! [columnsRS boolForColumnIndex:3];
                
                if (! isPK && info.nullAllowed && ! propertyClass) {
                    NSLog(@"[FCModel] column %@.%@ allows NULL but matching model property is a primitive type; should be declared NOT NULL", tableName, fieldName);
                    info.nullAllowed = NO;
                }
                
                BOOL defaultNull = isPK || [columnsRS columnIndexIsNull:4] || [[columnsRS stringForColumnIndex:4] isEqualToString:@"NULL"];
                
                // Type-parsing algorithm from SQLite's column-affinity rules: http://www.sqlite.org/datatype3.html
                // except the addition of BOOL as its own recognized type
                // parse case insensitive schema
                if ([fieldType rangeOfString:@"INT" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    info.type = FCModelFieldTypeInteger;
                    if (defaultNull) {
                        info.defaultValue = nil;
                    } else if ([fieldType rangeOfString:@"UNSIGNED" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                        info.defaultValue = [NSNumber numberWithUnsignedLongLong:[columnsRS unsignedLongLongIntForColumnIndex:4]];
                    } else {
                        info.defaultValue = [NSNumber numberWithLongLong:[columnsRS longLongIntForColumnIndex:4]];
                    }
                } else if ([fieldType rangeOfString:@"BOOL" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    info.type = FCModelFieldTypeBool;
                    info.defaultValue = defaultNull ? nil : [NSNumber numberWithBool:[columnsRS boolForColumnIndex:4]];
                } else if (
                    [fieldType rangeOfString:@"TEXT" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [fieldType rangeOfString:@"CHAR" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [fieldType rangeOfString:@"CLOB" options:NSCaseInsensitiveSearch].location != NSNotFound
                ) {
                    info.type = FCModelFieldTypeText;
                    info.defaultValue = defaultNull ? nil : [[[columnsRS stringForColumnIndex:4]
                        stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"'"]]
                        stringByReplacingOccurrencesOfString:@"''" withString:@"'"
                    ];
                } else if (
                    [fieldType rangeOfString:@"REAL" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [fieldType rangeOfString:@"FLOA" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [fieldType rangeOfString:@"DOUB" options:NSCaseInsensitiveSearch].location != NSNotFound
                ) {
                    info.type = FCModelFieldTypeDouble;
                    info.defaultValue = defaultNull ? nil : [NSNumber numberWithDouble:[columnsRS doubleForColumnIndex:4]];
                } else {
                    info.type = FCModelFieldTypeOther;
                    info.defaultValue = nil;
                }
                
                [fields setObject:info forKey:fieldName];
            }

            if (primaryKeyColumnCount != 1 ) {
                [[NSException
                    exceptionWithName:FCModelException
                    reason:[NSString stringWithFormat:@"FCModel tables must have a single-column primary key, but %@ has %d.", tableName, primaryKeyColumnCount]
                    userInfo:nil]
                raise];
            }
            
            id classKey = tableModelClass;
            [mutableFieldInfo setObject:fields forKey:classKey];
            [mutablePrimaryKeyFieldName setObject:primaryKeyName forKey:classKey];
            [columnsRS close];

            if (ignoredFieldNames.count) mutableIgnoredFieldNames[tableName] = [ignoredFieldNames copy];
        }
        [tablesRS close];
    
        g_fieldInfo = [mutableFieldInfo copy];
        g_ignoredFieldNames = [mutableIgnoredFieldNames copy];
        g_primaryKeyFieldName = [mutablePrimaryKeyFieldName copy];        
    }];

    [g_databaseQueue startMonitoringForExternalChanges];
    g_instanceCache = [[FCModelInstanceCache alloc] init];
}

+ (void)closeDatabase
{
    if (g_databaseQueue) {
        [g_databaseQueue close];
        [g_databaseQueue waitUntilAllOperationsAreFinished];
        g_databaseQueue = nil;
    }
    
    [FCModelCachedObject clearCache];
    [g_instanceCache removeAllInstances];
    g_primaryKeyFieldName = nil;
    g_fieldInfo = nil;
    g_ignoredFieldNames = nil;
}

+ (BOOL)databaseIsOpen { return g_databaseQueue != nil; }

+ (void)inDatabaseSync:(void (^)(FMDatabase *db))block
{
    checkForOpenDatabaseFatal(YES);
    [g_databaseQueue inDatabase:block];
}

#pragma mark - Batch notification queuing

+ (BOOL)isInTransaction
{
    __block BOOL inTransaction = NO;
    [self inDatabaseSync:^(FMDatabase *db) { inTransaction = db.inTransaction; }];
    return inTransaction;
}

+ (void)performTransaction:(BOOL (^)())block
{
    __block NSDictionary *changedFieldsToNotify = nil;

    [self inDatabaseSync:^(FMDatabase *db) {
        if (db.inTransaction) [[NSException exceptionWithName:FCModelException reason:@"Cannot nest FCModel transactions" userInfo:nil] raise];
        [db beginTransaction];
        g_databaseQueue.isQueuingNotifications = YES;
        
        BOOL commit = block();
        if (commit) [db commit];
        else [db rollback];
        
        g_databaseQueue.isQueuingNotifications = NO;
        changedFieldsToNotify = [g_databaseQueue.enqueuedChangedFieldsByClass copy];
        [g_databaseQueue.enqueuedChangedFieldsByClass removeAllObjects];
    }];
    
    // Send notifications
    onMainThreadAsync(^{
        [changedFieldsToNotify enumerateKeysAndObjectsUsingBlock:^(Class class, NSDictionary *changedFields, BOOL *stop) {
            [NSNotificationCenter.defaultCenter postNotificationName:FCModelWillSendChangeNotification object:class userInfo:@{ FCModelChangedFieldsKey : changedFields }];
        }];
        [changedFieldsToNotify enumerateKeysAndObjectsUsingBlock:^(Class class, NSDictionary *changedFields, BOOL *stop) {
            [NSNotificationCenter.defaultCenter postNotificationName:FCModelChangeNotification object:class userInfo:@{ FCModelChangedFieldsKey : changedFields }];
        }];
    });
}

+ (void)postChangeNotificationWithChangedFields:(NSSet *)changedFields
{
    if (! changedFields) changedFields = [NSSet setWithArray:self.class.databaseFieldNames];

    if (g_databaseQueue.isQueuingNotifications) {
        id class = (id) self;
        NSMutableSet *changedFieldsForClass = g_databaseQueue.enqueuedChangedFieldsByClass[class];
        if (changedFieldsForClass) [changedFieldsForClass unionSet:changedFields];
        else g_databaseQueue.enqueuedChangedFieldsByClass[class] = [changedFields mutableCopy];
    } else {
        // notify immediately
        NSDictionary *userInfo = @{ FCModelChangedFieldsKey : changedFields };
        onMainThreadAsync(^{
            [NSNotificationCenter.defaultCenter postNotificationName:FCModelWillSendChangeNotification object:self userInfo:userInfo];
            [NSNotificationCenter.defaultCenter postNotificationName:FCModelChangeNotification object:self userInfo:userInfo];
        });
    }
}

+ (void)dataChangedExternally
{
    [g_fieldInfo enumerateKeysAndObjectsUsingBlock:^(Class modelClass, id obj, BOOL *stop) {
        [modelClass postChangeNotificationWithChangedFields:nil];
    }];
}

@end
