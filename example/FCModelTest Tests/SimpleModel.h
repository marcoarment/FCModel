//
//  SimpleModel.h
//  FCModelTest
//
//  Created by Denis Hennessy on 25/09/2013.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "FCModel.h"

@interface SimpleModel : FCModel

@property (nonatomic, copy) NSString *uniqueID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSDate *date;
@property (nonatomic) id typelessTest;
@property (nonatomic) NSString *lowercase;
@property (nonatomic) NSInteger mixedcase;

@end
