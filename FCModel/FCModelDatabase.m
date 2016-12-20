//
//  FCModelDatabase.m
//
//  Created by Marco Arment on 3/12/14.
//  Copyright (c) 2014 Marco Arment. See included LICENSE file.
//

#import "FCModelDatabase.h"
#import "FCModel.h"
#import <sqlite3.h>

@interface FCModel ()
+ (void)postChangeNotificationWithChangedFields:(NSSet *)changedFields;
+ (void)dataChangedExternally;
@end

@interface FCModelDatabase () {
    uint32_t changeCounterBeforeBlock; // ivar instead of local so nested inDatabase calls work without mistakenly invoking dataChangedExternally
}

- (uint32_t)sqliteChangeCount;
- (BOOL)sqliteChangeTrackingIsActive;
@property (nonatomic) int32_t expectedChangeCount;
@end

#define kSQLiteFileChangeCounterOffset 24

static void _sqlite3_update_hook(void *context, int sqlite_operation, char const *db_name, char const *table_name, sqlite3_int64 rowid)
{
    Class class = NSClassFromString([NSString stringWithCString:table_name encoding:NSUTF8StringEncoding]);
    if (! class || ! [class isSubclassOfClass:FCModel.class]) return;

    FCModelDatabase *queue = (__bridge FCModelDatabase *) context;
    if (! queue.sqliteChangeTrackingIsActive) return;
    queue.expectedChangeCount = [queue sqliteChangeCount] + 1;
    if (queue.isInInternalWrite) return;

    // Can't run synchronously since SQLite requires that no other database queries are executed before this function returns,
    //  and queries are likely to be executed by any notification listeners.
    if (queue.isQueuingNotifications) [class postChangeNotificationWithChangedFields:nil];
    else dispatch_async(dispatch_get_main_queue(), ^{ [class postChangeNotificationWithChangedFields:nil]; });
}

@interface FCModelDatabase () {
    int changeCounterReadFileDescriptor;
    int dispatchEventFileDescriptor;
    dispatch_source_t dispatchFileWriteSource;
}
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

        sqlite3_update_hook(_openDatabase.sqliteHandle, &_sqlite3_update_hook, (__bridge void *) self);
    });
    return _openDatabase;
}

- (BOOL)sqliteChangeTrackingIsActive { return changeCounterReadFileDescriptor > 0; }

- (uint32_t)sqliteChangeCount
{
    if (! changeCounterReadFileDescriptor) return 0;
    
    uint32_t changeCounter = 0;
    lseek(changeCounterReadFileDescriptor, kSQLiteFileChangeCounterOffset, SEEK_SET);
    read(changeCounterReadFileDescriptor, &changeCounter, sizeof(uint32_t));
    return CFSwapInt32BigToHost(changeCounter);
}

- (void)startMonitoringForExternalChanges
{
    if (! self.openDatabase) [[NSException exceptionWithName:NSGenericException reason:@"Database must be open" userInfo:nil] raise];
    
    const char *fsp = _path.fileSystemRepresentation;
    changeCounterReadFileDescriptor = open(fsp, O_RDONLY);
    dispatchEventFileDescriptor = open(fsp, O_EVTONLY);
    dispatchFileWriteSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, dispatchEventFileDescriptor, DISPATCH_VNODE_WRITE, dispatch_get_main_queue());
    
    int rfdCopy = changeCounterReadFileDescriptor;
    int efdCopy = dispatchEventFileDescriptor;
    dispatch_source_set_cancel_handler(dispatchFileWriteSource, ^{
        close(rfdCopy);
        close(efdCopy);
    });

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(dispatchFileWriteSource, ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.expectedChangeCount != strongSelf.sqliteChangeCount) [FCModel dataChangedExternally];
    });

    dispatch_resume(dispatchFileWriteSource);
}

- (void)close
{
    dispatchEventFileDescriptor = 0;
    changeCounterReadFileDescriptor = 0;
    dispatch_source_cancel(dispatchFileWriteSource);
    dispatchFileWriteSource = NULL;

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
    
    FMDatabase *db = self.database;
    BOOL hadOpenResultSetsBefore = db.hasOpenResultSets;
    changeCounterBeforeBlock = [self sqliteChangeCount];

    block(db);

    if (changeCounterReadFileDescriptor) {
        // if more than 1 change during this expected write, either there's 2 queries in it (unexpected) or another process changed it
        uint32_t changeCounterAfterBlock = [self sqliteChangeCount];
        if (changeCounterAfterBlock - changeCounterBeforeBlock > 1) [FCModel dataChangedExternally];
    }

    if (db.hasOpenResultSets != hadOpenResultSetsBefore) {
        [[NSException exceptionWithName:NSGenericException reason:@"FCModelDatabase has an open FMResultSet after inDatabase:" userInfo:nil] raise];
    }
}

@end
