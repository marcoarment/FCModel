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
+ (void)postChangeNotificationWithChangedFields:(NSSet *)changedFields changedObject:(FCModel *)changedObject changeType:(FCModelChangeType)changeType priorFieldValues:(NSDictionary *)priorFieldValues;
@end

static void _sqlite3_update_hook(void *context, int sqlite_operation, char const *db_name, char const *table_name, sqlite3_int64 rowid)
{
    Class class = NSClassFromString([NSString stringWithCString:table_name encoding:NSUTF8StringEncoding]);
    if (! class || ! [class isSubclassOfClass:FCModel.class]) return;

    FCModelDatabase *queue = (__bridge FCModelDatabase *) context;
    if (queue.isInInternalWrite) return;

    // Can't run synchronously since SQLite requires that no other database queries are executed before this function returns,
    //  and queries are likely to be executed by any notification listeners.
    if (queue.isQueuingNotifications) [class postChangeNotificationWithChangedFields:nil changedObject:nil changeType:FCModelChangeTypeUnspecified priorFieldValues:nil];
    else dispatch_async(dispatch_get_main_queue(), ^{ [class postChangeNotificationWithChangedFields:nil changedObject:nil changeType:FCModelChangeTypeUnspecified priorFieldValues:nil]; });
}

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

        sqlite3_update_hook(_openDatabase.sqliteHandle, &_sqlite3_update_hook, (__bridge void *) self);
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
