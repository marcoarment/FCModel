//
//  FCModelDatabaseQueue.h
//
//  Created by Marco Arment on 3/12/14.
//  Copyright (c) 2014 Marco Arment. See included LICENSE file.
//

@import Foundation;

#ifdef COCOAPODS
#import <FMDB/FMDatabase.h>
#else
#import "FMDatabase.h"
#endif

// This serves the same role as FMDB's FMDatabaseQueue for FCModel, but with some differences:
//
//  - inDatabase calls can be nested without deadlocking. (See execOnSelfSync: in implementation.)
//  - Leaving any open FMResultSets after an inDatabase block raises an exception rather than logging a warning.
//  - The FMDatabase object is exposed as a readonly property for advanced, careful use if necessary.

@interface FCModelDatabaseQueue : NSOperationQueue

- (instancetype)initWithDatabasePath:(NSString *)filename;
- (void)inDatabase:(void (^)(FMDatabase *db))block;
- (void)close;

@property (nonatomic, readonly) FMDatabase *database;

@end
