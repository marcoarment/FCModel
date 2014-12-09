//
//  FCModelInstanceCache.h
//  FCModelTest
//
//  Created by Marco Arment on 12/8/14.
//  Copyright (c) 2014 Marco Arment. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FCModel.h"

@interface FCModelInstanceCache : NSObject

- (FCModel *)instanceOfClass:(Class)class withPrimaryKeyValue:(id)primaryKeyValue;
- (void)saveInstance:(FCModel *)instance;
- (void)removeInstanceOfClass:(Class)class withPrimaryKeyValue:(id)primaryKeyValue;
- (void)removeAllInstances;

@end
