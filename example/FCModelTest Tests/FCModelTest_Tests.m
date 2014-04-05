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
    
    XCTAssertTrue([FCModel closeDatabase]);
    [self openDatabase];
    
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
                   @"    lowercase         text,"
                   @"    mixedcase         Integer,"
                   @"    typelessTest"
                   @");"
                   ]) failedAt(1);
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
