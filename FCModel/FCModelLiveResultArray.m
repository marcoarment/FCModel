//
//  FCModelCachedResultSet.m
//
//  Created by Marco Arment on 3/1/14.
//  Copyright (c) 2014 Marco Arment. See included LICENSE file.
//

#import "FCModelLiveResultArray.h"
#import "FCModel.h"

@interface FCModelResultCache : NSObject
@property (nonatomic) NSCache *cache;

+ (instancetype)sharedInstance;
- (void)clear:(id)sender;
- (FCModelLiveResultArray *)liveArrayWithModelClass:(Class)fcModelClass queryAfterWHERE:(NSString *)query arguments:(NSArray *)arguments;
@end

@implementation FCModelResultCache

+ (instancetype)sharedInstance
{
    static FCModelResultCache *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    if ( (self = [super init]) ) {
        self.cache = [[NSCache alloc] init];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clear:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)clear:(id)sender { [self.cache removeAllObjects]; }

- (FCModelLiveResultArray *)liveArrayWithModelClass:(Class)fcModelClass queryAfterWHERE:(NSString *)query arguments:(NSArray *)arguments
{
    NSCache *classCache = [self.cache objectForKey:fcModelClass];
    if (! classCache) {
        classCache = [[NSCache alloc] init];
        [self.cache setObject:classCache forKey:fcModelClass];
    }
    
    NSCache *queryCache = [classCache objectForKey:(query ?: @"")];
    if (! queryCache) {
        queryCache = [[NSCache alloc] init];
        [classCache setObject:queryCache forKey:(query ?: @"")];
    }
    
    FCModelLiveResultArray *cachedLiveArray = [queryCache objectForKey:(arguments ?: @"")];
    if (! cachedLiveArray) {
        cachedLiveArray = [FCModelLiveResultArray arrayWithModelClass:fcModelClass queryAfterWHERE:query arguments:arguments fromGlobalCache:NO];
        [queryCache setObject:cachedLiveArray forKey:(arguments ?: @"")];
        NSLog(@"[QCache] miss %@:{%@} [%@]", NSStringFromClass(fcModelClass), query, [arguments componentsJoinedByString:@","]);
    } else {
        NSLog(@"[QCache] +HIT %@:{%@} [%@]", NSStringFromClass(fcModelClass), query, [arguments componentsJoinedByString:@","]);
    }
    
    return cachedLiveArray;
}

@end


#pragma mark - FCModelLiveResultArray

@interface FCModelLiveResultArray ()
@property (nonatomic) Class modelClass;
@property (nonatomic) NSString *queryAfterWHERE;
@property (nonatomic) NSArray  *queryArguments;
@property (nonatomic) NSArray  *currentResults;
@end

@implementation FCModelLiveResultArray

+ (void)clearGlobalCache { [FCModelResultCache.sharedInstance clear:nil]; }

+ (instancetype)arrayWithModelClass:(Class)fcModelClass queryAfterWHERE:(NSString *)query arguments:(NSArray *)arguments fromGlobalCache:(BOOL)cache
{
    if (cache) return [FCModelResultCache.sharedInstance liveArrayWithModelClass:fcModelClass queryAfterWHERE:query arguments:arguments];

    FCModelLiveResultArray *set = [self new];
    set.modelClass = fcModelClass;
    set.queryAfterWHERE = query;
    set.queryArguments = arguments;

    [NSNotificationCenter.defaultCenter addObserver:set selector:@selector(tableChanged:) name:FCModelWillReloadNotification object:FCModel.class];
    [NSNotificationCenter.defaultCenter addObserver:set selector:@selector(tableChanged:) name:FCModelWillReloadNotification object:fcModelClass];
    [NSNotificationCenter.defaultCenter addObserver:set selector:@selector(tableChanged:) name:FCModelAnyChangeNotification object:FCModel.class];
    [NSNotificationCenter.defaultCenter addObserver:set selector:@selector(tableChanged:) name:FCModelAnyChangeNotification object:fcModelClass];
    [NSNotificationCenter.defaultCenter addObserver:set selector:@selector(tableChanged:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    
    return set;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelWillReloadNotification object:FCModel.class];
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelWillReloadNotification object:_modelClass];
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelAnyChangeNotification object:FCModel.class];
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelAnyChangeNotification object:_modelClass];
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

- (void)tableChanged:(NSNotification *)n
{
    self.currentResults = nil;
}

- (void)fetch
{
    self.currentResults = _queryAfterWHERE ? [_modelClass instancesWhere:_queryAfterWHERE arguments:_queryArguments] : [_modelClass allInstances];
}

- (NSArray *)allObjects
{
    if (! self.currentResults) [self fetch];
    return [self.currentResults copy];
}

@end
