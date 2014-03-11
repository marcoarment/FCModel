//
//  FCModelCachedObject.m
//
//  Created by Marco Arment on 3/1/14.
//  Copyright (c) 2014 Marco Arment. See included LICENSE file.
//

#import "FCModelCachedObject.h"
#import "FCModel.h"

#pragma mark - Global cache

@interface FCModelGeneratedObjectCache : NSObject
@property (nonatomic) NSCache *cache;

+ (instancetype)sharedInstance;
- (void)clear:(id)sender;
- (FCModelCachedObject *)objectWithModelClass:(Class)fcModelClass identifier:(id)identifier;
- (void)saveObject:(FCModelCachedObject *)obj class:(Class)fcModelClass identifier:(id)identifier;

@end

@implementation FCModelGeneratedObjectCache

+ (instancetype)sharedInstance
{
    static FCModelGeneratedObjectCache *instance = nil;
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
#if TARGET_OS_IPHONE
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clear:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
    }
    return self;
}

#if TARGET_OS_IPHONE
- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}
#endif

- (void)clear:(id)sender { [self.cache removeAllObjects]; }

- (void)saveObject:(FCModelCachedObject *)obj class:(Class)fcModelClass identifier:(id)identifier
{
    NSCache *classCache = [self.cache objectForKey:fcModelClass];
    if (! classCache) {
        classCache = [[NSCache alloc] init];
        [self.cache setObject:classCache forKey:fcModelClass];
    }
    
    [classCache setObject:obj forKey:identifier];
}

- (FCModelCachedObject *)objectWithModelClass:(Class)fcModelClass identifier:(id)identifier
{
    NSCache *classCache = [self.cache objectForKey:fcModelClass];
    if (! classCache) return nil;
    return [classCache objectForKey:identifier];
}

@end


#pragma mark - FCModelCachedObject

@interface FCModelCachedObject ()

@property (nonatomic) Class modelClass;
@property (nonatomic, copy) id (^generator)(void);
@property (nonatomic) BOOL currentResultIsValid;
@property (nonatomic) id currentResult;

@end

@implementation FCModelCachedObject

+ (void)clearCache
{
    [FCModelGeneratedObjectCache.sharedInstance clear:nil];
}

+ (instancetype)objectWithModelClass:(Class)fcModelClass cacheIdentifier:(id)identifier generator:(id (^)(void))generatorBlock
{
    FCModelCachedObject *obj = [FCModelGeneratedObjectCache.sharedInstance objectWithModelClass:fcModelClass identifier:identifier];
    
    if (! obj) {
        obj = [[FCModelCachedObject alloc] init];
        obj.modelClass = fcModelClass;
        obj.generator = generatorBlock;

        [NSNotificationCenter.defaultCenter addObserver:obj selector:@selector(flush:) name:FCModelWillReloadNotification object:FCModel.class];
        [NSNotificationCenter.defaultCenter addObserver:obj selector:@selector(flush:) name:FCModelWillReloadNotification object:fcModelClass];
        [NSNotificationCenter.defaultCenter addObserver:obj selector:@selector(flush:) name:FCModelAnyChangeNotification object:FCModel.class];
        [NSNotificationCenter.defaultCenter addObserver:obj selector:@selector(flush:) name:FCModelAnyChangeNotification object:fcModelClass];

#if TARGET_OS_IPHONE
        [NSNotificationCenter.defaultCenter addObserver:obj selector:@selector(flush:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif

        [FCModelGeneratedObjectCache.sharedInstance saveObject:obj class:fcModelClass identifier:identifier];
    }
    return obj;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelWillReloadNotification object:FCModel.class];
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelWillReloadNotification object:_modelClass];
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelAnyChangeNotification object:FCModel.class];
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelAnyChangeNotification object:_modelClass];

#if TARGET_OS_IPHONE
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
}

- (void)flush:(NSNotification *)n
{
    self.currentResult = nil;
    self.currentResultIsValid = NO;
}

- (id)value
{
    if (! self.currentResultIsValid) {
        self.currentResult = self.generator();
        self.currentResultIsValid = YES;
    }
    return self.currentResult;
}

@end



#pragma mark - FCModelLiveResultArray

@interface FCModelLiveResultArray ()
@property (nonatomic) FCModelCachedObject *cachedObject;
@property (nonatomic) Class modelClass;
@property (nonatomic) NSString *queryAfterWHERE;
@property (nonatomic) NSArray  *queryArguments;
@property (nonatomic) NSArray  *currentResults;
@end

@implementation FCModelLiveResultArray

+ (instancetype)arrayWithModelClass:(Class)fcModelClass queryAfterWHERE:(NSString *)query arguments:(NSArray *)arguments
{
    FCModelLiveResultArray *set = [self new];
    set.modelClass = fcModelClass;
    set.queryAfterWHERE = query;
    set.queryArguments = arguments;

    __weak FCModelLiveResultArray *weakSet = set;
    set.cachedObject = [FCModelCachedObject objectWithModelClass:fcModelClass cacheIdentifier:@[(query ?: NSNull.null), (arguments ?: NSNull.null)] generator:^id{
        return weakSet ? (
            weakSet.queryAfterWHERE ?
            [weakSet.modelClass instancesWhere:weakSet.queryAfterWHERE arguments:weakSet.queryArguments] :
            [weakSet.modelClass allInstances]
        ) : nil;
    }];

    return set;
}

- (NSArray *)allObjects { return self.cachedObject.value; }

@end

