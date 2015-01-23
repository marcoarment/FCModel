//
//  FCModelNotificationCenter.m
//
//  Created by Marco Arment on 1/12/15.
//  Copyright (c) 2015 Marco Arment. See included LICENSE file.
//

#import "FCModelNotificationCenter.h"
#import "FCModel.h"

@interface FCModelNotificationCenter ()
@property (nonatomic) NSMapTable *observersByTarget;
@property (nonatomic) dispatch_queue_t targetWriteQueue;
@end

@implementation FCModelNotificationCenter

+ (instancetype)defaultCenter
{
    static FCModelNotificationCenter *c;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ c = [self new]; });
    return c;
}

- (instancetype)init
{
    if ( (self = [super init]) ) {
        self.observersByTarget = [NSMapTable weakToStrongObjectsMapTable];
        self.targetWriteQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)addObserver:(id)target selector:(SEL)action class:(Class)class changedFields:(NSSet *)requestedFields
{
    dispatch_sync(_targetWriteQueue, ^{
        NSMutableArray *targetObservers = [_observersByTarget objectForKey:target];
        if (! targetObservers) [_observersByTarget setObject:(targetObservers = [NSMutableArray array]) forKey:target];
        
        __weak id weakTarget = target;
        [targetObservers addObject:[NSNotificationCenter.defaultCenter addObserverForName:FCModelChangeNotification object:class queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            __strong id strongTarget = weakTarget;
            if (! strongTarget) return;
            NSSet *changedFields = n.userInfo[FCModelChangedFieldsKey];
            if (! changedFields || ! requestedFields || [changedFields intersectsSet:requestedFields]) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [strongTarget performSelector:action withObject:n];
#pragma clang diagnostic pop

            }
        }]];
    });
}

- (void)removeFieldChangeObservers:(id)target
{
    dispatch_sync(_targetWriteQueue, ^{
        NSMutableArray *targetObservers = [_observersByTarget objectForKey:target];
        if (! targetObservers) return;
        for (id observer in targetObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
        [_observersByTarget removeObjectForKey:target];
    });
}

@end
