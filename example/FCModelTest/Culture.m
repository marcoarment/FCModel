//
//  Culture.m
//
//  Created by Luke Durrant on 28/2/14.
//  Copyright (c) 2014 Luke Durrant. All rights reserved.
//

#import "Culture.h"

@implementation Culture

+(void)createTable:(FMDatabase*) db failBlock:(failedAtBlock)block version:(int*)version
{
    //Lets keep the model structure in the Culture Class
    if(*version < 1)
    {
        if (! [db executeUpdate:
           @"CREATE TABLE Culture ("
           @"cultureCode TEXT NOT NULL PRIMARY KEY,"
           @"name TEXT"
           @");"
           ]) block(19);
    }
}

- (BOOL)shouldInsert
{
    return YES;
}

- (BOOL)shouldUpdate
{
    return YES;
}
@end
