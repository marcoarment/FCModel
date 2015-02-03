//
//  FCModelTest_Tests.m
//  FCModelTest Tests
//
//  Created by Denis Hennessy on 25/09/2013.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "FCModel.h"
#import "AdvancedModel.h"
#import "SimpleModel.h"
#import "SimplerModel.h"

@interface FCModelTest_Tests : XCTestCase

@end

@implementation FCModelTest_Tests

- (void)setUp
{
    [super setUp];
    [NSFileManager.defaultManager removeItemAtPath:[self dbPath] error:NULL];
    [self openDatabase];
}

- (void)tearDown
{
    [FCModel closeDatabase];
    [super tearDown];
}

- (void)testBasicStoreRetrieve
{
    SimpleModel *entity1 = [SimpleModel instanceWithPrimaryKey:@"a"];
    entity1.name = @"Alice";
    XCTAssertFalse(entity1.existsInDatabase);
    XCTAssertEqual([entity1 save], YES);
    XCTAssertTrue(entity1.existsInDatabase);

    SimpleModel *entity2 = [SimpleModel instanceWithPrimaryKey:@"a"];
    XCTAssertTrue(entity2.existsInDatabase);
    XCTAssertTrue([entity2.name isEqualToString:entity1.name]);
}

- (void)testValueTransformStoreRetrieve
{
    AdvancedModel *entity1 = [AdvancedModel instanceWithPrimaryKey:@"a"];
    entity1.url = [NSURL URLWithString:@"http://example.com"];
    XCTAssertFalse(entity1.existsInDatabase);
    XCTAssertEqual([entity1 save], YES);
    XCTAssertTrue(entity1.existsInDatabase);

    AdvancedModel *entity2 = [AdvancedModel instanceWithPrimaryKey:@"a"];
    XCTAssertTrue(entity2.existsInDatabase);
    XCTAssertTrue([entity2.url isEqual:entity1.url]);
}

- (void)testBasicReloadAndSave
{
    SimpleModel *entity1 = [SimpleModel instanceWithPrimaryKey:@"a"];
    entity1.name = @"Alice";
    XCTAssertEqual([entity1 save], YES);

    XCTAssertEqual([entity1 reloadAndSave:^{
        entity1.name = @"Bob";
    }], YES);

    SimpleModel *entity2 = [SimpleModel instanceWithPrimaryKey:@"a"];
    XCTAssertTrue(entity2.existsInDatabase);
    XCTAssertTrue([entity2.name isEqualToString:entity1.name]);
}

- (void)testValueTransformReloadAndSave
{
    AdvancedModel *entity1 = [AdvancedModel instanceWithPrimaryKey:@"a"];
    entity1.url = [NSURL URLWithString:@"http://example.com"];
    XCTAssertEqual([entity1 save], YES);

    XCTAssertEqual([entity1 reloadAndSave:^{
        entity1.url = [NSURL URLWithString:@"https://github.com/marcoarment/FCModel"];
    }], YES);

    AdvancedModel *entity2 = [AdvancedModel instanceWithPrimaryKey:@"a"];
    XCTAssertTrue(entity2.existsInDatabase);
    XCTAssertTrue([entity2.url isEqual:entity1.url]);
}

- (void)testEntityNonUniquing
{
    SimpleModel *entity1 = [SimpleModel instanceWithPrimaryKey:@"a"];
    [entity1 save];
    
    SimpleModel *entity2 = [SimpleModel instanceWithPrimaryKey:@"a"];
    XCTAssertTrue(entity2 != entity1);
}

- (void)testDatabaseCloseFlushesCache
{
    void *e1ptr;
    @autoreleasepool {
        SimpleModel *entity1 = [SimpleModel instanceWithPrimaryKey:@"a"];
        entity1.name = @"Alice";
        [entity1 save];
        e1ptr = (__bridge void *)(entity1);
        entity1 = nil;
    }

    // the @autoreleasepool does not get cleared immediately
    [NSThread sleepForTimeInterval:1.0f];
    
    [FCModel closeDatabase];
    XCTAssertTrue(! [FCModel databaseIsOpen]);
    XCTAssertTrue([SimpleModel instanceWithPrimaryKey:@"a"] == nil);
    XCTAssertThrows([SimpleModel executeUpdateQuery:@"UPDATE $T SET name = 'bogus'"]);

    [self openDatabase];
    XCTAssertTrue([FCModel databaseIsOpen]);
    
    SimpleModel *entity2 = [SimpleModel instanceWithPrimaryKey:@"a"];
    XCTAssertTrue(entity2.existsInDatabase);
    XCTAssertTrue(entity2 != (__bridge SimpleModel *)(e1ptr));
}

- (void)testDateEncodingChangeMonitoring
{
    NSDate *date = [NSDate date];
    SimpleModel *entity1 = [SimpleModel new];
    entity1.date = date;
    BOOL saveResult1 = [entity1 save];
    XCTAssertEqual(saveResult1, YES);
    BOOL saveResult2 = [entity1 save];
    XCTAssertEqual(saveResult2, NO, @"Repeated saves should yield no changes");
    
    // actually changing the date should cause changes during save
    entity1.date = [NSDate dateWithTimeIntervalSinceNow:1];
    BOOL saveResult3 = [entity1 save];
    XCTAssertEqual(saveResult3, YES);
}

- (void)testMappingFieldInfo
{
    SimpleModel *entity = [SimpleModel new];
    FCModelFieldInfo *info1 = [[entity class] infoForFieldName:@"uniqueID"];
    FCModelFieldInfo *info2 = [[entity class] infoForFieldName:@"name"];
    FCModelFieldInfo *info3 = [[entity class] infoForFieldName:@"lowercase"];
    FCModelFieldInfo *info4 = [[entity class] infoForFieldName:@"mixedcase"];
    FCModelFieldInfo *info5 = [[entity class] infoForFieldName:@"typelessTest"];
    
    XCTAssertEqual(info1.type, FCModelFieldTypeText);
    XCTAssertEqual(info2.type, FCModelFieldTypeText);
    XCTAssertEqual(info3.type, FCModelFieldTypeText);
    XCTAssertEqual(info4.type, FCModelFieldTypeInteger);
    XCTAssertEqual(info5.type, FCModelFieldTypeOther);
}

- (void)testFieldDefaultNull
{
    FCModelFieldInfo *fieldInfoUnspecified = [SimpleModel infoForFieldName:@"textDefaultUnspecified"];
    FCModelFieldInfo *fieldInfoNullLiteral = [SimpleModel infoForFieldName:@"textDefaultNullLiteral"];
    FCModelFieldInfo *fieldInfoNullString = [SimpleModel infoForFieldName:@"textDefaultNullString"];
    
    XCTAssertTrue(fieldInfoUnspecified.nullAllowed);
    XCTAssertTrue(fieldInfoNullLiteral.nullAllowed);
    XCTAssertTrue(fieldInfoNullString.nullAllowed);
    XCTAssertTrue(fieldInfoUnspecified.defaultValue == nil);
    XCTAssertTrue(fieldInfoNullLiteral.defaultValue == nil);
    XCTAssertTrue([fieldInfoNullString.defaultValue isEqualToString:@"NULL"]);
    
    SimpleModel *entity = [SimpleModel new];
    XCTAssertTrue(entity.textDefaultUnspecified == nil);
    XCTAssertTrue(entity.textDefaultNullLiteral == nil);
    XCTAssertTrue(entity.textDefaultNullString && [entity.textDefaultNullString isEqualToString:@"NULL"]);
}

- (void)testNullableNumberField
{
    FCModelFieldInfo *infoDefaultUnspecified = [SimpleModel infoForFieldName:@"nullableNumberDefaultUnspecified"];
    FCModelFieldInfo *infoDefaultNull = [SimpleModel infoForFieldName:@"nullableNumberDefaultNull"];
    FCModelFieldInfo *infoDefault1 = [SimpleModel infoForFieldName:@"nullableNumberDefault1"];
    
    XCTAssertTrue(infoDefaultUnspecified.nullAllowed);
    XCTAssertTrue(infoDefaultNull.nullAllowed);
    XCTAssertTrue(infoDefault1.nullAllowed);

    XCTAssertTrue(infoDefaultUnspecified.defaultValue == nil);
    XCTAssertTrue(infoDefaultNull.defaultValue == nil);
    XCTAssertTrue([infoDefault1.defaultValue isEqual:@1]);
    
    SimpleModel *entity = [SimpleModel new];
    XCTAssertTrue(entity.nullableNumberDefaultUnspecified == nil);
    XCTAssertTrue(entity.nullableNumberDefaultNull == nil);
    XCTAssertTrue([entity.nullableNumberDefault1 isEqual:@1]);
}

- (void)testVariableLimit {
    __block int maxParameterCount = 0;
    [FCModel inDatabaseSync:^(FMDatabase *db) {
        maxParameterCount = sqlite3_limit(db.sqliteHandle, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
    }];
    
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:maxParameterCount+1];
    for (int i = 0; i <= maxParameterCount; i++) {
        [values addObject:@(i)];
    }
    XCTAssertNoThrow([SimpleModel instancesWithPrimaryKeyValues:values]);
    
}

- (void)testNotifications
{
    __block int anyChgNotificationsClass1 = 0, anyChgNotificationsClass2 = 0, anyChgNotificationsNoClass = 0;

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    NSArray *observers = @[
        [nc addObserverForName:FCModelChangeNotification object:nil                queue:nil usingBlock:^(NSNotification *n) {
            anyChgNotificationsNoClass++;
        }],
        [nc addObserverForName:FCModelChangeNotification object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) {
            anyChgNotificationsClass1++;
        }],
        [nc addObserverForName:FCModelChangeNotification object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) {
            anyChgNotificationsClass2++;
        }],
    ];

    SimpleModel *insertModel = [SimpleModel new];
    insertModel.name = @"insert";
    [insertModel save];
    
    XCTAssert(anyChgNotificationsNoClass == 1, @"[1] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 1, @"[1] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 0, @"[1] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

    SimplerModel *insertModel2 = [SimplerModel new];
    insertModel2.title = @"insert2";
    [insertModel2 save];

    XCTAssert(anyChgNotificationsNoClass == 2, @"[2] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 1, @"[2] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 1, @"[2] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

    insertModel2.title = @"update2";
    [insertModel2 save];

    XCTAssert(anyChgNotificationsNoClass == 3, @"[3] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 1, @"[3] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 2, @"[3] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

    [insertModel delete];

    XCTAssert(anyChgNotificationsNoClass == 4, @"[4] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 2, @"[4] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 2, @"[4] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

    [SimplerModel executeUpdateQuery:@"UPDATE $T SET title = 'executeUpdate2'"];

    XCTAssert(anyChgNotificationsNoClass == 5, @"[5] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 2, @"[5] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 3, @"[5] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);
    
    for (id observer in observers) [nc removeObserver:observer];
}

- (void)testBatchNotifications
{
    __block int anyChgNotificationsClass1 = 0, anyChgNotificationsClass2 = 0, anyChgNotificationsNoClass = 0;

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    NSArray *observers = @[
        [nc addObserverForName:FCModelChangeNotification object:nil                queue:nil usingBlock:^(NSNotification *n) {
            anyChgNotificationsNoClass++;
        }],
        [nc addObserverForName:FCModelChangeNotification object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) {
            anyChgNotificationsClass1++;
        }],
        [nc addObserverForName:FCModelChangeNotification object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) {
            anyChgNotificationsClass2++;
        }],
    ];

    [FCModel performTransaction:^BOOL{
        SimpleModel *insertModel = [SimpleModel new];
        insertModel.name = @"insert";
        [insertModel save];
        
        XCTAssert(anyChgNotificationsNoClass == 0, @"[1] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[1] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[1] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

        SimplerModel *insertModel2 = [SimplerModel new];
        insertModel2.title = @"insert2";
        [insertModel2 save];

        XCTAssert(anyChgNotificationsNoClass == 0, @"[2] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[2] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[2] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

        insertModel2.title = @"update2";
        [insertModel2 save];

        XCTAssert(anyChgNotificationsNoClass == 0, @"[3] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[3] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[3] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

        [insertModel delete];

        XCTAssert(anyChgNotificationsNoClass == 0, @"[4] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[4] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[4] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

        [SimplerModel executeUpdateQuery:@"UPDATE $T SET title = 'executeUpdate2'"];

        XCTAssert(anyChgNotificationsNoClass == 0, @"[5] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[5] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[5] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);
        
        return YES;
    }];
    
    XCTAssert(anyChgNotificationsNoClass == 2, @"[6] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 1, @"[6] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 1, @"[6] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);
    
    for (id observer in observers) [nc removeObserver:observer];
}


- (void)testChangedFieldsNotifications
{
    __block NSSet *changedFieldsClass1 = nil, *changedFieldsClass2 = nil;

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    NSArray *observers = @[
        [nc addObserverForName:FCModelChangeNotification object:SimpleModel.class queue:nil usingBlock:^(NSNotification *n) {
            changedFieldsClass1 = n.userInfo[FCModelChangedFieldsKey];
        }],
        [nc addObserverForName:FCModelChangeNotification object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) {
            changedFieldsClass2 = n.userInfo[FCModelChangedFieldsKey];
        }],
    ];
    
    NSSet *allClass1Fields = [NSSet setWithArray:SimpleModel.databaseFieldNames];
    NSSet *allClass2Fields = [NSSet setWithArray:SimplerModel.databaseFieldNames];

    SimpleModel *insertModel = [SimpleModel new];
    insertModel.name = @"insert";
    [insertModel save];
    XCTAssert([changedFieldsClass1 isEqualToSet:allClass1Fields], @"Insert reported wrong field names: %@", changedFieldsClass1);

    changedFieldsClass1 = nil;
    insertModel.name = @"update";
    [insertModel save];
    XCTAssert([changedFieldsClass1 isEqualToSet:[NSSet setWithObject:@"name"]], @"Update reported wrong field names: %@", changedFieldsClass1);

    SimplerModel *insertModel2 = [SimplerModel new];
    insertModel2.title = @"insert2";
    [insertModel2 save];
    XCTAssert([changedFieldsClass2 isEqualToSet:allClass2Fields], @"Insert2 reported wrong field names: %@", changedFieldsClass2);
    
    // Batching
    
    changedFieldsClass1 = nil;
    [FCModel performTransaction:^BOOL{
        insertModel.name = @"batchedUpdate";
        insertModel.lowercase = @"whatever";
        [insertModel save];
        XCTAssert(changedFieldsClass1 == nil, @"Batched update reported wrong field names: %@", changedFieldsClass1);

        insertModel.mixedcase = 2;
        [insertModel save];
        XCTAssert(changedFieldsClass1 == nil, @"Batched update2 reported wrong field names: %@", changedFieldsClass1);
        
        return YES;
    }];
    
    NSSet *changedFields = [NSSet setWithObjects:@"name", @"lowercase", @"mixedcase", nil];
    XCTAssert([changedFieldsClass1 isEqualToSet:changedFields], @"Batch reported wrong field names: %@", changedFieldsClass1);
    
    for (id observer in observers) [nc removeObserver:observer];
}

- (void)testUpdateWithoutLoadedInstances
{
    __block int notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:FCModelChangeNotification object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) {
        notifications++;
    }];
    
    [SimplerModel executeUpdateQuery:@"INSERT INTO $T (id, title) VALUES (1, 'T')"];

    XCTAssert(notifications == 1, @"Update without loaded instances got %d notifications", notifications);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}


#pragma mark - Helper methods

- (void)openDatabase
{
    [FCModel openDatabaseAtPath:[self dbPath] withDatabaseInitializer:NULL schemaBuilder:^(FMDatabase *db, int *schemaVersion) {
        [db setCrashOnErrors:YES];
        [db beginTransaction];
        
        void (^failedAt)(int statement) = ^(int statement){
            int lastErrorCode = db.lastErrorCode;
            NSString *lastErrorMessage = db.lastErrorMessage;
            [db rollback];
            NSAssert3(0, @"Migration statement %d failed, code %d: %@", statement, lastErrorCode, lastErrorMessage);
        };
        
        if (*schemaVersion < 1) {
            if (! [db executeUpdate:
                @"CREATE TABLE SimpleModel ("
                @"    uniqueID     TEXT PRIMARY KEY,"
                @"    name         TEXT,"
                @"    date         DATETIME,"
                @"    textDefaultUnspecified TEXT,"
                @"    textDefaultNullLiteral TEXT DEFAULT NULL,"
                @"    textDefaultNullString  TEXT DEFAULT 'NULL',"
                @"    nullableNumberDefaultUnspecified INTEGER,"
                @"    nullableNumberDefaultNull INTEGER DEFAULT NULL,"
                @"    nullableNumberDefault1 INTEGER DEFAULT 1,"
                @"    lowercase         text,"
                @"    mixedcase         Integer NOT NULL,"
                @"    typelessTest"
                @");"
            ]) failedAt(1);

            if (! [db executeUpdate:
                @"CREATE TABLE SimplerModel ("
                @"    id    INTEGER PRIMARY KEY,"
                @"    title TEXT"
                @");"
            ]) failedAt(2);


            *schemaVersion = 1;
        }

        if (*schemaVersion < 2) {
            if (![db executeUpdate:
                  @"CREATE TABLE AdvancedModel ("
                  @"    uniqueID TEXT PRIMARY KEY,"
                  @"    url      TEXT"
                  @");"
            ]) failedAt(3);


            *schemaVersion = 2;
        }

        [db commit];
    }];
}

- (NSString *)dbPath
{
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"testDB.sqlite3"];
}

@end
