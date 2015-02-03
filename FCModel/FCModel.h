//
//  FCModel.h
//
//  Created by Marco Arment on 7/18/13.
//  Copyright (c) 2013-2014 Marco Arment. See included LICENSE file.
//

#import <Foundation/Foundation.h>
#include <AvailabilityMacros.h>

#ifdef COCOAPODS
#import <FMDB/FMDatabase.h>
#else
#import "FMDatabase.h"
#endif

extern NSString * const FCModelException;

@class FCModelFieldInfo;

// These notifications use the relevant model's Class as the "object" for convenience so observers can,
//  for instance, observe every update to any instance of the Person class:
//
//  [NSNotificationCenter.defaultCenter addObserver:... selector:... name:FCModelUpdateNotification object:Person.class];
//
// Or set object to nil to get notified of operations to all FCModels.
//
extern NSString * const FCModelChangeNotification; // Any insert, update, or delete in the table.
//
// userInfo[FCModelInstanceKey] is the specific FCModel instance that has changed. If this key is absent, multiple instances may have changed.
//
extern NSString * const FCModelInstanceKey;
//
// userInfo[FCModelChangedFieldsKey] is an NSSet of NSString field names.
// "Changed" field names may be overly inclusive: all named fields may not *actually* have changed, but all actual changes will be in the set.
//
extern NSString * const FCModelChangedFieldsKey;


@interface FCModel : NSObject <NSCopying>

@property (readonly) id primaryKey;
@property (readonly) NSDictionary *allFields;
@property (readonly) BOOL hasUnsavedChanges;
@property (readonly) BOOL existsInDatabase; // either deleted or never saved
@property (readonly) BOOL isDeleted;

+ (void)openDatabaseAtPath:(NSString *)path withDatabaseInitializer:(void (^)(FMDatabase *db))databaseInitializer schemaBuilder:(void (^)(FMDatabase *db, int *schemaVersion))schemaBuilder;

+ (NSArray *)databaseFieldNames;
+ (NSString *)primaryKeyFieldName;

// Feel free to operate on the same database object with your own queries. They'll be
//  executed synchronously on FCModel's private database-operation queue.
//
+ (void)inDatabaseSync:(void (^)(FMDatabase *db))block;

// Convenience method that offers $T/$PK parsing when doing manual batch updates
//
+ (void)executeUpdateQuery:(NSString *)query, ...;
+ (void)executeUpdateQuery:(NSString *)query arguments:(NSArray *)args;

// CRUD basics
+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue; // will create if nonexistent
+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue createIfNonexistent:(BOOL)create; // will return nil if nonexistent
- (NSArray *)changedFieldNames;
- (void)revertUnsavedChanges;
- (void)revertUnsavedChangeToFieldName:(NSString *)fieldName;
- (void)delete;
- (BOOL)save; // returns YES if there were any changes

// SELECTs allow optional query placeholders:
//      $T  - This model's table name
//      $PK - This model's primary-key field name
//
// The variadic and array equivalents otherwise behave identically. "arguments" arrays can be nil.

+ (NSArray *)allInstances;

+ (instancetype)firstInstanceWhere:(NSString *)queryAfterWHERE, ...;
+ (instancetype)firstInstanceWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)arguments;

+ (NSArray *)instancesWhere:(NSString *)queryAfterWHERE, ...;
+ (NSArray *)instancesWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)array;

+ (instancetype)firstInstanceOrderedBy:(NSString *)queryAfterORDERBY, ...;
+ (instancetype)firstInstanceOrderedBy:(NSString *)queryAfterORDERBY arguments:(NSArray *)arguments;

+ (NSArray *)instancesOrderedBy:(NSString *)queryAfterORDERBY, ...;
+ (NSArray *)instancesOrderedBy:(NSString *)queryAfterORDERBY arguments:(NSArray *)arguments;

+ (NSUInteger)numberOfInstances;
+ (NSUInteger)numberOfInstancesWhere:(NSString *)queryAfterWHERE, ...;
+ (NSUInteger)numberOfInstancesWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)arguments;

// Fetch a set of primary keys, i.e. "WHERE key IN (...)"
+ (NSArray *)instancesWithPrimaryKeyValues:(NSArray *)primaryKeyValues;

// Return data instead of completed objects (convenient accessors to FCModel's database queue with $T/$PK parsing)
+ (NSArray *)resultDictionariesFromQuery:(NSString *)query, ...;
+ (NSArray *)resultDictionariesFromQuery:(NSString *)query arguments:(NSArray *)arguments;

+ (NSArray *)firstColumnArrayFromQuery:(NSString *)query, ...;
+ (NSArray *)firstColumnArrayFromQuery:(NSString *)query arguments:(NSArray *)arguments;

+ (id)firstValueFromQuery:(NSString *)query, ...;
+ (id)firstValueFromQuery:(NSString *)query arguments:(NSArray *)arguments;

// These methods use a global query cache (in FCModelCachedObject). Results are cached indefinitely until their
//  table has any writes or there's a system low-memory warning, at which point they automatically invalidate.
//  You can customize whether invalidations are triggered with the optional ignoreFieldsForInvalidation: params.
// The next subsequent request will repopulate the cached data, either by querying the DB (cachedInstancesWhere)
//  or calling the generator block (cachedObjectWithIdentifier).
//
+ (NSArray *)cachedInstancesWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)arguments;
+ (NSArray *)cachedInstancesWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)arguments ignoreFieldsForInvalidation:(NSSet *)ignoredFields;
+ (id)cachedObjectWithIdentifier:(id)identifier generator:(id (^)(void))generatorBlock;
+ (id)cachedObjectWithIdentifier:(id)identifier ignoreFieldsForInvalidation:(NSSet *)ignoredFields generator:(id (^)(void))generatorBlock;

// For subclasses to override, optional:
- (void)didInit;

+ (NSSet *)ignoredFieldNames; // Fields that exist in the table but should not be read into the model. Default empty set, cannot be nil.

// Safe-writing helpers:
//  - reload: reloads the current database values into this instance, overwriting any unsaved changes
//
//  - reloadAndSave:modificiationsBlock: Performs a "safe save" intended to prevent race conditions between loading, modifying, and saving.
//      Don't call -save within modificiationsBlock -- simply make your modifications on the instance you're working on, e.g.:
//
//      [person reloadAndSave:^{
//          person.name = @"Susan";
//      }];
//
//  Both return YES if the transaction succeeded. May return NO if, for instance, the instance gets deleted beforehand.
//
- (BOOL)reload;
- (BOOL)reloadAndSave:(void (^)())modificiationsBlock;

// Notification shortcuts: call on an FCModel subclass to be notified for only changes to certain fields
+ (void)addObserver:(id)target selector:(SEL)action forChangedFields:(NSSet *)fieldNamesToWatch;
+ (void)addObserver:(id)target selector:(SEL)action forAnyChangedFieldsExcept:(NSSet *)fieldNamesToIgnore;
+ (void)removeObserverForFieldChanges:(id)target;

// To create new records with supplied primary-key values, call instanceWithPrimaryKey:, then save when done
//  setting other fields.
//
// This method is only called if you call +new to create a new instance with an automatic primary-key value.
//
// By default, this method generates random int64_t values. Subclasses may override it to e.g. use UUID strings
//  or other values, but the values must be unique within the table. If you return something that already exists
//  in the table or in an unsaved in-memory instance, FCModel will keep calling this up to 100 times looking for
//  a unique value before raising an exception.
//
+ (id)primaryKeyValueForNewInstance;

// Transactions:
//  - Cannot be nested
//  - Enqueue and coalesce change notifications until commit (and are discarded if the transaction is rolled back)
//  - Do not automatically "revert" changed model instances in memory after rolled-back value changes
//
+ (void)performTransaction:(BOOL (^)())block; // return YES to commit, NO to roll back
+ (BOOL)isInTransaction;

// Field info: You probably won't need this most of the time, but it's nice to have sometimes. FCModel's generating this privately
//  anyway, so you might as well have read-only access to it if it can help you avoid some code. (I've already needed it.)
//
+ (FCModelFieldInfo *)infoForFieldName:(NSString *)fieldName;

// Value Transformer: If you wish to store non-native objects, a reversible value transformer must be provided
+ (NSValueTransformer *)valueTransformerForFieldName:(NSString *)fieldName;

// Closing the database is not necessary in most cases. Only close it if you need to, such as if you need to delete and recreate
//  the database file. Warning: Any FCModel call after closing will bizarrely fail until you call openDatabaseAtPath: again.
//
+ (void)closeDatabase;

// If you try to use FCModel while the database is closed, an error will be logged to the console on any relevant calls.
// Read/info/SELECT methods will return nil when possible, but these will throw exceptions:
//  -save
//  -delete
//  -executeUpdateQuery:
//  -inDatabaseSync:
//
// You can determine if the database is currently open:
//
+ (BOOL)databaseIsOpen;

@end


typedef NS_ENUM(NSInteger, FCModelFieldType) {
    FCModelFieldTypeOther = 0,
    FCModelFieldTypeText,
    FCModelFieldTypeInteger,
    FCModelFieldTypeDouble,
    FCModelFieldTypeBool
};

@interface FCModelFieldInfo : NSObject
@property (nonatomic, readonly) BOOL nullAllowed;
@property (nonatomic, readonly) FCModelFieldType type;
@property (nonatomic, readonly) id defaultValue;
@property (nonatomic, readonly) Class propertyClass;
@property (nonatomic, readonly) NSString *propertyTypeEncoding;
@end

