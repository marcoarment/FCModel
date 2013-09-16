//
//  Person.h
//  FCModelTest
//
//  Created by Marco Arment on 9/14/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "FCModel.h"
#import "Color.h"

@interface Person : FCModel

// database columns:
@property (nonatomic, assign) int64_t id;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *colorName;
@property (nonatomic, assign) int taps;
@property (nonatomic) NSDate *createdTime;
@property (nonatomic) NSDate *modifiedTime;

// non-columns:
@property (nonatomic) Color *color;

@end
