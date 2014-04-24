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
#import "FCModelDatabaseQueue.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import <sqlite3.h>
@import Security;

NSString * const FCModelInsertNotification = @"FCModelInsertNotification";
NSString * const FCModelUpdateNotification = @"FCModelUpdateNotification";
NSString * const FCModelDeleteNotification = @"FCModelDeleteNotification";
NSString * const FCModelInstanceSetKey = @"FCModelInstanceSetKey";

NSString * const FCModelAnyChangeNotification = @"FCModelAnyChangeNotification";
NSString * const FCModelWillReloadNotification = @"FCModelWillReloadNotification";

static NSString * const FCModelReloadNotification = @"FCModelReloadNotification";
static NSString * const FCModelSaveNotification   = @"FCModelSaveNotification";
static NSString * const FCModelClassKey           = @"class";

static FCModelDatabaseQueue *g_databaseQueue = NULL;
static NSDictionary *g_fieldInfo = NULL;
static NSDictionary *g_primaryKeyFieldName = NULL;
static NSSet *g_tablesUsingAutoIncrementEmulation = NULL;
static NSMutableDictionary *g_instances = NULL;
static dispatch_semaphore_t g_instancesReadLock;
static NSMutableDictionary *g_enqueuedBatchNotifications = NULL;

@interface FMDatabase (HackForVAListsSinceThisIsPrivate)
- (FMResultSet *)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray*)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args;
- (BOOL)executeUpdate:(NSString*)sql error:(NSError**)outErr withArgumentsInArray:(NSArray*)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args;
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


@interface FCModel () {
    BOOL existsInDatabase;
    BOOL deleted;
}
@property (nonatomic, copy) NSDictionary *_rowValuesInDatabase;
@property (nonatomic, copy) NSError *_lastSQLiteError;
@end


@implementation FCModel

- (NSError *)lastSQLiteError { return self._lastSQLiteError; }

#pragma mark - For subclasses to override

- (void)didInit { }
- (BOOL)shouldInsert { return YES; }
- (BOOL)shouldUpdate { return YES; }
- (BOOL)shouldDelete { return YES; }
- (void)didInsert { }
- (void)didUpdate { }
- (void)didDelete { }
- (void)saveWasRefused { }
- (void)saveDidFail { }

#pragma mark - Instance tracking and uniquing

+ (void)uniqueMapInit
{
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        g_instancesReadLock = dispatch_semaphore_create(1);
        g_instances = [NSMutableDictionary dictionary];
    });
}

+ (NSArray *)allLoadedInstances
{
    [self uniqueMapInit];
    dispatch_semaphore_wait(g_instancesReadLock, DISPATCH_TIME_FOREVER);
    NSMapTable *classCache = g_instances[self];
    NSArray *instances = classCache ? [classCache.objectEnumerator.allObjects copy] : [NSArray array];
    dispatch_semaphore_signal(g_instancesReadLock);
    return instances;
}

+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue { return [self instanceWithPrimaryKey:primaryKeyValue databaseRowValues:nil createIfNonexistent:YES]; }
+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue createIfNonexistent:(BOOL)create { return [self instanceWithPrimaryKey:primaryKeyValue databaseRowValues:nil createIfNonexistent:create]; }

+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue databaseRowValues:(NSDictionary *)fieldValues createIfNonexistent:(BOOL)create
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;

    if (! primaryKeyValue || primaryKeyValue == NSNull.null) {
        return (create ? [self new] : nil);
    }
    [self uniqueMapInit];
    
    primaryKeyValue = [self normalizedPrimaryKeyValue:primaryKeyValue];
    
    FCModel *instance = NULL;
    dispatch_semaphore_wait(g_instancesReadLock, DISPATCH_TIME_FOREVER);
    NSMapTable *classCache = g_instances[self];
    if (! classCache) classCache = g_instances[(id) self] = [NSMapTable strongToWeakObjectsMapTable];
    instance = [classCache objectForKey:primaryKeyValue];
    dispatch_semaphore_signal(g_instancesReadLock);
    
    if (! instance) {
        // Not in memory yet. Check DB.
        instance = fieldValues ? [[self alloc] initWithFieldValues:fieldValues existsInDatabaseAlready:YES] : [self instanceFromDatabaseWithPrimaryKey:primaryKeyValue];
        if (! instance && create) {
            // Create new with this key.
            instance = [[self alloc] initWithFieldValues:@{ g_primaryKeyFieldName[self] : primaryKeyValue } existsInDatabaseAlready:NO];
        }
        
        if (instance) {
            dispatch_semaphore_wait(g_instancesReadLock, DISPATCH_TIME_FOREVER);
            FCModel *racedInstance = [classCache objectForKey:primaryKeyValue];
            if (racedInstance) {
                instance = racedInstance;
            } else {
                [classCache setObject:instance forKey:primaryKeyValue];
            }
            dispatch_semaphore_signal(g_instancesReadLock);
        }
    }

    return instance;
}

- (void)registerUniqueInstance
{
    id primaryKeyValue = self.primaryKey;
    if (! primaryKeyValue || primaryKeyValue == NSNull.null) return;
    [self.class uniqueMapInit];

    dispatch_semaphore_wait(g_instancesReadLock, DISPATCH_TIME_FOREVER);
    NSMapTable *classCache = g_instances[self.class];
    if (! classCache) classCache = g_instances[(id) self.class] = [NSMapTable strongToWeakObjectsMapTable];
    [classCache setObject:self forKey:primaryKeyValue];
    dispatch_semaphore_signal(g_instancesReadLock);
}

- (void)removeUniqueInstance
{
    id primaryKeyValue = self.primaryKey;
    if (! primaryKeyValue || primaryKeyValue == NSNull.null) return;
    [self.class uniqueMapInit];
    
    dispatch_semaphore_wait(g_instancesReadLock, DISPATCH_TIME_FOREVER);
    NSMapTable *classCache = g_instances[self.class];
    [classCache removeObjectForKey:primaryKeyValue];
    dispatch_semaphore_signal(g_instancesReadLock);
}

+ (instancetype)instanceFromDatabaseWithPrimaryKey:(id)key
{
    __block FCModel *model = NULL;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *s = [db executeQuery:[self expandQuery:@"SELECT * FROM \"$T\" WHERE \"$PK\"=?"], key];
        if (! s) [self queryFailedInDatabase:db];
        if ([s next]) model = [[self alloc] initWithFieldValues:s.resultDictionary existsInDatabaseAlready:YES];
        [s close];
    }];
    
    return model;
}

+ (void)dataWasUpdatedExternally
{
    [NSNotificationCenter.defaultCenter postNotificationName:FCModelWillReloadNotification object:nil userInfo:@{ FCModelClassKey : self }];
    [NSNotificationCenter.defaultCenter postNotificationName:FCModelReloadNotification object:nil userInfo:@{ FCModelClassKey : self }];
    
    onMainThreadAsync(^{
        [NSNotificationCenter.defaultCenter postNotificationName:FCModelAnyChangeNotification object:nil userInfo:@{ FCModelClassKey : self }];
    });
}

#pragma mark - Mapping properties to database fields

- (id)serializedDatabaseRepresentationOfValue:(id)instanceValue forPropertyNamed:(NSString *)propertyName
{
    if ([instanceValue isKindOfClass:NSArray.class] || [instanceValue isKindOfClass:NSDictionary.class]) {
        NSError *error = nil;
        NSData *bplist = [NSPropertyListSerialization dataWithPropertyList:instanceValue format:NSPropertyListBinaryFormat_v1_0 options:NSPropertyListImmutable error:&error];
        if (error) {
            [[NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:
                @"Cannot serialize %@ to plist for %@.%@: %@", NSStringFromClass(((NSObject *)instanceValue).class), NSStringFromClass(self.class), propertyName, error.localizedDescription
            ] userInfo:nil] raise];
        }
        return bplist;
    } else if ([instanceValue isKindOfClass:NSURL.class]) {
        return [(NSURL *)instanceValue absoluteString];
    } else if ([instanceValue isKindOfClass:NSDate.class]) {
        return [NSNumber numberWithDouble:[(NSDate *)instanceValue timeIntervalSince1970]];
    }

    return instanceValue;
}

- (id)encodedValueForFieldName:(NSString *)fieldName
{
    id value = [self serializedDatabaseRepresentationOfValue:[self valueForKey:fieldName] forPropertyNamed:fieldName];
    return value ?: NSNull.null;
}

- (id)unserializedRepresentationOfDatabaseValue:(id)databaseValue forPropertyNamed:(NSString *)propertyName
{
    Class propertyClass = [g_fieldInfo[self.class][propertyName] propertyClass];
    
    if (propertyClass && databaseValue) {
        if (propertyClass == NSURL.class) {
            return [NSURL URLWithString:databaseValue];
        } else if (propertyClass == NSDate.class) {
            return [NSDate dateWithTimeIntervalSince1970:[databaseValue doubleValue]];
        } else if (propertyClass == NSDictionary.class) {
            NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:databaseValue options:kCFPropertyListImmutable format:NULL error:NULL];
            return dict && [dict isKindOfClass:NSDictionary.class] ? dict : @{};
        } else if (propertyClass == NSArray.class) {
            NSArray *array = [NSPropertyListSerialization propertyListWithData:databaseValue options:kCFPropertyListImmutable format:NULL error:NULL];
            return array && [array isKindOfClass:NSArray.class] ? array : @[];
        }
    }

    return databaseValue;
}

- (void)decodeFieldValue:(id)value intoPropertyName:(NSString *)propertyName
{
    if (value == NSNull.null) value = nil;
    if (class_getProperty(self.class, propertyName.UTF8String)) {
        [self setValue:[self unserializedRepresentationOfDatabaseValue:value forPropertyNamed:propertyName] forKeyPath:propertyName];
    }
}

+ (NSArray *)databaseFieldNames     { return checkForOpenDatabaseFatal(NO) ? [g_fieldInfo[self] allKeys] : nil; }
+ (NSString *)primaryKeyFieldName   { return checkForOpenDatabaseFatal(NO) ? g_primaryKeyFieldName[self] : nil; }
+ (FCModelFieldInfo *)infoForFieldName:(NSString *)fieldName { return checkForOpenDatabaseFatal(NO) ? g_fieldInfo[self][fieldName] : nil; }

// For unique-instance consistency:
// Resolve discrepancies between supplied primary-key value type and the column type that comes out of the database.
// Without this, it's possible to e.g. pull objects with key @(1) and key @"1" as two different instances of the same record.
+ (id)normalizedPrimaryKeyValue:(id)value
{
    static NSNumberFormatter *numberFormatter;
    static dispatch_once_t onceToken;

    if (! value) return value;
    
    FCModelFieldInfo *primaryKeyInfo = g_fieldInfo[self][g_primaryKeyFieldName[self]];
    
    if ([value isKindOfClass:NSString.class] && (primaryKeyInfo.type == FCModelFieldTypeInteger || primaryKeyInfo.type == FCModelFieldTypeDouble || primaryKeyInfo.type == FCModelFieldTypeBool)) {
        dispatch_once(&onceToken, ^{ numberFormatter = [[NSNumberFormatter alloc] init]; });
        value = [numberFormatter numberFromString:value];
    } else if (! [value isKindOfClass:NSString.class] && primaryKeyInfo.type == FCModelFieldTypeText) {
        value = [value stringValue];
    }

    return value;
}

#pragma mark - Find methods

+ (NSArray *)cachedInstancesWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)arguments
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;
    return [FCModelLiveResultArray arrayWithModelClass:self queryAfterWHERE:queryAfterWHERE arguments:arguments].allObjects;
}

+ (id)cachedObjectWithIdentifier:(id)identifier generator:(id (^)(void))generatorBlock
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;
    return [FCModelCachedObject objectWithModelClass:self cacheIdentifier:identifier generator:generatorBlock].value;
}

+ (NSError *)executeUpdateQuery:(NSString *)query, ...
{
    checkForOpenDatabaseFatal(YES);

    va_list args;
    va_list *foolTheStaticAnalyzer = &args;
    va_start(args, query);

    __block BOOL success = NO;
    __block NSError *error = nil;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        success = [db executeUpdate:[self expandQuery:query] error:nil withArgumentsInArray:nil orDictionary:nil orVAList:*foolTheStaticAnalyzer];
        if (! success) error = [db.lastError copy];
    }];

    va_end(args);
    if (success) [self dataWasUpdatedExternally];
    return error;
}

+ (id)_instancesWhere:(NSString *)query andArgs:(va_list)args orArgsArray:(NSArray *)argsArray orResultSet:(FMResultSet *)existingResultSet onlyFirst:(BOOL)onlyFirst keyed:(BOOL)keyed
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;

    NSMutableArray *instances;
    NSMutableDictionary *keyedInstances;
    __block FCModel *instance = nil;
    
    if (! onlyFirst) {
        if (keyed) keyedInstances = [NSMutableDictionary dictionary];
        else instances = [NSMutableArray array];
    }
    
    void (^processResult)(FMResultSet *, BOOL *) = ^(FMResultSet *s, BOOL *stop){
        NSDictionary *rowDictionary = s.resultDictionary;
        instance = [self instanceWithPrimaryKey:rowDictionary[g_primaryKeyFieldName[self]] databaseRowValues:rowDictionary createIfNonexistent:NO];
        if (onlyFirst) {
            *stop = YES;
            return;
        }
        if (keyed) [keyedInstances setValue:instance forKey:[instance primaryKey]];
        else [instances addObject:instance];
    };
    
    if (existingResultSet) {
        BOOL stop = NO;
        while (! stop && [existingResultSet next]) processResult(existingResultSet, &stop);
    } else {
        [g_databaseQueue inDatabase:^(FMDatabase *db) {
            FMResultSet *s = [db
                executeQuery:(
                    query ?
                    [self expandQuery:[@"SELECT * FROM \"$T\" WHERE " stringByAppendingString:query]] :
                    [self expandQuery:@"SELECT * FROM \"$T\""]
                )
                withArgumentsInArray:argsArray
                orDictionary:nil
                orVAList:args
            ];
            if (! s) [self queryFailedInDatabase:db];
            BOOL stop = NO;
            while (! stop && [s next]) processResult(s, &stop);
            [s close];
        }];
    }
    
    return onlyFirst ? instance : (keyed ? keyedInstances : instances);
}

+ (NSArray *)instancesFromResultSet:(FMResultSet *)rs { return [self _instancesWhere:nil andArgs:NULL orArgsArray:nil orResultSet:rs onlyFirst:NO keyed:NO]; }
+ (NSDictionary *)keyedInstancesFromResultSet:(FMResultSet *)rs { return [self _instancesWhere:nil andArgs:NULL orArgsArray:nil orResultSet:rs onlyFirst:NO keyed:YES]; }
+ (instancetype)firstInstanceFromResultSet:(FMResultSet *)rs { return [self _instancesWhere:nil andArgs:NULL orArgsArray:nil orResultSet:rs onlyFirst:YES keyed:NO]; }

+ (instancetype)firstInstanceWhere:(NSString *)query, ...
{
    va_list args;
    va_start(args, query);
    id result = [self _instancesWhere:query andArgs:args orArgsArray:nil orResultSet:nil onlyFirst:YES keyed:NO];
    va_end(args);
    return result;
}

+ (NSArray *)instancesWhere:(NSString *)query, ...
{
    va_list args;
    va_start(args, query);
    NSArray *results = [self _instancesWhere:query andArgs:args orArgsArray:nil orResultSet:nil onlyFirst:NO keyed:NO];
    va_end(args);
    return results;
}

+ (NSArray *)instancesWhere:(NSString *)query arguments:(NSArray *)array;
{
    return [self _instancesWhere:query andArgs:NULL orArgsArray:array orResultSet:NULL onlyFirst:NO keyed:NO];
}

+ (NSDictionary *)keyedInstancesWhere:(NSString *)query, ...
{
    va_list args;
    va_start(args, query);
    NSDictionary *results = [self _instancesWhere:query andArgs:args orArgsArray:nil orResultSet:nil onlyFirst:NO keyed:NO];
    va_end(args);
    return results;
}

+ (instancetype)firstInstanceOrderedBy:(NSString *)query, ...
{
    va_list args;
    va_start(args, query);
    id result = [self _instancesWhere:[@"1 ORDER BY " stringByAppendingString:query] andArgs:args orArgsArray:nil orResultSet:nil onlyFirst:YES keyed:NO];
    va_end(args);
    return result;
}

+ (NSArray *)instancesOrderedBy:(NSString *)query, ...
{
    va_list args;
    va_start(args, query);
    id result = [self _instancesWhere:[@"1 ORDER BY " stringByAppendingString:query] andArgs:args orArgsArray:nil orResultSet:nil onlyFirst:NO keyed:NO];
    va_end(args);
    return result;
}

+ (NSArray *)allInstances { return [self _instancesWhere:nil andArgs:NULL orArgsArray:nil orResultSet:nil onlyFirst:NO keyed:NO]; }
+ (NSDictionary *)keyedAllInstances { return [self _instancesWhere:nil andArgs:NULL orArgsArray:nil orResultSet:nil onlyFirst:NO keyed:YES]; }

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
    
    void (^fetchChunk)() = ^{
        if (valuesArray.count == 0) return;
        [whereClause appendString:@")"];
        NSArray *newInstancesThisChunk = [self _instancesWhere:whereClause andArgs:NULL orArgsArray:valuesArray orResultSet:nil onlyFirst:NO keyed:NO];
        allFoundInstances = allFoundInstances ? [allFoundInstances arrayByAddingObjectsFromArray:newInstancesThisChunk] : newInstancesThisChunk;
        
        // reset state for next chunk
        [whereClause deleteCharactersInRange:NSMakeRange(7, whereClause.length - 7)];
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

+ (NSDictionary *)keyedInstancesWithPrimaryKeyValues:(NSArray *)primaryKeyValues
{
    NSArray *instances = [self instancesWithPrimaryKeyValues:primaryKeyValues];
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:instances.count];
    for (FCModel *instance in instances) [dictionary setObject:instance forKey:instance.primaryKey];
    return dictionary;
}

+ (NSUInteger)numberOfInstances
{
    NSNumber *value = [self firstValueFromQuery:@"SELECT COUNT(*) FROM $T"];
    return value ? value.unsignedIntegerValue : 0;
}

+ (NSUInteger)numberOfInstancesWhere:(NSString *)queryAfterWHERE, ...
{
    __block NSUInteger count = 0;
    va_list args;
    va_list *foolTheStaticAnalyzer = &args;
    va_start(args, queryAfterWHERE);
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *s = [db executeQuery:[self expandQuery:[@"SELECT COUNT(*) FROM $T WHERE " stringByAppendingString:queryAfterWHERE]] withArgumentsInArray:nil orDictionary:nil orVAList:*foolTheStaticAnalyzer];
        if (! s) [self queryFailedInDatabase:db];
        if ([s next]) {
            NSNumber *value = [s objectForColumnIndex:0];
            if (value) count = value.unsignedIntegerValue;
        }
        [s close];
    }];
    va_end(args);
    
    return count;
}

+ (NSArray *)firstColumnArrayFromQuery:(NSString *)query, ...
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;

    NSMutableArray *columnArray = [NSMutableArray array];
    va_list args;
    va_list *foolTheStaticAnalyzer = &args;
    va_start(args, query);
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *s = [db executeQuery:[self expandQuery:query] withArgumentsInArray:nil orDictionary:nil orVAList:*foolTheStaticAnalyzer];
        if (! s) [self queryFailedInDatabase:db];
        while ([s next]) [columnArray addObject:[s objectForColumnIndex:0]];
        [s close];
    }];
    va_end(args);
    return columnArray;
}

+ (NSArray *)resultDictionariesFromQuery:(NSString *)query, ...
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;

    NSMutableArray *rows = [NSMutableArray array];
    va_list args;
    va_list *foolTheStaticAnalyzer = &args;
    va_start(args, query);
        [g_databaseQueue inDatabase:^(FMDatabase *db) {
            FMResultSet *s = [db executeQuery:[self expandQuery:query] withArgumentsInArray:nil orDictionary:nil orVAList:*foolTheStaticAnalyzer];
            if (! s) [self queryFailedInDatabase:db];
            while ([s next]) [rows addObject:s.resultDictionary];
            [s close];
        }];
    va_end(args);
    return rows;
}

+ (id)firstValueFromQuery:(NSString *)query, ...
{
    if (! checkForOpenDatabaseFatal(NO)) return nil;

    __block id firstValue = nil;
    va_list args;
    va_list *foolTheStaticAnalyzer = &args;
    va_start(args, query);
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *s = [db executeQuery:[self expandQuery:query] withArgumentsInArray:nil orDictionary:nil orVAList:*foolTheStaticAnalyzer];
        if (! s) [self queryFailedInDatabase:db];
        if ([s next]) firstValue = [[s objectForColumnIndex:0] copy];
        [s close];
    }];
    va_end(args);
    return firstValue;
}

+ (void)queryFailedInDatabase:(FMDatabase *)db
{
    [[NSException exceptionWithName:@"FCModelSQLiteException" reason:db.lastErrorMessage userInfo:nil] raise];
}

#pragma mark - Attributes and CRUD

+ (id)primaryKeyValueForNewInstance
{
    BOOL databaseIsOpen = checkForOpenDatabaseFatal(NO);
    
    // Emulation for old AUTOINCREMENT tables
    if (databaseIsOpen && g_tablesUsingAutoIncrementEmulation && [g_tablesUsingAutoIncrementEmulation containsObject:NSStringFromClass(self)]) {
        id largestNumber = [self firstValueFromQuery:@"SELECT MAX($PK) FROM $T"];
        int64_t largestExistingValue = largestNumber && largestNumber != NSNull.null ? ((NSNumber *) largestNumber).longLongValue : 0;

        dispatch_semaphore_wait(g_instancesReadLock, DISPATCH_TIME_FOREVER);
        NSMapTable *classCache = g_instances[self];
        NSArray *instances = classCache ? [classCache.objectEnumerator.allObjects copy] : [NSArray array];
        for (FCModel *instance in instances) {
            largestExistingValue = MAX(largestExistingValue, ((NSNumber *)instance.primaryKey).longLongValue);
        }
        dispatch_semaphore_signal(g_instancesReadLock);
        
        largestExistingValue++;
        return @(largestExistingValue);
    }

    // Otherwise, issue random 64-bit signed ints
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
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload:) name:FCModelReloadNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(saveByNotification:) name:FCModelSaveNotification object:nil];
        existsInDatabase = existsInDB;
        deleted = NO;
        
        [self.class uniqueMapInit];
        
        [g_fieldInfo[self.class] enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
            FCModelFieldInfo *info = (FCModelFieldInfo *)obj;
            
            id suppliedValue = fieldValues[key];
            if (suppliedValue) {
                [self decodeFieldValue:suppliedValue intoPropertyName:key];
            } else {
                if ([key isEqualToString:g_primaryKeyFieldName[self.class]]) {
                    NSAssert(! existsInDB, @"Primary key not provided to initWithFieldValues:existsInDatabaseAlready:YES");
                    existsInDatabase = NO;
                
                    // No supplied value to primary key for a new record. Generate a unique key value.
                    BOOL conflict = NO;
                    int attempts = 0;
                    do {
                        attempts++;
                        NSAssert1(attempts < 100, @"FCModel subclass %@ is not returning usable, unique values from primaryKeyValueForNewInstance", NSStringFromClass(self.class));
                        
                        id newKeyValue = [self.class normalizedPrimaryKeyValue:[self.class primaryKeyValueForNewInstance]];
                        if ([self.class instanceFromDatabaseWithPrimaryKey:newKeyValue]) continue; // already exists in database

                        // already exists in memory (unsaved)
                        dispatch_semaphore_wait(g_instancesReadLock, DISPATCH_TIME_FOREVER);
                        NSMapTable *classCache = g_instances[self.class];
                        if (! classCache) classCache = g_instances[(id) self.class] = [NSMapTable strongToWeakObjectsMapTable];
                        conflict = (nil != [classCache objectForKey:newKeyValue]);
                        if (! conflict) [classCache setObject:self forKey:newKeyValue];
                        dispatch_semaphore_signal(g_instancesReadLock);
                        
                        [self setValue:newKeyValue forKey:key];
                    } while (conflict);
                    
                } else if (info.defaultValue) {
                    [self decodeFieldValue:info.defaultValue intoPropertyName:key];
                }
            }
        }];

        self._rowValuesInDatabase = existsInDatabase ? fieldValues : nil;
        [self didInit];
    }
    return self;
}

- (void)saveByNotification:(NSNotification *)n
{
    if (! checkForOpenDatabaseFatal(NO)) return;
    
    if (deleted) return;
    Class targetedClass = n.userInfo[FCModelClassKey];
    if (targetedClass && ! [self isKindOfClass:targetedClass]) return;
    [self save];
}

- (void)reload:(NSNotification *)n
{
    if (! checkForOpenDatabaseFatal(NO)) return;

    Class targetedClass = n.userInfo[FCModelClassKey];
    if (targetedClass && ! [self isKindOfClass:targetedClass]) return;
    if (! self.existsInDatabase) return;

    __block NSDictionary *resultDictionary = nil;

    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *s = [db executeQuery:[self.class expandQuery:@"SELECT * FROM \"$T\" WHERE \"$PK\"=?"], self.primaryKey];
        if (! s) [self.class queryFailedInDatabase:db];
        if ([s next]) {
            // Update from new database values
            resultDictionary = [s.resultDictionary copy];
        } else {
            // This instance no longer exists in database
            deleted = YES;
            existsInDatabase = NO;
        }
        [s close];
    }];

    if (deleted) {
        self._rowValuesInDatabase = nil;
        [self didDelete];
        [self postChangeNotification:FCModelDeleteNotification];
        [self postChangeNotification:FCModelAnyChangeNotification];
    } else {
        NSDictionary *unsavedChanges = self.unsavedChanges;

        [resultDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *fieldName, id fieldValue, BOOL *stop) {
            if ([fieldName isEqualToString:g_primaryKeyFieldName[self.class]]) return;
            fieldValue = fieldValue == NSNull.null ? nil : fieldValue;
            
            id unsavedChangeValue = unsavedChanges[fieldName];
            if (unsavedChangeValue) {
                // Conflict if the value isn't equal to the new DB value.
                if (unsavedChangeValue == NSNull.null) unsavedChangeValue = nil;

                if (unsavedChangeValue != fieldValue && ((! unsavedChangeValue || ! fieldValue) || ! [fieldValue isEqual:unsavedChangeValue])) {
                    // Conflict: model was loaded from DB, modified without being saved, and now the reload wants to set a different value
                    fieldValue = [self valueOfFieldName:fieldName byResolvingReloadConflictWithDatabaseValue:fieldValue];
                }

                [self decodeFieldValue:fieldValue intoPropertyName:fieldName];
            } else {
                // No conflict. Just assign the new value.
                [self decodeFieldValue:fieldValue intoPropertyName:fieldName];
            }
        }];
        
        self._rowValuesInDatabase = resultDictionary;
        
        [self didUpdate];
        [self postChangeNotification:FCModelUpdateNotification];
        [self postChangeNotification:FCModelAnyChangeNotification];
    }
}

- (id)valueOfFieldName:(NSString *)fieldName byResolvingReloadConflictWithDatabaseValue:(id)valueInDatabase
{
    // A very simple subclass implementation could just always accept the locally modified value:
    //     return [self valueForKeyPath:fieldName]
    //
    // ...or always accept the database value:
    //     return valueInDatabase;
    //
    // But this is a decision that you should really make knowingly and deliberately in each case.

    [[NSException exceptionWithName:@"FCReloadConflict" reason:
        [NSString stringWithFormat:@"%@ ID %@ cannot resolve reload conflict for \"%@\"", NSStringFromClass(self.class), self.primaryKey, fieldName]
    userInfo:nil] raise];
    return nil;
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
    if (oldValue) [self decodeFieldValue:oldValue intoPropertyName:fieldName];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelReloadNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelSaveNotification object:nil];
}

- (BOOL)existsInDatabase  { return existsInDatabase; }
- (BOOL)hasUnsavedChanges { return ! existsInDatabase || self.unsavedChanges.count; }

- (NSDictionary *)unsavedChanges
{
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    
    [g_fieldInfo[self.class] enumerateKeysAndObjectsUsingBlock:^(NSString *fieldName, FCModelFieldInfo *info, BOOL *stop) {
        if ([fieldName isEqualToString:g_primaryKeyFieldName[self.class]]) return;

        id oldValue = self._rowValuesInDatabase ? self._rowValuesInDatabase[fieldName] : nil;
        if (oldValue) oldValue = [self unserializedRepresentationOfDatabaseValue:(oldValue == NSNull.null ? nil : oldValue) forPropertyNamed:fieldName];
        
        id newValue = [self valueForKey:fieldName];
        if ((oldValue || newValue) && (! oldValue || (oldValue && ! newValue) || (oldValue && newValue && ! [newValue isEqual:oldValue]))) {
            BOOL valueChanged = YES;
            if (oldValue && newValue && [oldValue isKindOfClass:[NSDate class]] && [newValue isKindOfClass:[NSDate class]]) {
                // to avoid rounding errors, dates are flagged as changed only if the difference is significant enough (well below one second)
                valueChanged = fabs([oldValue timeIntervalSinceDate:newValue]) > 0.000001;
            }
            
            if (valueChanged) {
                changes[fieldName] = newValue ?: NSNull.null;
            }
        }
    }];

    return [changes copy];
}

- (NSArray *)changedFieldNames { return self.unsavedChanges.allKeys; }

- (FCModelSaveResult)save
{
    checkForOpenDatabaseFatal(YES);
    
    if (deleted) [[NSException exceptionWithName:@"FCAttemptToSaveAfterDelete" reason:@"Cannot save deleted instance" userInfo:nil] raise];
    
    NSDictionary *changes = self.unsavedChanges;
    BOOL dirty = changes.count;
    if (! dirty && existsInDatabase) return FCModelSaveNoChanges;
    
    BOOL update = existsInDatabase;
    NSArray *columnNames;
    NSMutableArray *values;
    
    NSString *tableName = NSStringFromClass(self.class);
    NSString *pkName = g_primaryKeyFieldName[self.class];
    id primaryKey = [self encodedValueForFieldName:pkName];
    NSAssert1(primaryKey, @"Cannot update %@ without primary key value", NSStringFromClass(self.class));
   
    if (update) {
        if (! [self shouldUpdate]) {
            [self saveWasRefused];
            return FCModelSaveRefused;
        }
        columnNames = [changes allKeys];
    } else {
        if (! [self shouldInsert]) {
            [self saveWasRefused];
            return FCModelSaveRefused;
        }
        NSMutableSet *columnNamesMinusPK = [[NSSet setWithArray:[g_fieldInfo[self.class] allKeys]] mutableCopy];
        [columnNamesMinusPK removeObject:pkName];
        columnNames = [columnNamesMinusPK allObjects];
    }

    // Validate NOT NULL columns
    [g_fieldInfo[self.class] enumerateKeysAndObjectsUsingBlock:^(id key, FCModelFieldInfo *info, BOOL *stop) {
        if (info.nullAllowed) return;
    
        id value = [self valueForKey:key];
        if (! value || value == NSNull.null) {
            [[NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Cannot save NULL to NOT NULL property %@.%@", tableName, key] userInfo:nil] raise];
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

    __block BOOL success = NO;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        success = [db executeUpdate:query withArgumentsInArray:values];
        if (success) {
            self._lastSQLiteError = nil;
        } else {
            self._lastSQLiteError = db.lastError;
        }
    }];
    
    if (! success) {
        [self saveDidFail];
        return FCModelSaveFailed;
    }
    
    NSMutableDictionary *newRowValues = self._rowValuesInDatabase ? [self._rowValuesInDatabase mutableCopy] : [NSMutableDictionary dictionary];
    [changes enumerateKeysAndObjectsUsingBlock:^(NSString *fieldName, id obj, BOOL *stop) {
        obj = [self serializedDatabaseRepresentationOfValue:(obj == NSNull.null ? nil : obj) forPropertyNamed:fieldName];
        newRowValues[fieldName] = obj ?: NSNull.null;
    }];
    self._rowValuesInDatabase = newRowValues;
    existsInDatabase = YES;
    
    if (update) {
        [self didUpdate];
        [self postChangeNotification:FCModelUpdateNotification];
        [self postChangeNotification:FCModelAnyChangeNotification];
    } else {
        [self didInsert];
        [self postChangeNotification:FCModelInsertNotification];
        [self postChangeNotification:FCModelAnyChangeNotification];
    }
    
    return FCModelSaveSucceeded;
}

- (FCModelSaveResult)delete
{
    checkForOpenDatabaseFatal(YES);
    
    if (deleted) return FCModelSaveNoChanges;
    if (! [self shouldDelete]) {
        [self saveWasRefused];
        return FCModelSaveRefused;
    }
    
    __block BOOL success = NO;
    [g_databaseQueue inDatabase:^(FMDatabase *db) {
        NSString *query = [self.class expandQuery:@"DELETE FROM \"$T\" WHERE \"$PK\" = ?"];
        success = [db executeUpdate:query, [self primaryKey]];
        self._lastSQLiteError = success ? nil : db.lastError;
    }];

    if (! success) {
        [self saveDidFail];
        return FCModelSaveFailed;
    }
    
    deleted = YES;
    existsInDatabase = NO;
    [self didDelete];
    [self postChangeNotification:FCModelDeleteNotification];
    [self postChangeNotification:FCModelAnyChangeNotification];
    [self removeUniqueInstance];
    
    return FCModelSaveSucceeded;
}

+ (void)saveAll
{
    checkForOpenDatabaseFatal(YES);
    [NSNotificationCenter.defaultCenter postNotificationName:FCModelSaveNotification object:nil userInfo:@{ FCModelClassKey : self }];
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
    return ((NSObject *)self.primaryKey).hash;
}

#pragma mark - Database management

+ (void)openDatabaseAtPath:(NSString *)path withSchemaBuilder:(void (^)(FMDatabase *db, int *schemaVersion))schemaBuilder { [self openDatabaseAtPath:path withDatabaseInitializer:nil schemaBuilder:schemaBuilder]; }

+ (void)openDatabaseAtPath:(NSString *)path withDatabaseInitializer:(void (^)(FMDatabase *db))databaseInitializer schemaBuilder:(void (^)(FMDatabase *db, int *schemaVersion))schemaBuilder
{
    g_databaseQueue = [[FCModelDatabaseQueue alloc] initWithDatabasePath:path];
    NSMutableDictionary *mutableFieldInfo = [NSMutableDictionary dictionary];
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
        NSMutableSet *autoincTables = [NSMutableSet set];
        FMResultSet *autoincRS = [db executeQuery:@"SELECT name FROM sqlite_master WHERE UPPER(sql) LIKE '%AUTOINCREMENT%'"];
        while ([autoincRS next]) {
            [autoincTables addObject:[autoincRS stringForColumnIndex:0]];
            NSLog(@"[FCModel] Warning: database table %@ uses AUTOINCREMENT, which FCModel no longer supports. Its behavior will be approximated.", [autoincRS stringForColumnIndex:0]);
        }
        [autoincRS close];
        if (autoincTables.count) g_tablesUsingAutoIncrementEmulation = [autoincTables copy];
        
        // Read schema for field names and primary keys
        FMResultSet *tablesRS = [db executeQuery:
            @"SELECT DISTINCT tbl_name FROM (SELECT * FROM sqlite_master UNION ALL SELECT * FROM sqlite_temp_master) WHERE type != 'meta' AND name NOT LIKE 'sqlite_%'"
       ];
        while ([tablesRS next]) {
            NSString *tableName = [tablesRS stringForColumnIndex:0];
            Class tableModelClass = NSClassFromString(tableName);
            if (! tableModelClass || ! [tableModelClass isSubclassOfClass:self]) continue;
            
            NSString *primaryKeyName = nil;
            BOOL isMultiColumnPrimaryKey = NO;
            NSMutableDictionary *fields = [NSMutableDictionary dictionary];
            FMResultSet *columnsRS = [db executeQuery:[NSString stringWithFormat: @"PRAGMA table_info('%@')", tableName]];
            while ([columnsRS next]) {
                NSString *fieldName = [columnsRS stringForColumnIndex:1];
                
                objc_property_t property = class_getProperty(tableModelClass, fieldName.UTF8String);
                if (! property) {
                    NSLog(@"[FCModel] ignoring column %@.%@, no matching model property", tableName, fieldName);
                    continue;
                }
                
                NSArray *propertyAttributes = [[NSString stringWithCString:property_getAttributes(property) encoding:NSASCIIStringEncoding]componentsSeparatedByString:@","];
                if ([propertyAttributes containsObject:@"R"]) {
                    NSLog(@"[FCModel] ignoring column %@.%@, matching model property is readonly", tableName, fieldName);
                    continue;
                }
                
                Class propertyClass;
                NSString *propertyClassName, *typeString = propertyAttributes.firstObject;
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
                if (isPK == 1) primaryKeyName = fieldName;
                else if (isPK > 1) isMultiColumnPrimaryKey = YES;

                NSString *fieldType = [columnsRS stringForColumnIndex:2];
                FCModelFieldInfo *info = [FCModelFieldInfo new];
                info.propertyClass = propertyClass;
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
            
            if (! primaryKeyName || isMultiColumnPrimaryKey) {
                [[NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"FCModel tables must have a single-column primary key, not found in %@", tableName] userInfo:nil] raise];
            }
            
            id classKey = tableModelClass;
            [mutableFieldInfo setObject:fields forKey:classKey];
            [mutablePrimaryKeyFieldName setObject:primaryKeyName forKey:classKey];
            [columnsRS close];
        }
        [tablesRS close];
    
        g_fieldInfo = [mutableFieldInfo copy];
        g_primaryKeyFieldName = [mutablePrimaryKeyFieldName copy];
    }];
}

+ (BOOL)closeDatabase
{
    [FCModelCachedObject clearCache];

    __block BOOL modelsAreStillLoaded = NO;
    dispatch_semaphore_wait(g_instancesReadLock, DISPATCH_TIME_FOREVER);
    [g_instances enumerateKeysAndObjectsUsingBlock:^(Class class, NSMapTable *classInstances, BOOL *stop) {
        for (id primaryKeyValue in classInstances.keyEnumerator.allObjects) {
            modelsAreStillLoaded = YES;
            NSLog(@"[FCModel] closeDatabase: %@ ID %@ is still retained by something and is being abandoned by FCModel. This can cause weird bugs. Don't let this happen.", NSStringFromClass(class), primaryKeyValue);
        }
    }];
    [g_instances removeAllObjects];
    dispatch_semaphore_signal(g_instancesReadLock);

    [g_databaseQueue close];
    g_databaseQueue = nil;
    g_primaryKeyFieldName = nil;
    g_fieldInfo = nil;
    g_tablesUsingAutoIncrementEmulation = nil;
    g_enqueuedBatchNotifications = nil;

    return ! modelsAreStillLoaded;
}

+ (BOOL)databaseIsOpen { return (BOOL) g_databaseQueue; }

+ (void)inDatabaseSync:(void (^)(FMDatabase *db))block
{
    checkForOpenDatabaseFatal(YES);
    [g_databaseQueue inDatabase:block];
}

#pragma mark - Batch notification queuing

+ (dispatch_semaphore_t)notificationBatchLock
{
    static dispatch_once_t onceToken;
    static dispatch_semaphore_t lock;
    dispatch_once(&onceToken, ^{
        lock = dispatch_semaphore_create(1);
    });
    return lock;
}

+ (void)beginNotificationBatch
{
    dispatch_semaphore_t lock = [self notificationBatchLock];
    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
    if (! g_enqueuedBatchNotifications) {
        g_enqueuedBatchNotifications = [NSMutableDictionary dictionary];
    }
    dispatch_semaphore_signal(lock);
}

+ (void)endNotificationBatchAndNotify:(BOOL)sendQueuedNotifications
{
    if (! g_enqueuedBatchNotifications) return;

    dispatch_semaphore_t lock = [self notificationBatchLock];    
    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
    NSDictionary *notificationsToSend = sendQueuedNotifications ? [g_enqueuedBatchNotifications copy] : nil;
    g_enqueuedBatchNotifications = nil;
    dispatch_semaphore_signal(lock);
    
    if (sendQueuedNotifications) {
        onMainThreadAsync(^{
            [notificationsToSend enumerateKeysAndObjectsUsingBlock:^(Class class, NSDictionary *notificationsForClass, BOOL *stopOuter) {
                [notificationsForClass enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSSet *objects, BOOL *stopInner) {
                    [NSNotificationCenter.defaultCenter postNotificationName:name object:class userInfo:@{
                        FCModelInstanceSetKey : objects
                    }];
                }];
            }];
        });
    }
}

- (void)postChangeNotification:(NSString *)name
{
    BOOL enqueued = NO;
    
    dispatch_semaphore_t lock = [self.class notificationBatchLock];
    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
    if (g_enqueuedBatchNotifications) {
        id class = self.class;
        NSMutableDictionary *notificationsForClass = g_enqueuedBatchNotifications[class];
        if (! notificationsForClass) {
            notificationsForClass = [NSMutableDictionary dictionary];
            g_enqueuedBatchNotifications[class] = notificationsForClass;
        }
        
        NSMutableSet *instancesForNotification = notificationsForClass[name];
        if (instancesForNotification) {
            [instancesForNotification addObject:self];
        } else {
            instancesForNotification = [NSMutableSet setWithObject:self];
            notificationsForClass[name] = instancesForNotification;
        }
        
        enqueued = YES;
    }
    dispatch_semaphore_signal(lock);
    
    if (! enqueued) {
        onMainThreadAsync(^{
            [NSNotificationCenter.defaultCenter postNotificationName:name object:self.class userInfo:@{
                FCModelInstanceSetKey : [NSSet setWithObject:self]
            }];
        });
    }
}

@end
