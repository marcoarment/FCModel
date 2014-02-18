//
//  FCModel.h
//
//  Created by Marco Arment on 7/18/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifdef COCOAPODS
#import <FMDB/FMDatabase.h>
#import <FMDB/FMDatabaseQueue.h>
#else
#import "FMDatabase.h"
#import "FMDatabaseQueue.h"
#endif

// These notifications use the relevant model's Class as the "object" for convenience so observers can,
//  for instance, observe every update to any instance of the Person class:
//
//  [NSNotificationCenter.defaultCenter addObserver:... selector:... name:FCModelUpdateNotification object:Person.class];
//
// The specific instance or instances acted upon are passed as an NSSet in userInfo[FCModelInstanceSetKey].
// The set will always contain exactly one instance unless you use beginNotificationBatch/endNotificationBatchAndNotify.
//
extern NSString * const FCModelInsertNotification;
extern NSString * const FCModelUpdateNotification;
extern NSString * const FCModelDeleteNotification;
extern NSString * const FCModelInstanceSetKey;

typedef NS_ENUM(NSInteger, FCModelSaveResult) {
    FCModelSaveFailed = 0, // SQLite refused a query. Check .lastSQLiteError
    FCModelSaveRefused,    // The instance blocked the operation from a should* method.
    FCModelSaveSucceeded,
    FCModelSaveNoChanges
};

@interface FCModel : NSObject

@property (readonly) id primaryKey;
@property (readonly) NSDictionary *allFields;
@property (readonly) BOOL hasUnsavedChanges;
@property (readonly) BOOL existsInDatabase;
@property (readonly) NSError *lastSQLiteError;

+ (void)openDatabaseAtPath:(NSString *)path withSchemaBuilder:(void (^)(FMDatabase *db, int *schemaVersion))schemaBuilder;
+ (void)openDatabaseAtPath:(NSString *)path withDatabaseInitializer:(void (^)(FMDatabase *db))databaseInitializer schemaBuilder:(void (^)(FMDatabase *db, int *schemaVersion))schemaBuilder;

+ (NSArray *)databaseFieldNames;
+ (NSString *)primaryKeyFieldName;

// Be careful with this -- the array could be out of date by the time you use it
//  if a new instance is loaded by another thread. Everything in it is guaranteed
//  to be a loaded instance, but you're not guaranteed to always have *all* of them
//  if you perform SELECTs from multiple threads.
+ (NSArray *)allLoadedInstances;

// Feel free to operate on the same database queue with your own queries (IMPORTANT: READ THE NEXT METHOD DEFINITION)
+ (FMDatabaseQueue *)databaseQueue;

// Call if you perform INSERT/UPDATE/DELETE outside of the instance*/save methods.
// This will cause any instances in existence to reload their data from the database.
//
//  - Call on a subclass to reload all instances of that model and any subclasses.
//  - Call on FCModel to reload all instances of ALL models.
//
+ (void)dataWasUpdatedExternally;

// Or use this convenience method, which calls dataWasUpdatedExternally automatically and offers $T/$PK parsing.
// If you don't know which tables will be affected, or if it will affect more than one, call on FCModel, not a subclass.
// Only call on a subclass if only that model's table will be affected.
+ (NSError *)executeUpdateQuery:(NSString *)query, ...;

// CRUD basics
+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue; // will create if nonexistent
+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue createIfNonexistent:(BOOL)create;
- (FCModelSaveResult)revertUnsavedChanges;
- (FCModelSaveResult)revertUnsavedChangeToFieldName:(NSString *)fieldName;
- (FCModelSaveResult)delete;
- (FCModelSaveResult)save;
+ (void)saveAll; // Resolved by class: call on FCModel to save all, on a subclass to save just those and their subclasses, etc.

// SELECTs
// - "keyed" variants return dictionaries keyed by each instance's primary-key value.
// - "FromResultSet" variants will iterate through the supplied result set, but the caller is still responsible for closing it.
// - "countOf" variants return an NSNumber count, or nil on error.
// - Optional query placeholders:
//      $T  - This model's table name
//      $PK - This model's primary-key field name
//
+ (NSArray *)allInstances;
+ (NSDictionary *)keyedAllInstances;
+ (NSNumber *)countOfInstances;

+ (NSArray *)instancesFromResultSet:(FMResultSet *)rs;
+ (NSDictionary *)keyedInstancesFromResultSet:(FMResultSet *)rs;
+ (instancetype)firstInstanceFromResultSet:(FMResultSet *)rs;

+ (instancetype)firstInstanceWhere:(NSString *)queryAfterWHERE, ...;
+ (NSArray *)instancesWhere:(NSString *)queryAfterWHERE, ...;
+ (NSDictionary *)keyedInstancesWhere:(NSString *)queryAfterWHERE, ...;
+ (NSNumber *)countOfInstancesWhere:(NSString *)queryAfterWHERE, ...;

+ (instancetype)firstInstanceOrderedBy:(NSString *)queryAfterORDERBY, ...;
+ (NSArray *)instancesOrderedBy:(NSString *)queryAfterORDERBY, ...;

+ (NSUInteger)numberOfInstances;
+ (NSUInteger)numberOfInstancesWhere:(NSString *)queryAfterWHERE, ...;

// Fetch a set of primary keys, i.e. "WHERE key IN (...)"
+ (NSArray *)instancesWithPrimaryKeyValues:(NSArray *)primaryKeyValues;
+ (NSDictionary *)keyedInstancesWithPrimaryKeyValues:(NSArray *)primaryKeyValues;

// Return data instead of completed objects (convenient accessors to FCModel's database queue with $T/$PK parsing)
+ (NSArray *)resultDictionariesFromQuery:(NSString *)query, ...;
+ (NSArray *)firstColumnArrayFromQuery:(NSString *)query, ...;
+ (id)firstValueFromQuery:(NSString *)query, ...;


// For subclasses to override, all optional:

+ (NSString *)tableName; // By default, the class name is used
- (void)didInit;
- (BOOL)shouldInsert;
- (BOOL)shouldUpdate;
- (BOOL)shouldDelete;
- (void)didInsert;
- (void)didUpdate;
- (void)didDelete;
- (void)saveWasRefused;
- (void)saveDidFail;

// A bit redundant with KVO, but friendlier to multi-level subclassing, and only called for
//  meaningful changes (not setting to same value, or initially loading from the database)
//  on non-primary-key database columns.
//
- (void)didChangeValueForFieldName:(NSString *)fieldName fromValue:(id)oldValue toValue:(id)newValue;

// Subclasses can customize how properties are serialized for the database.
//
// FCModel automatically handles numeric primitives, NSString, NSNumber, NSData, NSURL, NSDate, NSDictionary, and NSArray.
// (Note that NSDate is stored as a time_t, so values before 1970 won't serialize properly.)
//
// To override this behavior or customize it for other types, you can implement these methods.
// You MUST call the super implementation for values that you're not handling.
//
// Database values may be NSString or NSNumber for INTEGER/FLOAT/TEXT columns, or NSData for BLOB columns.
//
- (id)serializedDatabaseRepresentationOfValue:(id)instanceValue forPropertyNamed:(NSString *)propertyName;
- (id)unserializedRepresentationOfDatabaseValue:(id)databaseValue forPropertyNamed:(NSString *)propertyName;

// Called on subclasses if there's a reload conflict:
//  - The instance changes field X but doesn't save the changes to the database.
//  - Database updates are executed outside of FCModel that cause instances to reload their data.
//  - This instance's value for field X in the database is different from the unsaved value it has.
//
// The default implementation raises an exception, so implement this if you use +dataWasUpdatedExternally or +executeUpdateQuery,
//  and don't call super.
//
- (id)valueOfFieldName:(NSString *)fieldName byResolvingReloadConflictWithDatabaseValue:(id)valueInDatabase;

// Notification batches and queuing:
//
// A common pattern is to listen for FCModelInsert/Update/DeleteNotification and reload a table or take other expensive UI operations.
// When small numbers of instances are updated/deleted during normal use, that's fine. But when doing a large operation in which
//  hundreds or thousands of instances might be changed, responding to these notifications may cause noticeable performance problems.
//
// Using this batch-queuing system, you can temporarily suspend delivery of these notifications, then deliver or discard them.
// Multiple identical notification types for each class will be collected into one. For instance:
//
// Without notification batching:
//
//     FCModelInsertNotification: Person class, { Sue }
//     FCModelUpdateNotification: Person class, { Robert }
//     FCModelUpdateNotification: Person class, { Sarah }
//     FCModelUpdateNotification: Person class, { James }
//     FCModelUpdateNotification: Person class, { Kate }
//     FCModelDeleteNotification: Person class, { Richard }
//
// With notification batching:
//
//     FCModelInsertNotification: Person class, { Sue }
//     FCModelUpdateNotification: Person class, { Robert, Sarah, James, Kate }
//     FCModelDeleteNotification: Person class, { Richard }
//
// Be careful: batch notification order is not preserved, and you may be unexpectedly interacting with deleted instances.
// Always check the given instances' .existsInDatabase property.
//
+ (void)beginNotificationBatch;
+ (void)endNotificationBatchAndNotify:(BOOL)sendQueuedNotifications;

@end
