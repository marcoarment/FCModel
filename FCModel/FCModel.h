//
//  FCModel.h
//
//  Created by Marco Arment on 7/18/13.
//  Copyright (c) 2013-2014 Marco Arment. See included LICENSE file.
//

#import <Foundation/Foundation.h>

#ifdef COCOAPODS
#import <FMDB/FMDatabase.h>
#else
#import "FMDatabase.h"
#endif

@class FCModelFieldInfo;

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

// Like the above with using the Class as the object, except that this one doesn't get a set of changed instances,
//  fires on any insert, update, or delete, and also fires after calls to dataWasUpdatedExternally and executeUpdateQuery:.
// If you find yourself subscribing to all three insert/update/delete notifications to do something like reload a tableview,
//  this is probably what you want instead.
//
extern NSString * const FCModelAnyChangeNotification;


// During dataWasUpdatedExternally and executeUpdateQuery:, this is called immediately before FCModel tells all loaded
//  instances of the affected class to reload themselves. Reloading can be time-consuming if many instances are in memory,
//  so this is a good time to release any unnecessarily retained instances so they don't need to go through the reload.
//
// (You probably don't need to care about this. Until you do.)
//
extern NSString * const FCModelWillReloadNotification;


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

// Feel free to operate on the same database object with your own queries. They'll be
//  executed synchronously on FCModel's private database-operation queue.
//  (IMPORTANT: READ THE NEXT METHOD DEFINITION)
+ (void)inDatabaseSync:(void (^)(FMDatabase *db))block;

// Call if you perform INSERT/UPDATE/DELETE on any FCModel table outside of the instance*/save
// methods. This will cause any instances in existence to reload their data from the database.
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
+ (instancetype)instanceWithPrimaryKey:(id)primaryKeyValue createIfNonexistent:(BOOL)create; // will return nil if nonexistent
- (NSArray *)changedFieldNames;
- (void)revertUnsavedChanges;
- (void)revertUnsavedChangeToFieldName:(NSString *)fieldName;
- (FCModelSaveResult)delete;
- (FCModelSaveResult)save;
+ (void)saveAll; // Resolved by class: call on FCModel to save all, on a subclass to save just those and their subclasses, etc.

// SELECTs
// - "keyed" variants return dictionaries keyed by each instance's primary-key value.
// - "FromResultSet" variants will iterate through the supplied result set, but the caller is still responsible for closing it.
// - Optional query placeholders:
//      $T  - This model's table name
//      $PK - This model's primary-key field name
//
+ (NSArray *)allInstances;
+ (NSDictionary *)keyedAllInstances;

+ (NSArray *)instancesFromResultSet:(FMResultSet *)rs;
+ (NSDictionary *)keyedInstancesFromResultSet:(FMResultSet *)rs;
+ (instancetype)firstInstanceFromResultSet:(FMResultSet *)rs;

+ (instancetype)firstInstanceWhere:(NSString *)queryAfterWHERE, ...;
+ (NSArray *)instancesWhere:(NSString *)queryAfterWHERE, ...;
+ (NSArray *)instancesWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)array;
+ (NSDictionary *)keyedInstancesWhere:(NSString *)queryAfterWHERE, ...;

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

// These methods use a global query cache (in FCModelCachedObject). Results are cached indefinitely until their
//  table has any writes or there's a system low-memory warning, at which point they automatically invalidate.
// The next subsequent request will repopulate the cached data, either by querying the DB (cachedInstancesWhere)
//  or calling the generator block (cachedObjectWithIdentifier).
//
+ (NSArray *)cachedInstancesWhere:(NSString *)queryAfterWHERE arguments:(NSArray *)arguments;
+ (id)cachedObjectWithIdentifier:(id)identifier generator:(id (^)(void))generatorBlock;


// For subclasses to override, all optional:

- (void)didInit;
- (BOOL)shouldInsert;
- (BOOL)shouldUpdate;
- (BOOL)shouldDelete;
- (void)didInsert;
- (void)didUpdate;
- (void)didDelete;
- (void)saveWasRefused;
- (void)saveDidFail;

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

// Field info: You probably won't need this most of the time, but it's nice to have sometimes. FCModel's generating this privately
//  anyway, so you might as well have read-only access to it if it can help you avoid some code. (I've already needed it.)
//
+ (FCModelFieldInfo *)infoForFieldName:(NSString *)fieldName;

// Closing the database is not necessary in most cases. Only close it if you need to, such as if you need to delete and recreate
//  the database file. Caveats:
//     - Any FCModel call after closing will bizarrely fail until you call openDatabaseAtPath: again.
//     - Any FCModel instances retained by any other parts of your code at the time of closing will become abandoned and untracked.
//        The uniqueness guarantee will be broken, and operations on those instances will have undefined behavior. You really don't
//        want this, and it may raise an exception in the future.
//
//        Until then, having any resident FCModel instances at the time of closing the database will result in scary console warnings
//        and a return value of NO, which you should take as a condescending judgment and should fix immediately.
//
// Returns YES if there were no resident FCModel instances.
//
+ (BOOL)closeDatabase;

// If you try to use FCModel while the database is closed, an error will be logged to the console on any relevant calls.
// Read/info/SELECT methods will return nil when possible, but these will throw exceptions:
//  -save
//  +saveAll
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
@end

