//
//  FCModelCache.h
//
//  Created by Marco Arment on 8/17/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FCModel.h"

extern NSString * const FCModelRecacheNotification;

// This class is an implementation detail of FCModel. Do not instantiate or use it from elsewhere.
@interface FCModelCache : NSObject

+ (instancetype)sharedInstance;

- (void)saveInstance:(FCModel *)instance;
- (NSArray *)allInstancesOfClassAndSubclasses:(Class)class;
- (FCModel *)instanceOfClass:(Class)class withPrimaryKey:(id<NSCopying>)primaryKey;

- (void)removeDeallocatedInstanceOfClass:(Class)class withPrimaryKey:(id<NSCopying>)primaryKey;
- (void)removeAllInstances;
- (void)removeAllInstancesOfClass:(Class)class;

@end
