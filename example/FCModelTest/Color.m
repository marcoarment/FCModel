//
//  Color.m
//  FCModelTest
//
//  Created by Marco Arment on 9/15/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "Color.h"
#define UIColorFromHex(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]


@implementation Color

- (UIColor *)colorValue
{
    unsigned int hexColor = 0;
    [[NSScanner scannerWithString:self.hex] scanHexInt:&hexColor];
    return UIColorFromHex(hexColor);
}

@end
