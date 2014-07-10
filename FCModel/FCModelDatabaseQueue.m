//
//  FCModelDatabaseQueue.m
//
//  Created by Marco Arment on 3/12/14.
//  Copyright (c) 2014 Marco Arment. See included LICENSE file.
//

#import "FCModelDatabaseQueue.h"

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
        NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:block];
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

- (void (^)())databaseBlockWithBlock:(void (^)(FMDatabase *db))block {
    FMDatabase *db = self.database;
    return ^{
        BOOL hadOpenResultSetsBefore = db.hasOpenResultSets;
        block(db);
        if (db.hasOpenResultSets != hadOpenResultSetsBefore) [[NSException exceptionWithName:NSGenericException reason:@"FCModelDatabaseQueue has an open FMResultSet after inDatabase:" userInfo:nil] raise];
    };
}

- (void)inDatabase:(void (^)(FMDatabase *db))block
{
    [self execOnSelfSync:[self databaseBlockWithBlock:block]];
}

- (void)inDatabaseAsync:(void (^)(FMDatabase *db))block {
    [self addOperation:[NSBlockOperation blockOperationWithBlock:[self databaseBlockWithBlock:block]]];
}

@end
