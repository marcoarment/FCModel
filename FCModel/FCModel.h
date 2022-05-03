//
//  FCModel.h
//
//  Created by Marco Arment on 7/18/13.
//  Copyright (c) 2013-2020 Marco Arment. See included LICENSE file.
//

#import <Foundation/Foundation.h>
#include <AvailabilityMacros.h>

#ifdef COCOAPODS
#import <FMDB/FMDatabase.h>
#else
#import "FMDatabase.h"
#endif

extern NSString * _Nonnull const FCModelException;

@class FCModelFieldInfo;

// These notifications use the relevant model's Class as the "object" for convenience so observers can,
//  for instance, observe every update to any instance of the Person class:
//
//  [NSNotificationCenter.defaultCenter addObserver:... selector:... name:FCModelUpdateNotification object:Person.class];
//
// Or set object to nil to get notified of operations to all FCModels.
//
extern NSString * _Nonnull const FCModelChangeNotification; // Any insert, update, or delete in the table.
//
// userInfo[FCModelInstanceKey] is the specific FCModel instance that has changed. If this key is absent, multiple instances may have changed.
//
extern NSString * _Nonnull const FCModelInstanceKey;
//
// userInfo[FCModelChangedFieldsKey] is an NSSet of NSString field names.
// "Changed" field names may be overly inclusive: all named fields may not *actually* have changed, but all actual changes will be in the set.
//
extern NSString * _Nonnull const FCModelChangedFieldsKey;
//
// userInfo[FCModelOldFieldValuesKey] is an NSDictionary of NSString field names to values.
// Only included in update notifications.
// If included, it may be overly inclusive: all specified fields may not *actually* have changed, but all actual changes will be present.
//
extern NSString * _Nonnull const FCModelOldFieldValuesKey;
//
// userInfo[FCModelChangeTypeKey] is an NSNumber from the following enum:
//
extern NSString * _Nonnull const FCModelChangeTypeKey;

typedef NS_ENUM(NSInteger, FCModelChangeType) {
    FCModelChangeTypeUnspecified, // Any change or changes may have been made
    FCModelChangeTypeInsert,      // The object in FCModelInstanceKey is non-nil, and was inserted into the database
    FCModelChangeTypeUpdate,      // The object in FCModelInstanceKey is non-nil, and was updated in the database
    FCModelChangeTypeDelete       // The object in FCModelInstanceKey is non-nil, and was deleted from the database
};


@interface FCModel : NSObject

@property (readonly) id _Nullable primaryKey;
@property (readonly) NSDictionary * _Nonnull allFields;
@property (readonly) BOOL hasUnsavedChanges;
@property (readonly) BOOL existsInDatabase; // either deleted or never saved
@property (readonly) BOOL isDeleted;

// Swift classes have their module name prefixed onto their Objective-C class. To use FCModel with Swift, provide your module name.
// You can find it in Xcode under Build Settings -> Product Module Name.
+ (void)openDatabaseAtPath:(NSString * _Nonnull)path withDatabaseInitializer:(void (^ _Nullable)(FMDatabase * _Nonnull db))databaseInitializer schemaBuilder:(void (^ _Nonnull)(FMDatabase * _Nonnull db, int * _Nonnull schemaVersion))schemaBuilder;
+ (void)openDatabaseAtPath:(NSString * _Nonnull)path withDatabaseInitializer:(void (^ _Nullable)(FMDatabase * _Nonnull db))databaseInitializer schemaBuilder:(void (^ _Nonnull)(FMDatabase * _Nonnull db, int * _Nonnull schemaVersion))schemaBuilder moduleName:(NSString * _Nullable)moduleName;

+ (NSArray * _Nullable)databaseFieldNames;
+ (NSString * _Nullable)primaryKeyFieldName;

// Feel free to operate on the same database object with your own queries. They'll be
//  executed synchronously on FCModel's private database-operation queue.
//
+ (void)inDatabaseSync:(void (^ _Nonnull)(FMDatabase * _Nonnull db))block;

+ (void)inDatabaseSyncWithoutChangeNotifications:(void (^ _Nonnull)(FMDatabase * _Nonnull db))block;

// Convenience method that offers $T/$PK parsing when doing manual batch updates
//
+ (void)executeUpdateQuery:(NSString * _Nullable)query, ...;
+ (void)executeUpdateQuery:(NSString * _Nullable)query arguments:(NSArray * _Nullable)args;

// CRUD basics
+ (instancetype _Nullable)instanceWithPrimaryKey:(id _Nullable)primaryKeyValue; // will create if nonexistent
+ (instancetype _Nullable)instanceWithPrimaryKey:(id _Nullable)primaryKeyValue createIfNonexistent:(BOOL)create; // will return nil if nonexistent

- (instancetype _Nullable)initWithPrimaryKey:(id _Nullable)primaryKeyValue;
- (instancetype _Nullable)initWithPrimaryKey:(id _Nullable)primaryKeyValue createIfNonexistent:(BOOL)create;

- (NSArray * _Nonnull)changedFieldNames;
- (void)revertUnsavedChanges;
- (void)revertUnsavedChangeToFieldName:(NSString * _Nonnull)fieldName;
- (void)delete;

// SELECTs allow optional query placeholders:
//      $T  - This model's table name
//      $PK - This model's primary-key field name
//
// The variadic and array equivalents otherwise behave identically. "arguments" arrays can be nil.

+ (NSArray * _Nullable)allInstances;

+ (instancetype _Nullable)firstInstanceWhere:(NSString * _Nullable)queryAfterWHERE, ...;
+ (instancetype _Nullable)firstInstanceWhere:(NSString * _Nullable)queryAfterWHERE arguments:(NSArray * _Nullable)arguments;

+ (NSArray * _Nullable)instancesWhere:(NSString * _Nullable)queryAfterWHERE, ...;
+ (NSArray * _Nullable)instancesWhere:(NSString * _Nullable)queryAfterWHERE arguments:(NSArray * _Nullable)array;

+ (instancetype _Nullable)firstInstanceOrderedBy:(NSString * _Nullable)queryAfterORDERBY, ...;
+ (instancetype _Nullable)firstInstanceOrderedBy:(NSString * _Nullable)queryAfterORDERBY arguments:(NSArray * _Nullable)arguments;

+ (NSArray * _Nullable)instancesOrderedBy:(NSString * _Nullable)queryAfterORDERBY, ...;
+ (NSArray * _Nullable)instancesOrderedBy:(NSString * _Nullable)queryAfterORDERBY arguments:(NSArray * _Nullable)arguments;

+ (NSUInteger)numberOfInstances;
+ (NSUInteger)numberOfInstancesWhere:(NSString * _Nullable)queryAfterWHERE, ...;
+ (NSUInteger)numberOfInstancesWhere:(NSString * _Nullable)queryAfterWHERE arguments:(NSArray * _Nullable)arguments;

// Batch-operate on instances matching a set of primary keys, i.e. "WHERE key IN (...)"
// Note: "ORDER BY" clauses should not be included in the andWhere strings, since these may execute multiple queries and ordering may not be consistent
+ (NSArray * _Nullable)instancesWithPrimaryKeyValues:(NSArray * _Nullable)primaryKeyValues;
+ (NSArray * _Nullable)instancesWherePrimaryKeyValueIn:(NSArray * _Nullable)primaryKeyValues andWhere:(NSString * _Nullable)additionalWhereClause arguments:(NSArray * _Nullable)additionalWhereArguments;
+ (NSUInteger)numberOfInstancesWherePrimaryKeyValueIn:(NSArray * _Nullable)primaryKeyValues andWhere:(NSString * _Nullable)additionalWhereClause arguments:(NSArray * _Nullable)additionalWhereArguments;
+ (void)executeUpdateQuerySet:(NSString * _Nonnull)setClause setArguments:(NSArray * _Nonnull)setArguments wherePrimaryKeyValueIn:(NSArray * _Nullable)primaryKeyValues andWhere:(NSString * _Nullable)additionalWhereClause arguments:(NSArray * _Nullable)additionalWhereArguments;

// Return data instead of completed objects (convenient accessors to FCModel's database queue with $T/$PK parsing)
+ (NSArray * _Nullable)resultDictionariesFromQuery:(NSString * _Nullable)query, ...;
+ (NSArray * _Nullable)resultDictionariesFromQuery:(NSString * _Nullable)query arguments:(NSArray * _Nullable)arguments;

+ (NSArray * _Nullable)firstColumnArrayFromQuery:(NSString * _Nullable)query, ...;
+ (NSArray * _Nullable)firstColumnArrayFromQuery:(NSString * _Nullable)query arguments:(NSArray * _Nullable)arguments;

+ (id _Nullable)firstValueFromQuery:(NSString * _Nullable)query, ...;
+ (id _Nullable)firstValueFromQuery:(NSString * _Nullable)query arguments:(NSArray * _Nullable)arguments;

// These methods use a global query cache (in FCModelCachedObject). Results are cached indefinitely until their
//  table has any writes or there's a system low-memory warning, at which point they automatically invalidate.
//  You can customize whether invalidations are triggered with the optional ignoreFieldsForInvalidation: params.
// The next subsequent request will repopulate the cached data, either by querying the DB (cachedInstancesWhere)
//  or calling the generator block (cachedObjectWithIdentifier).
//
+ (NSArray * _Nullable)cachedAllInstances;
+ (NSArray * _Nullable)cachedInstancesWhere:(NSString * _Nullable)queryAfterWHERE arguments:(NSArray * _Nullable)arguments;
+ (NSArray * _Nullable)cachedInstancesWhere:(NSString * _Nullable)queryAfterWHERE arguments:(NSArray * _Nullable)arguments ignoreFieldsForInvalidation:(NSSet * _Nullable)ignoredFields;
+ (id _Nullable)cachedObjectWithIdentifier:(id _Nonnull)identifier generator:(id _Nullable (^ _Nonnull)(void))generatorBlock;
+ (id _Nullable)cachedObjectWithIdentifier:(id _Nonnull)identifier ignoreFieldsForInvalidation:(NSSet * _Nullable)ignoredFields generator:(id _Nullable (^ _Nonnull)(void))generatorBlock;

// For subclasses to override, optional:
- (void)didInit;

+ (NSSet * _Nonnull)ignoredFieldNames; // Fields that exist in the table but should not be read into the model. Default empty set, cannot be nil.

// Safe-writing helpers:
//  - reload: reloads the current database values into this instance, overwriting any unsaved changes
//
//  - save:modificiationsBlock: Performs a "safe save" intended to prevent race conditions between loading, modifying, and saving.
//      Simply make your modifications on the instance you're working on inside the block, e.g.:
//
//      [person save:^{
//          person.name = @"Susan";
//      }];
//
//  Both return YES if the transaction succeeded. May return NO if, for instance, the instance gets deleted beforehand.
//
- (BOOL)reload;
- (BOOL)save:(void (^ _Nullable)(void))modificiationsBlock;
- (BOOL)saveWithoutChangeNotifications:(void (^ _Nullable)(void))modificiationsBlock;

// When using SwiftUI/Combine, call this to trigger a refresh manually if you modify fields outside of
//  the usual save/reload/update methods, or after modifying other properties that aren't database columns
- (void)observableObjectPropertiesWillChange;

// Notification shortcuts: call on an FCModel subclass to be notified for only changes to certain fields
+ (void)addObserver:(id _Nonnull)target selector:(SEL _Nonnull)action forChangedFields:(NSSet * _Nullable)fieldNamesToWatch;
+ (void)addObserver:(id _Nonnull)target selector:(SEL _Nonnull)action forAnyChangedFieldsExcept:(NSSet * _Nullable)fieldNamesToIgnore;
+ (void)removeObserverForFieldChanges:(id _Nonnull)target;

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
+ (id _Nonnull)primaryKeyValueForNewInstance;

// Transactions:
//  - Cannot be nested
//  - Enqueue and coalesce change notifications until commit (and are discarded if the transaction is rolled back)
//  - Do not automatically "revert" changed model instances in memory after rolled-back value changes
//
+ (void)performTransaction:(BOOL (^ _Nonnull)(void))block; // return YES to commit, NO to roll back
+ (BOOL)isInTransaction;

// This variant has no control over commit/rollback; safe to potentially nest inside other transactions if you only want performance
+ (void)performInTransactionForPerformance:(void (^ _Nonnull)(void))block;

// Field info: You probably won't need this most of the time, but it's nice to have sometimes. FCModel's generating this privately
//  anyway, so you might as well have read-only access to it if it can help you avoid some code. (I've already needed it.)
//
+ (FCModelFieldInfo * _Nullable)infoForFieldName:(NSString * _Nonnull)fieldName;

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

// All instances of the called class in memory. Call on a subclass, not FCModel directly. You probably don't need this, until you do.
+ (NSArray * _Nonnull)allLoadedInstances;

// Issues SQLite VACUUM to rebuild database and recover deleted pages. Returns NO if a transaction is in progress that prevents it.
+ (BOOL)vacuumIfPossible;

// Provide a custom handler for any SQLite errors when performing queries. If unspecified or NULL, proposedException is raised on errors.
+ (void)setQueryFailedHandler:(void (^ _Nullable)(NSException * _Nonnull proposedException, int dbErrorCode, NSString * _Nonnull dbErrorMessage))handler;

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
@property (nonatomic, readonly) id _Nullable defaultValue;
@property (nonatomic, readonly) Class _Nullable propertyClass;
@property (nonatomic, readonly) NSString * _Nonnull propertyTypeEncoding;
@end

