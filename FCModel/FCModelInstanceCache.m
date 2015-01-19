//
//  FCModelInstanceCache.m
//  FCModelTest
//
//  Created by Marco Arment on 12/8/14.
//  Copyright (c) 2014 Marco Arment. All rights reserved.
//

#import "FCModelInstanceCache.h"
extern NSString * const FCModelWillSendChangeNotification;

@interface FCModelInstanceCache ()
@property (nonatomic) NSMutableDictionary *cachesByClass;
@end


@implementation FCModelInstanceCache

- (instancetype)init
{
    if ( (self = [super init]) ) {
        self.cachesByClass = [NSMutableDictionary dictionary];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(invalidate:) name:FCModelWillSendChangeNotification object:nil];
#if TARGET_OS_IPHONE
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(removeAllInstances) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (FCModel *)instanceOfClass:(Class)class withPrimaryKeyValue:(id)primaryKeyValue
{
    if (! primaryKeyValue) return nil;
    NSMutableDictionary *classCache = self.cachesByClass[class];
    return classCache ? [classCache objectForKey:primaryKeyValue] : nil;
}

- (void)removeInstanceOfClass:(Class)class withPrimaryKeyValue:(id)primaryKeyValue
{
    if (! primaryKeyValue) return;
    NSMutableDictionary *classCache = self.cachesByClass[class];
    if (classCache) [classCache removeObjectForKey:primaryKeyValue];
}

- (void)saveInstance:(FCModel *)instance
{
    id pkValue = instance.primaryKey;
    if (! pkValue) return;
    
    NSMutableDictionary *classCache = self.cachesByClass[instance.class];
    if (! classCache) {
        classCache = [NSMutableDictionary dictionary];
        self.cachesByClass[(id)instance.class] = classCache;
    }
    [classCache setObject:[instance copy] forKey:pkValue];
}

- (void)invalidate:(NSNotification *)n
{
    [self.cachesByClass removeObjectForKey:n.object];
}

- (void)removeAllInstances
{
    [self.cachesByClass removeAllObjects];
}

@end
