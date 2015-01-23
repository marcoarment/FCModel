//
//  FCModelConcurrentMutableDictionary.h
//
//  Created by Marco Arment on 1/22/15.
//  Copyright (c) 2015 Marco Arment. See included LICENSE file.
//

#import <Foundation/Foundation.h>

@interface FCModelConcurrentMutableDictionary : NSObject

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSDictionary *dictionarySnapshot;

+ (instancetype)dictionary;

- (id)objectForKey:(id)key;
- (id)objectForKeyedSubscript:(id)key;
- (void)setObject:(id)object forKey:(id<NSCopying>)key;
- (void)setObject:(id)object forKeyedSubscript:(id<NSCopying>)key;
- (void)removeObjectForKey:(id)key;
- (void)removeAllObjects;

@end
