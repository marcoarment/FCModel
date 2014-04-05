//
//  CustomModel.h
//  FCModelTest
//
//  Created by Ramon on 4/4/14.
//  Copyright (c) 2014 Marco Arment. All rights reserved.
//

#import "FCModel.h"

@interface CustomModel : FCModel

@property(nonatomic) NSInteger id;
@property(nonatomic, copy) NSString *name;
@property(nonatomic) BOOL available;

@end
