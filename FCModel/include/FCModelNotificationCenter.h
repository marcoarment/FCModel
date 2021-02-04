//
//  FCModelNotificationCenter.h
//
//  Created by Marco Arment on 1/12/15.
//  Copyright (c) 2015 Marco Arment. See included LICENSE file.
//

#import <Foundation/Foundation.h>

@interface FCModelNotificationCenter : NSObject

+ (instancetype)defaultCenter;
- (void)addObserver:(id)target selector:(SEL)action class:(Class)class changedFields:(NSSet *)changedFields;
- (void)removeFieldChangeObservers:(id)target;

@end
