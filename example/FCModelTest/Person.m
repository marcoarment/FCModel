//
//  Person.m
//  FCModelTest
//
//  Created by Marco Arment on 9/14/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "Person.h"

@implementation Person

- (BOOL)shouldInsert
{
    self.createdTime = [NSDate date];
    self.modifiedTime = self.createdTime;
    return YES;
}

- (BOOL)shouldUpdate
{
    self.modifiedTime = [NSDate date];
    return YES;
}

- (Color *)color
{
    return [Color instanceWithPrimaryKey:self.colorName];
}

- (void)setColor:(Color *)color
{
    self.colorName = color.name;
}

@end
