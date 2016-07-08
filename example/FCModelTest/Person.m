//
//  Person.m
//  FCModelTest
//
//  Created by Marco Arment on 9/14/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "Person.h"

@implementation Person


- (BOOL)save:(void (^)())modificiationsBlock
{
    return [super save:^{
        if (self.hasUnsavedChanges) self.modifiedTime = [NSDate date];
        if (! self.existsInDatabase) self.createdTime = [NSDate date];
        modificiationsBlock();
    }];
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
