//
//  FCModelConcurrentMutableDictionary.m
//
//  Created by Marco Arment on 1/22/15.
//  Copyright (c) 2015 Marco Arment. See included LICENSE file.
//

#import "FCModelConcurrentMutableDictionary.h"

@interface FCModelConcurrentMutableDictionary ()
@property (nonatomic) NSMutableDictionary *backingStore;
@property (nonatomic) dispatch_queue_t queue;
@end

@implementation FCModelConcurrentMutableDictionary

+ (instancetype)dictionary { return [[self alloc] init]; }

- (instancetype)init
{
    if ( (self = [super init]) ) {
        self.backingStore = [NSMutableDictionary dictionary];
        self.queue = dispatch_queue_create(NULL, DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (NSDictionary *)dictionarySnapshot
{
    __block NSDictionary *dict;
    dispatch_sync(_queue, ^{ dict = [self.backingStore copy]; });
    return dict;
}

- (NSUInteger)count
{
    __block NSUInteger count;
    dispatch_sync(_queue, ^{ count = _backingStore.count; });
    return count;
}

- (id)objectForKey:(id)key
{
    __block id value;
    dispatch_sync(_queue, ^{ value = [_backingStore objectForKey:key]; });
    return value;
}

- (id)objectForKeyedSubscript:(id)key
{
    __block id value;
    dispatch_sync(_queue, ^{ value = [_backingStore objectForKeyedSubscript:key]; });
    return value;
}

- (void)setObject:(id)object forKey:(id<NSCopying>)key
{
    dispatch_barrier_async(_queue, ^{ [_backingStore setObject:object forKey:key]; });
}

- (void)setObject:(id)object forKeyedSubscript:(id<NSCopying>)key
{
    dispatch_barrier_async(_queue, ^{ [_backingStore setObject:object forKeyedSubscript:key]; });
}

- (void)removeObjectForKey:(id)key
{
    dispatch_barrier_async(_queue, ^{ [_backingStore removeObjectForKey:key]; });
}

- (void)removeAllObjects
{
    dispatch_barrier_async(_queue, ^{ [_backingStore removeAllObjects]; });
}


@end
