//
//  FCModelDatabaseQueue.m
//
//  Created by Marco Arment on 3/12/14.
//  Copyright (c) 2014 Marco Arment. See included LICENSE file.
//

#import "FCModelDatabaseQueue.h"

// this NSOperation only exists, rather than using addOperationWithBlock:, so we can use addOperations:waitUntilFinished:
//  rather than having to wait for ALL operations to finish in execOnSelfSync:
//
@interface FCModelDatabaseQueueOperation : NSOperation
@property (nonatomic, copy) void (^block)();
@end
@implementation FCModelDatabaseQueueOperation
- (void)main { self.block(); }
@end


@interface FCModelDatabaseQueue ()
@property (nonatomic) FMDatabase *openDatabase;
@property (nonatomic) NSString *path;
@end

@implementation FCModelDatabaseQueue

- (instancetype)initWithDatabasePath:(NSString *)path
{
    if ( (self = [super init]) ) {
        self.name = NSStringFromClass(self.class);
        self.maxConcurrentOperationCount = 1;
        self.path = path;
    }
    return self;
}

- (FMDatabase *)database
{
    if (! self.openDatabase) [self execOnSelfSync:^{
        self.openDatabase = [[FMDatabase alloc] initWithPath:self.path];
        if (! [self.openDatabase open]) {
            [[NSException exceptionWithName:NSGenericException reason:[NSString stringWithFormat:@"Cannot open or create database at path: %@", self.path] userInfo:nil] raise];
        }
    }];
    return self.openDatabase;
}

- (void)execOnSelfSync:(void (^)())block
{
    if (NSOperationQueue.currentQueue == self) {
        block();
    } else {
        FCModelDatabaseQueueOperation *operation = [[FCModelDatabaseQueueOperation alloc] init];
        operation.block = block;
        [self addOperations:@[ operation ] waitUntilFinished:YES];
    }
}

- (void)close
{
    [self execOnSelfSync:^{
        [self.openDatabase close];
        self.openDatabase = nil;
    }];
}

- (void)dealloc
{
    [_openDatabase close];
    self.openDatabase = nil;
}

- (void)inDatabase:(void (^)(FMDatabase *db))block
{
    [self execOnSelfSync:^{
        FMDatabase *db = self.database;
        BOOL hadOpenResultSetsBefore = db.hasOpenResultSets;
        block(self.database);
        if (db.hasOpenResultSets != hadOpenResultSetsBefore) [[NSException exceptionWithName:NSGenericException reason:@"FCModelDatabaseQueue has an open FMResultSet after inDatabase:" userInfo:nil] raise];
    }];
}

@end
