//
//  FCModelDatabaseQueue.m
//
//  Created by Marco Arment on 3/12/14.
//  Copyright (c) 2014 Marco Arment. See included LICENSE file.
//

#import "FCModelDatabaseQueue.h"
#import "FCModel.h"

#define kSQLiteFileChangeCounterOffset 24

@interface FCModelDatabaseQueue () {
    int changeCounterReadFileDescriptor;
    int dispatchEventFileDescriptor;
    dispatch_source_t dispatchFileWriteSource;
    dispatch_queue_t dispatchFileWriteQueue;
}
@property (nonatomic) FMDatabase *openDatabase;
@property (nonatomic) NSString *path;
@property (nonatomic) BOOL inExpectedWrite;
@end

@implementation FCModelDatabaseQueue

- (instancetype)initWithDatabasePath:(NSString *)path
{
    if ( (self = [super init]) ) {
        self.name = NSStringFromClass(self.class);
        self.maxConcurrentOperationCount = 1;
        self.path = path;
        dispatchFileWriteQueue = dispatch_queue_create(NULL, NULL);
    }
    return self;
}

- (FMDatabase *)database
{
    if (! self.openDatabase) [self execOnSelfSync:^{
        self.openDatabase = [[FMDatabase alloc] initWithPath:_path];
        if (! [_openDatabase open]) {
            [[NSException exceptionWithName:NSGenericException reason:[NSString stringWithFormat:@"Cannot open or create database at path: %@", _path] userInfo:nil] raise];
        }
    }];
    return self.openDatabase;
}

- (void)startMonitoringForExternalChanges
{
    if (! self.openDatabase) [[NSException exceptionWithName:NSGenericException reason:@"Database must be open" userInfo:nil] raise];
    
    const char *fsp = _path.fileSystemRepresentation;
    changeCounterReadFileDescriptor = open(fsp, O_RDONLY);
    dispatchEventFileDescriptor = open(fsp, O_EVTONLY);
    dispatchFileWriteSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, dispatchEventFileDescriptor, DISPATCH_VNODE_WRITE, dispatchFileWriteQueue);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(dispatchFileWriteSource, ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf && ! strongSelf.inExpectedWrite) [FCModel dataWasUpdatedExternally];
    });

    dispatch_resume(dispatchFileWriteSource);
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
        dispatch_source_cancel(dispatchFileWriteSource);
        dispatchFileWriteSource = NULL;

        close(dispatchEventFileDescriptor);
        dispatchEventFileDescriptor = 0;

        close(changeCounterReadFileDescriptor);
        changeCounterReadFileDescriptor = 0;

        [self.openDatabase close];
        self.openDatabase = nil;
    }];
}

- (void)dealloc
{
    [_openDatabase close];
    self.openDatabase = nil;
}

- (void (^)())databaseBlockWithBlock:(void (^)(FMDatabase *db))block readOnly:(BOOL)readOnly {
    FMDatabase *db = self.database;
    return ^{
        BOOL hadOpenResultSetsBefore = db.hasOpenResultSets;
        if (! readOnly) _inExpectedWrite = YES;

        // Read change counter from SQLite file header to detect changes made by other processes during this write
        uint32_t changeCounterBeforeBlock = 0;
        if (changeCounterReadFileDescriptor > 0) {
            lseek(changeCounterReadFileDescriptor, kSQLiteFileChangeCounterOffset, SEEK_SET);
            read(changeCounterReadFileDescriptor, &changeCounterBeforeBlock, sizeof(uint32_t));
            changeCounterBeforeBlock = CFSwapInt32BigToHost(changeCounterBeforeBlock);
        }
        
        block(db);

        dispatch_sync(dispatchFileWriteQueue, ^{
            _inExpectedWrite = NO;
            
            // if more than 1 change during this expected write, either there's 2 queries in it (unexpected) or another process changed it
            uint32_t changeCounterAfterBlock = 0;
            if (changeCounterReadFileDescriptor > 0) {
                lseek(changeCounterReadFileDescriptor, kSQLiteFileChangeCounterOffset, SEEK_SET);
                read(changeCounterReadFileDescriptor, &changeCounterAfterBlock, sizeof(uint32_t));
                changeCounterAfterBlock = CFSwapInt32BigToHost(changeCounterAfterBlock);
            }

            if (changeCounterAfterBlock - changeCounterBeforeBlock > 1) [FCModel dataWasUpdatedExternally];
        });

        if (db.hasOpenResultSets != hadOpenResultSetsBefore) [[NSException exceptionWithName:NSGenericException reason:@"FCModelDatabaseQueue has an open FMResultSet after inDatabase:" userInfo:nil] raise];
    };
}

- (void)readDatabase:(void (^)(FMDatabase *db))block
{
    [self execOnSelfSync:[self databaseBlockWithBlock:block readOnly:YES]];
}

- (void)writeDatabase:(void (^)(FMDatabase *db))block
{
    [self execOnSelfSync:[self databaseBlockWithBlock:block readOnly:NO]];
}


@end
