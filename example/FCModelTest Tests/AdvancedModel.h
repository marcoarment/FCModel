//
//  AdvancedModel.h
//  FCModelTest
//
//  Created by Adam Lickel on 2/2/15.
//  Copyright (c) 2015 Marco Arment. All rights reserved.
//

#import "FCModel.h"

@interface AdvancedModel : FCModel

@property (nonatomic, copy) NSString *uniqueID;
@property (nonatomic, strong) NSURL *url;

@end
