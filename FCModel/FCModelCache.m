//
//  FCModelCache.m
//
//  Created by Marco Arment on 8/17/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "FCModelCache.h"

NSString * const FCModelRecacheNotification = @"FCModelRecacheNotification";


@interface FCModelCache ()
@property (nonatomic) NSMutableDictionary *classCaches;
@property (nonatomic) dispatch_semaphore_t readLock;
@end


@implementation FCModelCache

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    static FCModelCache *sharedInstance;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    if ( (self = [super init]) ) {
        self.classCaches = [NSMutableDictionary dictionary];
        self.readLock = dispatch_semaphore_create(1);
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

- (void)saveInstance:(FCModel *)instance
{
    id primaryKey = instance.primaryKey;
    if (! primaryKey) [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Cannot cache model instance with no primary key set" userInfo:nil] raise];
    
    NSMapTable *classCache = self.classCaches[instance.class];
    if (! classCache) {
        classCache = [NSMapTable strongToWeakObjectsMapTable];
        self.classCaches[(id) instance.class] = classCache;
    }

    [classCache setObject:instance forKey:primaryKey];
}

- (NSArray *)allInstancesOfClassAndSubclasses:(Class)class
{
    dispatch_semaphore_wait(_readLock, DISPATCH_TIME_FOREVER);
    NSMutableArray *instances = [NSMutableArray array];

    [self.classCaches enumerateKeysAndObjectsUsingBlock:^(Class c, NSMapTable *classCache, BOOL *stop) {
        if ([c isSubclassOfClass:class]) {
            NSEnumerator *enumerator = classCache.objectEnumerator;
            id obj;
            while ( (obj = [enumerator nextObject]) ) [instances addObject:obj];
        }
    }];

    dispatch_semaphore_signal(_readLock);
    return instances;
}

- (FCModel *)instanceOfClass:(Class)class withPrimaryKey:(id<NSCopying>)primaryKey
{
    dispatch_semaphore_wait(_readLock, DISPATCH_TIME_FOREVER);
    NSMapTable *classCache = self.classCaches[class];
    FCModel *cachedInstance = classCache ? [classCache objectForKey:primaryKey] : nil;
    dispatch_semaphore_signal(_readLock);
    return cachedInstance;
}

- (void)removeDeallocatedInstanceOfClass:(Class)class withPrimaryKey:(id<NSCopying>)primaryKey
{
    NSMapTable *classCache = self.classCaches[class];
    if (classCache) [classCache removeObjectForKey:primaryKey];
}

- (void)removeAllInstances
{
    dispatch_semaphore_wait(_readLock, DISPATCH_TIME_FOREVER);
    [self.classCaches removeAllObjects];
    [NSNotificationCenter.defaultCenter postNotificationName:FCModelRecacheNotification object:nil];
    dispatch_semaphore_signal(_readLock);
}

- (void)removeAllInstancesOfClass:(Class)class
{
    dispatch_semaphore_wait(_readLock, DISPATCH_TIME_FOREVER);
    NSMutableDictionary *classCache = self.classCaches[class];
    if (classCache) [classCache removeAllObjects];
    [NSNotificationCenter.defaultCenter postNotificationName:FCModelRecacheNotification object:nil];
    dispatch_semaphore_signal(_readLock);
}

- (void)didReceiveMemoryWarning:(NSNotification *)n
{
    [self removeAllInstances];
}

@end
