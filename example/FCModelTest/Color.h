//
//  Color.h
//  FCModelTest
//
//  Created by Marco Arment on 9/15/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "FCModel.h"

@interface Color : FCModel

@property (readonly) UIColor *colorValue; // not a database column
@property (nonatomic) NSString *name; // database primary key (doesn't have to be an integer)
@property (nonatomic) NSString *hex;  // database column

@end
