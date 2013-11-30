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
// The specific instance acted upon is passed as userInfo[FCModelInstanceKey].
//
extern NSString * const FCModelInsertNotification;
extern NSString * const FCModelUpdateNotification;
extern NSString * const FCModelDeleteNotification;
extern NSString * const FCModelInstanceKey;

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
+ (NSDictionary *)keyedInstancesWhere:(NSString *)queryAfterWHERE, ...;

+ (instancetype)firstInstanceOrderedBy:(NSString *)queryAfterORDERBY, ...;
+ (NSArray *)instancesOrderedBy:(NSString *)queryAfterORDERBY, ...;

// Fetch a set of primary keys, i.e. "WHERE key IN (...)"
+ (NSArray *)instancesWithPrimaryKeyValues:(NSArray *)primaryKeyValues;
+ (NSDictionary *)keyedInstancesWithPrimaryKeyValues:(NSArray *)primaryKeyValues;

// Return data instead of completed objects (convenient accessors to FCModel's database queue with $T/$PK parsing)
+ (NSArray *)resultDictionariesFromQuery:(NSString *)query, ...;
+ (NSArray *)firstColumnArrayFromQuery:(NSString *)query, ...;
+ (id)firstValueFromQuery:(NSString *)query, ...;


// For subclasses to override, all optional:

- (BOOL)shouldInsert;
- (BOOL)shouldUpdate;
- (BOOL)shouldDelete;
- (void)didInsert;
- (void)didUpdate;
- (void)didDelete;
- (void)saveWasRefused;
- (void)saveDidFail;

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


@end
