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
