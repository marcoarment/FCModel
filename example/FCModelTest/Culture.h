//
//  Culture.h
//  
//
//  Created by Luke Durrant on 28/2/14.
//  Copyright (c) 2014 Luke Durrant. All rights reserved.
//

#import "FCModel.h"

typedef void (^failedAtBlock)(int statement);

@interface Culture : FCModel

// database columns:
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *cultureCode;

+(void)createTable:(FMDatabase*) db failBlock:(failedAtBlock)block version:(int*)version;

@end
