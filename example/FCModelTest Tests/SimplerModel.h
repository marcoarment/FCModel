//
//  SimplerModel.h
//  FCModelTest
//
//  Created by Marco Arment on 5/5/14.
//  Copyright (c) 2014 Marco Arment. All rights reserved.
//

#import "FCModel.h"

@interface SimplerModel : FCModel

@property (nonatomic) int64_t id;
@property (nonatomic, copy) NSString *title;

@end
