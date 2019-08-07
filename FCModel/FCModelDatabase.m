//
//  FCModelDatabase.m
//
//  Created by Marco Arment on 3/12/14.
//  Copyright (c) 2014 Marco Arment. See included LICENSE file.
//

#import "FCModelDatabase.h"
#import "FCModel.h"
#import <sqlite3.h>

@interface FCModelDatabase ()
@property (nonatomic) FMDatabase *openDatabase;
@property (nonatomic) NSString *path;
@property (nonatomic) NSMutableDictionary *enqueuedChangedFieldsByClass;
@property (nonatomic) BOOL inExpectedWrite;
@end

@implementation FCModelDatabase

- (instancetype)initWithDatabasePath:(NSString *)path
{
    if ( (self = [super init]) ) {
        self.path = path;
        self.enqueuedChangedFieldsByClass = [NSMutableDictionary dictionary];
    }
    return self;
}

- (FMDatabase *)database
{
    if (! _openDatabase) fcm_onMainThread(^{
        self.openDatabase = [[FMDatabase alloc] initWithPath:_path];
        if (! [_openDatabase open]) {
            [[NSException exceptionWithName:NSGenericException reason:[NSString stringWithFormat:@"Cannot open or create database at path: %@", self.path] userInfo:nil] raise];
        }
    });
    return _openDatabase;
}

- (void)close
{
    [self.openDatabase close];
    self.openDatabase = nil;
}

- (void)dealloc
{
    [_openDatabase close];
    self.openDatabase = nil;
}

- (void)inDatabase:(void (^)(FMDatabase *db))block
{
    NSParameterAssert(NSThread.isMainThread);
    block(self.database);
}

@end
