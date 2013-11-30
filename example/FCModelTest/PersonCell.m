//
//  PersonCell.m
//  FCModelTest
//
//  Created by Marco Arment on 9/14/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "PersonCell.h"


@interface PersonCell ()
@property (nonatomic) Person *person;
@end

@implementation PersonCell

- (void)configureWithPerson:(Person *)person
{
    if (self.person) {
        [self.person removeObserver:self forKeyPath:@"name"];
        [self.person removeObserver:self forKeyPath:@"colorName"];
        [self.person removeObserver:self forKeyPath:@"taps"];
    }
    
    self.person = person;

    if (person) {
        [self.person addObserver:self forKeyPath:@"name" options:NSKeyValueObservingOptionInitial context:NULL];
        [self.person addObserver:self forKeyPath:@"colorName" options:NSKeyValueObservingOptionInitial context:NULL];
        [self.person addObserver:self forKeyPath:@"taps" options:NSKeyValueObservingOptionInitial context:NULL];

        self.idLabel.text = [NSString stringWithFormat:@"%lld", person.id];
    }
}
-(void)dealloc {
    if(self.person) {
        [self.person removeObserver:self forKeyPath:@"name"];
        [self.person removeObserver:self forKeyPath:@"colorName"];
        [self.person removeObserver:self forKeyPath:@"taps"];
    }
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(Person *)person change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"name"]) {
        self.nameLabel.text = person.name;
    } else if ([keyPath isEqualToString:@"colorName"]) {
        Color *c = person.color;
        self.backgroundColor = c ? c.colorValue : [UIColor clearColor];
        self.colorLabel.text = c ? c.name : @"(invalid)";
    } else if ([keyPath isEqualToString:@"taps"]) {
        self.tapsLabel.text = [NSString stringWithFormat:@"%d tap%@", person.taps, person.taps == 1 ? @"" : @"s"];
    }
}

@end
