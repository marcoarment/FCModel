//
//  PersonCell.h
//  FCModelTest
//
//  Created by Marco Arment on 9/14/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Person.h"

@interface PersonCell : UICollectionViewCell

- (void)configureWithPerson:(Person *)person;

@property (nonatomic) IBOutlet UILabel *idLabel;
@property (nonatomic) IBOutlet UILabel *nameLabel;
@property (nonatomic) IBOutlet UILabel *tapsLabel;
@property (nonatomic) IBOutlet UILabel *colorLabel;

@end
