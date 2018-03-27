//
//  FCModel+ExecuteRawQuery.h
//  Fastly
//
//  Created by Valentino Urbano on 27/03/2018.
//  Copyright © 2018 Valentino Urbano. 
//

#import "FCModel.h"

@interface FCModel (executeRawQuery)
///Only use for selects!!
+ (NSDictionary*) executeRawQuery:(NSString*) query;
@end
