//
//  AdvancedModel.m
//  FCModelTest
//
//  Created by Adam Lickel on 2/2/15.
//  Copyright (c) 2015 Marco Arment. All rights reserved.
//

#import "AdvancedModel.h"

@interface URLTransformer: NSValueTransformer
@end

@implementation AdvancedModel

+ (void)load
{
    [NSValueTransformer setValueTransformer:[URLTransformer new] forName:NSStringFromClass(URLTransformer.class)];
}

+ (NSValueTransformer *)valueTransformerForFieldName:(NSString *)fieldName
{
    if ([fieldName isEqualToString:@"url"]) {
        return [NSValueTransformer valueTransformerForName:NSStringFromClass(URLTransformer.class)];
    }
    return nil;
}

@end

@implementation URLTransformer

+ (Class)transformedValueClass
{
    return NSURL.class;
}

+ (BOOL)allowsReverseTransformation
{
    return YES;
}

- (id)transformedValue:(NSString *)value
{
    return [NSURL URLWithString:value];
}

- (id)reverseTransformedValue:(NSURL *)value
{
    return value.absoluteString;
}

@end
