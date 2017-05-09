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

// This ridiculously convoluted approach to dynamically call UIApplication.beginBackgroundTask...
//  is to enable compiling this with iOS apps AND extensions without requiring apps to custom-#define
//  "is extension"/"is main app" preprocessor macros in their build configs.
//
// Performing DB queries within background tasks is now required under iOS 10.x to prevent the app from
//  being suspended mid-query, which will cause Springboard to kill the app with crashlog code 0xdeadl0cc.
//
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
static void wrapInBackgroundTask(void (^block)())
{
    static dispatch_once_t onceToken;
    static Class UIApplicationClass;
    static id application;
    static NSMethodSignature *beginTaskSignature, *endTaskSignature;
    static SEL beginTaskSEL;
    static SEL endTaskSEL;
    dispatch_once(&onceToken, ^{
        beginTaskSEL = @selector(beginBackgroundTaskWithExpirationHandler:);
        endTaskSEL = @selector(endBackgroundTask:);
        UIApplicationClass = NSClassFromString(@"UIApplication");
        application = UIApplicationClass ? [UIApplicationClass performSelector:@selector(sharedApplication)]: nil;
        beginTaskSignature = application ? [application methodSignatureForSelector:beginTaskSEL] : nil;
        endTaskSignature = application ? [application methodSignatureForSelector:endTaskSEL] : nil;
    });
    
    if (application) {
        __block NSUInteger backgroundTaskID = 0;
        void (^endTaskBlock)() = ^{
            backgroundTaskID = 0;
            NSInvocation *endInvocation = [NSInvocation invocationWithMethodSignature:endTaskSignature];
            endInvocation.selector = endTaskSEL;
            [endInvocation setArgument:&backgroundTaskID atIndex:2];
            [endInvocation invokeWithTarget:application];
        };

        NSInvocation *beginInvocation = [NSInvocation invocationWithMethodSignature:beginTaskSignature];
        beginInvocation.selector = beginTaskSEL;
        [beginInvocation setArgument:&endTaskBlock atIndex:2];
        [beginInvocation invokeWithTarget:application];
        [beginInvocation getReturnValue:&backgroundTaskID];
        block();
        if (backgroundTaskID) endTaskBlock();
    } else {
        block();
    }
}
#pragma clang diagnostic pop

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
        wrapInBackgroundTask(^{
            self.openDatabase = [[FMDatabase alloc] initWithPath:_path];
            if (! [_openDatabase open]) {
                [[NSException exceptionWithName:NSGenericException reason:[NSString stringWithFormat:@"Cannot open or create database at path: %@", self.path] userInfo:nil] raise];
            }

            sqlite3_update_hook(_openDatabase.sqliteHandle, &_sqlite3_update_hook, (__bridge void *) self);
        });
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
    wrapInBackgroundTask(^{ [self.openDatabase close]; });
    self.openDatabase = nil;
}

- (void)dealloc
{
    wrapInBackgroundTask(^{ [_openDatabase close]; });
    self.openDatabase = nil;
}

- (void)inDatabase:(void (^)(FMDatabase *db))block
{
    NSParameterAssert(NSThread.isMainThread);
    
    wrapInBackgroundTask(^{
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
    });
}

@end
