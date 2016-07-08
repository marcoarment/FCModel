//
//  FCModelCachedObject.m
//
//  Created by Marco Arment on 3/1/14.
//  Copyright (c) 2014 Marco Arment. See included LICENSE file.
//

#import "FCModelCachedObject.h"
#import "FCModel.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

// FCModelCachedObject has its own notification that runs BEFORE the other FCModel change notifications
//  so it can remove stale data before any application actions fetch new data in response to the change.
extern NSString * const FCModelWillSendChangeNotification;

#pragma mark - Global cache

@interface FCModelGeneratedObjectCache : NSObject
@property (nonatomic) NSMutableDictionary *cache;
@property (nonatomic) dispatch_queue_t cacheQueue;

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
        self.cacheQueue = dispatch_queue_create("FCModelGeneratedObjectCache", NULL);
        self.cache = [NSMutableDictionary dictionary];
#if TARGET_OS_IPHONE
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clear:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self clear:nil];
}

- (void)clear:(id)sender
{
    dispatch_sync(self.cacheQueue, ^{
        [self.cache removeAllObjects];
    });
}

- (void)saveObject:(FCModelCachedObject *)obj class:(Class)fcModelClass identifier:(id)identifier
{
    dispatch_sync(self.cacheQueue, ^{
        NSMutableDictionary *classCache = self.cache[fcModelClass];
        if (! classCache) {
            classCache = [NSMutableDictionary dictionary];
            self.cache[(id)fcModelClass] = classCache;
        }
        
        classCache[identifier] = obj;
    });
}

- (FCModelCachedObject *)objectWithModelClass:(Class)fcModelClass identifier:(id)identifier
{
    __block FCModelCachedObject *result = nil;
    dispatch_sync(self.cacheQueue, ^{
        NSMutableDictionary *classCache = self.cache[fcModelClass];
        if (! classCache) return;
        result = classCache[identifier];
    });
    return result;
}

@end


#pragma mark - FCModelCachedObject

@interface FCModelCachedObject ()

@property (nonatomic) Class modelClass;
@property (nonatomic, copy) id (^generator)(void);
@property (nonatomic) BOOL currentResultIsValid;
@property (nonatomic) id currentResult;
@property (nonatomic) NSSet *ignoredFieldsForInvalidation;

@end

@implementation FCModelCachedObject

+ (void)clearCache
{
    [FCModelGeneratedObjectCache.sharedInstance clear:nil];
}

+ (instancetype)objectWithModelClass:(Class)fcModelClass cacheIdentifier:(id)identifier generator:(id (^)(void))generatorBlock
{
    return [self objectWithModelClass:fcModelClass cacheIdentifier:identifier ignoreFieldsForInvalidation:nil generator:generatorBlock];
}

+ (instancetype)objectWithModelClass:(Class)fcModelClass cacheIdentifier:(id)identifier ignoreFieldsForInvalidation:(NSSet *)ignoredFields generator:(id (^)(void))generatorBlock
{
    FCModelCachedObject *obj = [FCModelGeneratedObjectCache.sharedInstance objectWithModelClass:fcModelClass identifier:identifier];

    if (! obj) {
        obj = [[FCModelCachedObject alloc] init];
        obj.modelClass = fcModelClass;
        obj.generator = generatorBlock;
        obj.ignoredFieldsForInvalidation = ignoredFields;

        [NSNotificationCenter.defaultCenter addObserver:obj selector:@selector(dataSourceChanged:) name:FCModelWillSendChangeNotification object:fcModelClass];

#if TARGET_OS_IPHONE
        [NSNotificationCenter.defaultCenter addObserver:obj selector:@selector(flush:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif

        [FCModelGeneratedObjectCache.sharedInstance saveObject:obj class:fcModelClass identifier:identifier];
    }
    return obj;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)dataSourceChanged:(NSNotification *)n
{
    if (n.object != nil && n.object != self.modelClass) return;
    
    NSSet *changedFields, *ignoredFields = self.ignoredFieldsForInvalidation;
    if (ignoredFields && (changedFields = n.userInfo[FCModelChangedFieldsKey]) ) {
        NSMutableSet *fieldsWeCareAbout = [changedFields mutableCopy];
        [fieldsWeCareAbout minusSet:ignoredFields];
        if (fieldsWeCareAbout.count == 0) return;
    }
    
    [self flush:n];
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
@end

@implementation FCModelLiveResultArray

+ (instancetype)arrayWithModelClass:(Class)fcModelClass queryAfterWHERE:(NSString *)query arguments:(NSArray *)arguments ignoreFieldsForInvalidation:(NSSet *)ignoredFields
{
    FCModelLiveResultArray *set = [self new];
    
    set.cachedObject = [FCModelCachedObject objectWithModelClass:fcModelClass cacheIdentifier:@[(query ?: NSNull.null), (arguments ?: NSNull.null)] ignoreFieldsForInvalidation:ignoredFields generator:^id{
        return query ? [fcModelClass instancesWhere:query arguments:arguments] : [fcModelClass allInstances];
    }];

    return set;
}

- (NSArray *)allObjects { return self.cachedObject.value; }

@end

