//
//  FCModel+ExecuteRawQuery_m.h
//  Fastly
//
//  Created by Valentino Urbano on 27/03/2018.
//  Copyright © 2018 Valentino Urbano. 
//

#import "FCModel+ExecuteRawQuery.h"

@implementation FCModel(executeRawQuery)

+ (NSDictionary*) executeRawQuery:(NSString*) query
{

  __block NSDictionary *model = NULL;
  [g_databaseQueue inDatabase:^(FMDatabase *db) {
    FMResultSet *s = [db executeQuery: query];
    if (! s) [self queryFailedInDatabase:db];
    model = [s resultDictionary];
    [s close];
  }];
  
  return model;
}

@end
