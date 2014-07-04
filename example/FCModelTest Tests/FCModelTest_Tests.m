//
//  FCModelTest_Tests.m
//  FCModelTest Tests
//
//  Created by Denis Hennessy on 25/09/2013.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "FCModel.h"
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
    XCTAssertEqual([entity1 save], FCModelSaveSucceeded);
    XCTAssertTrue(entity1.existsInDatabase);

    SimpleModel *entity2 = [SimpleModel instanceWithPrimaryKey:@"a"];
    XCTAssertTrue(entity2.existsInDatabase);
    XCTAssertEqual(entity2.name, entity1.name);
}

- (void)testEntityUniquing
{
    SimpleModel *entity1 = [SimpleModel instanceWithPrimaryKey:@"a"];
    [entity1 save];
    
    SimpleModel *entity2 = [SimpleModel instanceWithPrimaryKey:@"a"];
    XCTAssertTrue(entity2 == entity1);
}

- (void)testUniqueMapIssue65
{
    SimpleModel *newlyCreated = [SimpleModel new];
    newlyCreated.name = @"123";
    [newlyCreated save];

    NSArray *array = [SimpleModel instancesWhere:@"name == ?", @"123"];
    XCTAssertTrue(array.count == 1, @"More than 1 element");

    SimpleModel *first = array.count ? array[0] : nil;
    XCTAssertTrue(newlyCreated == first, @"%@ and %@ are different objects!", newlyCreated, first);
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
    
    XCTAssertTrue([FCModel closeDatabase]);
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
    FCModelSaveResult saveResult1 = [entity1 save];
    XCTAssertEqual(saveResult1, FCModelSaveSucceeded);
    FCModelSaveResult saveResult2 = [entity1 save];
    XCTAssertEqual(saveResult2, FCModelSaveNoChanges, @"Repeated saves should yield no changes");
    
    // actually changing the date should cause changes during save
    entity1.date = [NSDate dateWithTimeIntervalSinceNow:1];
    FCModelSaveResult saveResult3 = [entity1 save];
    XCTAssertEqual(saveResult3, FCModelSaveSucceeded);
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

- (void)testKeyedInstancesType
{
    SimpleModel *entity1 = [SimpleModel instanceWithPrimaryKey:@"w"];
    entity1.name = @"Waudru";
    [entity1 save];
    
    id result = nil;
    
    result = [SimpleModel keyedAllInstances];
    XCTAssertTrue(result && [result isKindOfClass:[NSDictionary class]]);
    
    [SimpleModel inDatabaseSync:^(FMDatabase *db) {
        FMResultSet *r = [db executeQuery:@"SELECT * FROM SimpleModel"];
        id result = [SimpleModel keyedInstancesFromResultSet:r];
        XCTAssertTrue(result && [result isKindOfClass:[NSDictionary class]]);
        [r close];
    }];
    
    result = [SimpleModel keyedInstancesWhere:@"name = 'Waudru'"];
    XCTAssertTrue(result && [result isKindOfClass:[NSDictionary class]]);
    
    result = [SimpleModel keyedInstancesWithPrimaryKeyValues:@[@"w"]];
    XCTAssertTrue(result && [result isKindOfClass:[NSDictionary class]]);
}

- (void)testNotifications
{
    __block int insertNotificationsClass1 = 0, insertNotificationsClass2 = 0, insertNotificationsNoClass = 0,
                updateNotificationsClass1 = 0, updateNotificationsClass2 = 0, updateNotificationsNoClass = 0,
                deleteNotificationsClass1 = 0, deleteNotificationsClass2 = 0, deleteNotificationsNoClass = 0,
                anyChgNotificationsClass1 = 0, anyChgNotificationsClass2 = 0, anyChgNotificationsNoClass = 0;

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    NSArray *observers = @[
        [nc addObserverForName:FCModelInsertNotification    object:nil                queue:nil usingBlock:^(NSNotification *n) { insertNotificationsNoClass++; }],
        [nc addObserverForName:FCModelInsertNotification    object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) { insertNotificationsClass1++;  }],
        [nc addObserverForName:FCModelInsertNotification    object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) { insertNotificationsClass2++;  }],
        [nc addObserverForName:FCModelUpdateNotification    object:nil                queue:nil usingBlock:^(NSNotification *n) { updateNotificationsNoClass++; }],
        [nc addObserverForName:FCModelUpdateNotification    object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) { updateNotificationsClass1++;  }],
        [nc addObserverForName:FCModelUpdateNotification    object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) { updateNotificationsClass2++;  }],
        [nc addObserverForName:FCModelDeleteNotification    object:nil                queue:nil usingBlock:^(NSNotification *n) { deleteNotificationsNoClass++; }],
        [nc addObserverForName:FCModelDeleteNotification    object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) { deleteNotificationsClass1++;  }],
        [nc addObserverForName:FCModelDeleteNotification    object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) { deleteNotificationsClass2++;  }],
        [nc addObserverForName:FCModelAnyChangeNotification object:nil                queue:nil usingBlock:^(NSNotification *n) { anyChgNotificationsNoClass++; }],
        [nc addObserverForName:FCModelAnyChangeNotification object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) { anyChgNotificationsClass1++;  }],
        [nc addObserverForName:FCModelAnyChangeNotification object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) { anyChgNotificationsClass2++;  }],
    ];

    SimpleModel *insertModel = [SimpleModel new];
    insertModel.name = @"insert";
    [insertModel save];
    
    XCTAssert(insertNotificationsNoClass == 1, @"[1] Received %d insert classless notifications",    insertNotificationsNoClass);
    XCTAssert(insertNotificationsClass1  == 1, @"[1] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
    XCTAssert(insertNotificationsClass2  == 0, @"[1] Received %d insert SimplerModel notifications", insertNotificationsClass2);
    XCTAssert(updateNotificationsNoClass == 0, @"[1] Received %d update classless notifications",    updateNotificationsNoClass);
    XCTAssert(updateNotificationsClass1  == 0, @"[1] Received %d update SimpleModel notifications",  updateNotificationsClass1);
    XCTAssert(updateNotificationsClass2  == 0, @"[1] Received %d update SimplerModel notifications", updateNotificationsClass2);
    XCTAssert(deleteNotificationsNoClass == 0, @"[1] Received %d delete classless notifications",    deleteNotificationsNoClass);
    XCTAssert(deleteNotificationsClass1  == 0, @"[1] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
    XCTAssert(deleteNotificationsClass2  == 0, @"[1] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
    XCTAssert(anyChgNotificationsNoClass == 1, @"[1] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 1, @"[1] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 0, @"[1] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

    SimplerModel *insertModel2 = [SimplerModel new];
    insertModel2.title = @"insert2";
    [insertModel2 save];

    XCTAssert(insertNotificationsNoClass == 2, @"[2] Received %d insert classless notifications",    insertNotificationsNoClass);
    XCTAssert(insertNotificationsClass1  == 1, @"[2] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
    XCTAssert(insertNotificationsClass2  == 1, @"[2] Received %d insert SimplerModel notifications", insertNotificationsClass2);
    XCTAssert(updateNotificationsNoClass == 0, @"[2] Received %d update classless notifications",    updateNotificationsNoClass);
    XCTAssert(updateNotificationsClass1  == 0, @"[2] Received %d update SimpleModel notifications",  updateNotificationsClass1);
    XCTAssert(updateNotificationsClass2  == 0, @"[2] Received %d update SimplerModel notifications", updateNotificationsClass2);
    XCTAssert(deleteNotificationsNoClass == 0, @"[2] Received %d delete classless notifications",    deleteNotificationsNoClass);
    XCTAssert(deleteNotificationsClass1  == 0, @"[2] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
    XCTAssert(deleteNotificationsClass2  == 0, @"[2] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
    XCTAssert(anyChgNotificationsNoClass == 2, @"[2] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 1, @"[2] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 1, @"[2] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

    insertModel2.title = @"update2";
    [insertModel2 save];

    XCTAssert(insertNotificationsNoClass == 2, @"[3] Received %d insert classless notifications",    insertNotificationsNoClass);
    XCTAssert(insertNotificationsClass1  == 1, @"[3] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
    XCTAssert(insertNotificationsClass2  == 1, @"[3] Received %d insert SimplerModel notifications", insertNotificationsClass2);
    XCTAssert(updateNotificationsNoClass == 1, @"[3] Received %d update classless notifications",    updateNotificationsNoClass);
    XCTAssert(updateNotificationsClass1  == 0, @"[3] Received %d update SimpleModel notifications",  updateNotificationsClass1);
    XCTAssert(updateNotificationsClass2  == 1, @"[3] Received %d update SimplerModel notifications", updateNotificationsClass2);
    XCTAssert(deleteNotificationsNoClass == 0, @"[3] Received %d delete classless notifications",    deleteNotificationsNoClass);
    XCTAssert(deleteNotificationsClass1  == 0, @"[3] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
    XCTAssert(deleteNotificationsClass2  == 0, @"[3] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
    XCTAssert(anyChgNotificationsNoClass == 3, @"[3] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 1, @"[3] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 2, @"[3] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

    [insertModel delete];

    XCTAssert(insertNotificationsNoClass == 2, @"[4] Received %d insert classless notifications",    insertNotificationsNoClass);
    XCTAssert(insertNotificationsClass1  == 1, @"[4] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
    XCTAssert(insertNotificationsClass2  == 1, @"[4] Received %d insert SimplerModel notifications", insertNotificationsClass2);
    XCTAssert(updateNotificationsNoClass == 1, @"[4] Received %d update classless notifications",    updateNotificationsNoClass);
    XCTAssert(updateNotificationsClass1  == 0, @"[4] Received %d update SimpleModel notifications",  updateNotificationsClass1);
    XCTAssert(updateNotificationsClass2  == 1, @"[4] Received %d update SimplerModel notifications", updateNotificationsClass2);
    XCTAssert(deleteNotificationsNoClass == 1, @"[4] Received %d delete classless notifications",    deleteNotificationsNoClass);
    XCTAssert(deleteNotificationsClass1  == 1, @"[4] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
    XCTAssert(deleteNotificationsClass2  == 0, @"[4] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
    XCTAssert(anyChgNotificationsNoClass == 4, @"[4] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 2, @"[4] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 2, @"[4] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

    [SimplerModel executeUpdateQuery:@"UPDATE $T SET title = 'executeUpdate2'"];

    XCTAssert(insertNotificationsNoClass == 2, @"[5] Received %d insert classless notifications",    insertNotificationsNoClass);
    XCTAssert(insertNotificationsClass1  == 1, @"[5] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
    XCTAssert(insertNotificationsClass2  == 1, @"[5] Received %d insert SimplerModel notifications", insertNotificationsClass2);
    XCTAssert(updateNotificationsNoClass == 2, @"[5] Received %d update classless notifications",    updateNotificationsNoClass);
    XCTAssert(updateNotificationsClass1  == 0, @"[5] Received %d update SimpleModel notifications",  updateNotificationsClass1);
    XCTAssert(updateNotificationsClass2  == 2, @"[5] Received %d update SimplerModel notifications", updateNotificationsClass2);
    XCTAssert(deleteNotificationsNoClass == 1, @"[5] Received %d delete classless notifications",    deleteNotificationsNoClass);
    XCTAssert(deleteNotificationsClass1  == 1, @"[5] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
    XCTAssert(deleteNotificationsClass2  == 0, @"[5] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
    XCTAssert(anyChgNotificationsNoClass == 5, @"[5] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
    XCTAssert(anyChgNotificationsClass1  == 2, @"[5] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
    XCTAssert(anyChgNotificationsClass2  == 3, @"[5] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);
    
    for (id observer in observers) [nc removeObserver:observer];
}

- (void)testBatchNotifications
{
    __block int insertNotificationsClass1 = 0, insertNotificationsClass2 = 0, insertNotificationsNoClass = 0,
                updateNotificationsClass1 = 0, updateNotificationsClass2 = 0, updateNotificationsNoClass = 0,
                deleteNotificationsClass1 = 0, deleteNotificationsClass2 = 0, deleteNotificationsNoClass = 0,
                anyChgNotificationsClass1 = 0, anyChgNotificationsClass2 = 0, anyChgNotificationsNoClass = 0;

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    NSArray *observers = @[
        [nc addObserverForName:FCModelInsertNotification    object:nil                queue:nil usingBlock:^(NSNotification *n) { insertNotificationsNoClass++; }],
        [nc addObserverForName:FCModelInsertNotification    object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) { insertNotificationsClass1++;  }],
        [nc addObserverForName:FCModelInsertNotification    object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) { insertNotificationsClass2++;  }],
        [nc addObserverForName:FCModelUpdateNotification    object:nil                queue:nil usingBlock:^(NSNotification *n) { updateNotificationsNoClass++; }],
        [nc addObserverForName:FCModelUpdateNotification    object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) { updateNotificationsClass1++;  }],
        [nc addObserverForName:FCModelUpdateNotification    object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) { updateNotificationsClass2++;  }],
        [nc addObserverForName:FCModelDeleteNotification    object:nil                queue:nil usingBlock:^(NSNotification *n) { deleteNotificationsNoClass++; }],
        [nc addObserverForName:FCModelDeleteNotification    object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) { deleteNotificationsClass1++;  }],
        [nc addObserverForName:FCModelDeleteNotification    object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) { deleteNotificationsClass2++;  }],
        [nc addObserverForName:FCModelAnyChangeNotification object:nil                queue:nil usingBlock:^(NSNotification *n) { anyChgNotificationsNoClass++; }],
        [nc addObserverForName:FCModelAnyChangeNotification object:SimpleModel.class  queue:nil usingBlock:^(NSNotification *n) { anyChgNotificationsClass1++;  }],
        [nc addObserverForName:FCModelAnyChangeNotification object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) { anyChgNotificationsClass2++;  }],
    ];

    [FCModel performWithBatchedNotifications:^{
        SimpleModel *insertModel = [SimpleModel new];
        insertModel.name = @"insert";
        [insertModel save];
        
        XCTAssert(insertNotificationsNoClass == 0, @"[1] Received %d insert classless notifications",    insertNotificationsNoClass);
        XCTAssert(insertNotificationsClass1  == 0, @"[1] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
        XCTAssert(insertNotificationsClass2  == 0, @"[1] Received %d insert SimplerModel notifications", insertNotificationsClass2);
        XCTAssert(updateNotificationsNoClass == 0, @"[1] Received %d update classless notifications",    updateNotificationsNoClass);
        XCTAssert(updateNotificationsClass1  == 0, @"[1] Received %d update SimpleModel notifications",  updateNotificationsClass1);
        XCTAssert(updateNotificationsClass2  == 0, @"[1] Received %d update SimplerModel notifications", updateNotificationsClass2);
        XCTAssert(deleteNotificationsNoClass == 0, @"[1] Received %d delete classless notifications",    deleteNotificationsNoClass);
        XCTAssert(deleteNotificationsClass1  == 0, @"[1] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
        XCTAssert(deleteNotificationsClass2  == 0, @"[1] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
        XCTAssert(anyChgNotificationsNoClass == 0, @"[1] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[1] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[1] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

        SimplerModel *insertModel2 = [SimplerModel new];
        insertModel2.title = @"insert2";
        [insertModel2 save];

        XCTAssert(insertNotificationsNoClass == 0, @"[2] Received %d insert classless notifications",    insertNotificationsNoClass);
        XCTAssert(insertNotificationsClass1  == 0, @"[2] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
        XCTAssert(insertNotificationsClass2  == 0, @"[2] Received %d insert SimplerModel notifications", insertNotificationsClass2);
        XCTAssert(updateNotificationsNoClass == 0, @"[2] Received %d update classless notifications",    updateNotificationsNoClass);
        XCTAssert(updateNotificationsClass1  == 0, @"[2] Received %d update SimpleModel notifications",  updateNotificationsClass1);
        XCTAssert(updateNotificationsClass2  == 0, @"[2] Received %d update SimplerModel notifications", updateNotificationsClass2);
        XCTAssert(deleteNotificationsNoClass == 0, @"[2] Received %d delete classless notifications",    deleteNotificationsNoClass);
        XCTAssert(deleteNotificationsClass1  == 0, @"[2] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
        XCTAssert(deleteNotificationsClass2  == 0, @"[2] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
        XCTAssert(anyChgNotificationsNoClass == 0, @"[2] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[2] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[2] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

        insertModel2.title = @"update2";
        [insertModel2 save];

        XCTAssert(insertNotificationsNoClass == 0, @"[3] Received %d insert classless notifications",    insertNotificationsNoClass);
        XCTAssert(insertNotificationsClass1  == 0, @"[3] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
        XCTAssert(insertNotificationsClass2  == 0, @"[3] Received %d insert SimplerModel notifications", insertNotificationsClass2);
        XCTAssert(updateNotificationsNoClass == 0, @"[3] Received %d update classless notifications",    updateNotificationsNoClass);
        XCTAssert(updateNotificationsClass1  == 0, @"[3] Received %d update SimpleModel notifications",  updateNotificationsClass1);
        XCTAssert(updateNotificationsClass2  == 0, @"[3] Received %d update SimplerModel notifications", updateNotificationsClass2);
        XCTAssert(deleteNotificationsNoClass == 0, @"[3] Received %d delete classless notifications",    deleteNotificationsNoClass);
        XCTAssert(deleteNotificationsClass1  == 0, @"[3] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
        XCTAssert(deleteNotificationsClass2  == 0, @"[3] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
        XCTAssert(anyChgNotificationsNoClass == 0, @"[3] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[3] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[3] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

        [insertModel delete];

        XCTAssert(insertNotificationsNoClass == 0, @"[4] Received %d insert classless notifications",    insertNotificationsNoClass);
        XCTAssert(insertNotificationsClass1  == 0, @"[4] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
        XCTAssert(insertNotificationsClass2  == 0, @"[4] Received %d insert SimplerModel notifications", insertNotificationsClass2);
        XCTAssert(updateNotificationsNoClass == 0, @"[4] Received %d update classless notifications",    updateNotificationsNoClass);
        XCTAssert(updateNotificationsClass1  == 0, @"[4] Received %d update SimpleModel notifications",  updateNotificationsClass1);
        XCTAssert(updateNotificationsClass2  == 0, @"[4] Received %d update SimplerModel notifications", updateNotificationsClass2);
        XCTAssert(deleteNotificationsNoClass == 0, @"[4] Received %d delete classless notifications",    deleteNotificationsNoClass);
        XCTAssert(deleteNotificationsClass1  == 0, @"[4] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
        XCTAssert(deleteNotificationsClass2  == 0, @"[4] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
        XCTAssert(anyChgNotificationsNoClass == 0, @"[4] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[4] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[4] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);

        [SimplerModel executeUpdateQuery:@"UPDATE $T SET title = 'executeUpdate2'"];

        XCTAssert(insertNotificationsNoClass == 0, @"[5] Received %d insert classless notifications",    insertNotificationsNoClass);
        XCTAssert(insertNotificationsClass1  == 0, @"[5] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
        XCTAssert(insertNotificationsClass2  == 0, @"[5] Received %d insert SimplerModel notifications", insertNotificationsClass2);
        XCTAssert(updateNotificationsNoClass == 0, @"[5] Received %d update classless notifications",    updateNotificationsNoClass);
        XCTAssert(updateNotificationsClass1  == 0, @"[5] Received %d update SimpleModel notifications",  updateNotificationsClass1);
        XCTAssert(updateNotificationsClass2  == 0, @"[5] Received %d update SimplerModel notifications", updateNotificationsClass2);
        XCTAssert(deleteNotificationsNoClass == 0, @"[5] Received %d delete classless notifications",    deleteNotificationsNoClass);
        XCTAssert(deleteNotificationsClass1  == 0, @"[5] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
        XCTAssert(deleteNotificationsClass2  == 0, @"[5] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
        XCTAssert(anyChgNotificationsNoClass == 0, @"[5] Received %d anyChg classless notifications",    anyChgNotificationsNoClass);
        XCTAssert(anyChgNotificationsClass1  == 0, @"[5] Received %d anyChg SimpleModel notifications",  anyChgNotificationsClass1);
        XCTAssert(anyChgNotificationsClass2  == 0, @"[5] Received %d anyChg SimplerModel notifications", anyChgNotificationsClass2);
    } deliverOnCompletion:YES];
    
    XCTAssert(insertNotificationsNoClass == 2, @"[6] Received %d insert classless notifications",    insertNotificationsNoClass);
    XCTAssert(insertNotificationsClass1  == 1, @"[6] Received %d insert SimpleModel notifications",  insertNotificationsClass1);
    XCTAssert(insertNotificationsClass2  == 1, @"[6] Received %d insert SimplerModel notifications", insertNotificationsClass2);
    XCTAssert(updateNotificationsNoClass == 1, @"[6] Received %d update classless notifications",    updateNotificationsNoClass);
    XCTAssert(updateNotificationsClass1  == 0, @"[6] Received %d update SimpleModel notifications",  updateNotificationsClass1);
    XCTAssert(updateNotificationsClass2  == 1, @"[6] Received %d update SimplerModel notifications", updateNotificationsClass2);
    XCTAssert(deleteNotificationsNoClass == 1, @"[6] Received %d delete classless notifications",    deleteNotificationsNoClass);
    XCTAssert(deleteNotificationsClass1  == 1, @"[6] Received %d delete SimpleModel notifications",  deleteNotificationsClass1);
    XCTAssert(deleteNotificationsClass2  == 0, @"[6] Received %d delete SimplerModel notifications", deleteNotificationsClass2);
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
        [nc addObserverForName:FCModelAnyChangeNotification object:SimpleModel.class queue:nil usingBlock:^(NSNotification *n) {
            changedFieldsClass1 = n.userInfo[FCModelChangedFieldsKey];
        }],
        [nc addObserverForName:FCModelAnyChangeNotification object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) {
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
    [FCModel performWithBatchedNotifications:^{
        insertModel.name = @"batchedUpdate";
        insertModel.lowercase = @"whatever";
        [insertModel save];
        XCTAssert(changedFieldsClass1 == nil, @"Batched update reported wrong field names: %@", changedFieldsClass1);

        insertModel.mixedcase = 2;
        [insertModel save];
        XCTAssert(changedFieldsClass1 == nil, @"Batched update2 reported wrong field names: %@", changedFieldsClass1);        
    } deliverOnCompletion:YES];
    
    NSSet *changedFields = [NSSet setWithObjects:@"name", @"lowercase", @"mixedcase", nil];
    XCTAssert([changedFieldsClass1 isEqualToSet:changedFields], @"Batch reported wrong field names: %@", changedFieldsClass1);
    
    for (id observer in observers) [nc removeObserver:observer];
}

- (void)testUpdateWithoutLoadedInstances
{
    __block int notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:FCModelAnyChangeNotification object:SimplerModel.class queue:nil usingBlock:^(NSNotification *n) {
        notifications++;
    }];

    [SimplerModel dataWasUpdatedExternally];
    XCTAssert(notifications == 1, @"Update without loaded instances got %d notifications", notifications);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}


#pragma mark - Helper methods

- (void)openDatabase
{
    [FCModel openDatabaseAtPath:[self dbPath] withSchemaBuilder:^(FMDatabase *db, int *schemaVersion) {
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
        [db commit];
    }];
}

- (NSString *)dbPath
{
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"testDB.sqlite3"];
}

@end
