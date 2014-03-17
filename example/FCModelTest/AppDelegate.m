//
//  AppDelegate.m
//  FCModelTest
//
//  Created by Marco Arment on 9/14/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"
#import "FCModel.h"
#import "Person.h"
#import "Culture.h"
#import "RandomThings.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSString *dbPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"testDB.sqlite3"];
    NSLog(@"DB path: %@", dbPath);

    // New DB on every launch for testing (comment out for persistence testing)
    [NSFileManager.defaultManager removeItemAtPath:dbPath error:NULL];
    
    [FCModel openDatabaseAtPath:dbPath withSchemaBuilder:^(FMDatabase *db, int *schemaVersion) {
        [db setCrashOnErrors:YES];
        db.traceExecution = YES; // Log every query (useful to learn what FCModel is doing or analyze performance)
        [db beginTransaction];
        
        void (^failedAt)(int statement) = ^(int statement){
            int lastErrorCode = db.lastErrorCode;
            NSString *lastErrorMessage = db.lastErrorMessage;
            [db rollback];
            NSAssert3(0, @"Migration statement %d failed, code %d: %@", statement, lastErrorCode, lastErrorMessage);
        };
        
        //Example of table creation in a class
        [Culture createTable:db failBlock:failedAt version:schemaVersion];
        
        if (*schemaVersion < 1) {
            if (! [db executeUpdate:
                @"CREATE TABLE Person ("
                @"    id           INTEGER PRIMARY KEY AUTOINCREMENT," // Autoincrement is optional. Just demonstrating that it works.
                @"    name         TEXT NOT NULL DEFAULT '',"
                @"    cultureCode  TEXT NOT NULL DEFAULT 'en',"
                @"    colorName    TEXT NOT NULL,"
                @"    taps         INTEGER NOT NULL DEFAULT 0,"
                @"    createdTime  INTEGER NOT NULL,"
                @"    modifiedTime INTEGER NOT NULL"
                @");"
            ]) failedAt(1);
            
            if (! [db executeUpdate:@"CREATE UNIQUE INDEX IF NOT EXISTS name ON Person (name);"]) failedAt(2);
            
            if (! [db executeUpdate:
                @"CREATE TABLE Color ("
                @"    name         TEXT NOT NULL PRIMARY KEY,"
                @"    hex          TEXT NOT NULL"
                @");"
            ]) failedAt(3);
            
            // Create any other tables...
            
            *schemaVersion = 1;
        }

        // If you wanted to change the schema in a later app version, you'd add something like this here:
        /*
        if (*schemaVersion < 2) {
            if (! [db executeUpdate:@"ALTER TABLE Person ADD COLUMN lastModified INTEGER NULL"]) failedAt(3);
            *schemaVersion = 2;
        }
        */

        [db commit];
    }];
    
    [FCModel inDatabaseSync:^(FMDatabase *db) {
        [FCModel inDatabaseSync:^(FMDatabase *db) {
            
        }];
    }];
    
    Culture *culture1 = [Culture instanceWithPrimaryKey:@"en-AU"];
    [culture1 setName:@"English Australia"];
    
    [culture1 save];

    Culture *culture2 = [Culture instanceWithPrimaryKey:@"en-US"];
    [culture2 setName:@"English US"];
    
    [culture2 save];
    
    Color *testUniqueRed0 = [Color instanceWithPrimaryKey:@"red"];
    
    // Prepopulate the Color table
    [@{
        @"red" : @"FF3838",
        @"orange" : @"FF9335",
        @"yellow" : @"FFC947",
        @"green" : @"44D875",
        @"blue1" : @"2DAAD6",
        @"blue2" : @"007CF4",
        @"purple" : @"5959CE",
        @"pink" : @"FF2B56",
        @"gray1" : @"8E8E93",
        @"gray2" : @"C6C6CC",
    } enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *hex, BOOL *stop) {
        Color *c = [Color instanceWithPrimaryKey:name];
        c.hex = hex;
        [c save];
    }];
    
    Color *testUniqueRed1 = [Color instanceWithPrimaryKey:@"red"];
    NSArray *allColors = [Color allInstances];
    Color *testUniqueRed2 = [Color instanceWithPrimaryKey:@"red"];
    
    NSAssert(testUniqueRed0 == testUniqueRed1, @"Instance-uniqueness check 1 failed");
    NSAssert(testUniqueRed1 == testUniqueRed2, @"Instance-uniqueness check 2 failed");
    
    // Comment/uncomment this to see caching/retention behavior.
    // Without retaining these, scroll the collectionview, and you'll see each cell performing a SELECT to look up its color.
    // By retaining these, all of the colors are kept in memory by primary key, and those requests become cache hits.
    self.cachedColors = allColors;
    
    NSMutableSet *colorsUsedAlready = [NSMutableSet set];
    
    // Put some data in the table if there's not enough
    int numPeople = [[Person firstValueFromQuery:@"SELECT COUNT(*) FROM $T"] intValue];
    while (numPeople < 52) {
        
        NSString *randomName = [RandomThings randomName];
        
        Person *p = [Person new];
        
        [p setCulture:culture1];
        
        
        //I know the names aren't going to match to the true culture version but lets just pretend
        p.name = [randomName stringByAppendingString:@" AU"];
        
        if (colorsUsedAlready.count >= allColors.count) [colorsUsedAlready removeAllObjects];
        
        Color *color;
        do {
            color = (Color *) allColors[([RandomThings randomUInt32] % allColors.count)];
        } while ([colorsUsedAlready member:color] && colorsUsedAlready.count < allColors.count);

        [colorsUsedAlready addObject:color];
        p.color = color;
        
        if([p save])
            numPeople++;
        else
            NSLog(@"First Person failed");
        
        
        
        //Now create the other culture version of the person
        Person *p2 = [Person new];
        
        [p2 setCulture:culture2];
        
        //I know the names aren't going to match to the true culture version but lets just pretend
        p2.name = [randomName stringByAppendingString:@" US"];
        
        p2.color = color;
        
        [p2 save];
        
        if([p2 save])
            numPeople++;
        else
            NSLog(@"Second Person failed");
        
        
    }
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
							
@end
