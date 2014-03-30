//
//  Person.h
//  FCModelTest
//
//  Created by Marco Arment on 9/14/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "FCModel.h"
#import "Color.h"
#import "Culture.h"

@interface Person : FCModel

// database columns:
@property (nonatomic, assign) int64_t id;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *colorName;
@property (nonatomic, copy) NSString *cultureCode;
@property (nonatomic, assign) int taps;
@property (nonatomic) NSDate *createdTime;
@property (nonatomic) NSDate *modifiedTime;



// non-columns:
@property (nonatomic) Color *color;
@property (nonatomic) Culture *culture;

@end
