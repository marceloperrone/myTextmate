#import "FileItem.h"
#import "FSEventsManager.h"

// =============================
// = File system status observer =
// =============================

@interface FileSystemObserver : NSObject
{
	void(^_handler)(NSArray<NSURL*>*);
	id _fsEventsObserver;
}
@end

@implementation FileSystemObserver
- (instancetype)initWithURL:(NSURL*)url usingBlock:(void(^)(NSArray<NSURL*>*))handler
{
	if(self = [super init])
	{
		_handler = handler;

		__weak FileSystemObserver* weakSelf = self;
		_fsEventsObserver = [FSEventsManager.sharedInstance addObserverToDirectoryAtURL:url usingBlock:^(NSURL*){
			[weakSelf loadContentsOfDirectoryAtURL:url];
		}];

		[self loadContentsOfDirectoryAtURL:url];
	}
	return self;
}

- (void)dealloc
{
	[FSEventsManager.sharedInstance removeObserver:_fsEventsObserver];
}

- (void)loadContentsOfDirectoryAtURL:(NSURL*)url
{
	__weak FileSystemObserver* weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSArray<NSURL*>* urls = [NSFileManager.defaultManager contentsOfDirectoryAtURL:url includingPropertiesForKeys:@[ NSURLIsDirectoryKey, NSURLIsPackageKey, NSURLIsSymbolicLinkKey, NSURLIsHiddenKey, NSURLLocalizedNameKey, NSURLEffectiveIconKey ] options:0 error:nil];
		dispatch_async(dispatch_get_main_queue(), ^{
			if(FileSystemObserver* strongSelf = weakSelf)
				strongSelf->_handler(urls);
		});
	});
}
@end

// ===================================================
// = Helper classes to manage abstract URL observers =
// ===================================================

@class URLObserver;

@interface URLObserverClient : NSObject
@property (nonatomic, readonly) void(^handler)(NSArray<NSURL*>*);
@property (nonatomic) URLObserver* URLObserver;
- (instancetype)initWithBlock:(void(^)(NSArray<NSURL*>*))handler;
- (void)removeFromURLObserver;
@end

@interface URLObserver : NSObject
@property (nonatomic, readonly) NSURL* URL;
@property (nonatomic, readonly) NSMutableArray<URLObserverClient*>* clients;
@property (nonatomic) id driver;
@property (nonatomic) NSArray<NSURL*>* cachedURLs;
- (void)addClient:(URLObserverClient*)client;
- (void)removeClient:(URLObserverClient*)client;
@end

@implementation URLObserver
- (instancetype)initWithURL:(NSURL*)url
{
	if(self = [super init])
	{
		_URL     = url;
		_clients = [NSMutableArray array];
	}
	return self;
}

- (void)setCachedURLs:(NSArray<NSURL*>*)urls
{
	_cachedURLs = urls;
	for(URLObserverClient* client in [_clients copy])
		client.handler(urls);
}

- (void)addClient:(URLObserverClient*)client
{
	client.URLObserver = self;
	[_clients addObject:client];
	if(_cachedURLs && _cachedURLs.count)
		client.handler(_cachedURLs);
}

- (void)removeClient:(URLObserverClient*)client
{
	[_clients removeObject:client];
	client.URLObserver = nil;
}
@end

@implementation URLObserverClient
- (instancetype)initWithBlock:(void(^)(NSArray<NSURL*>*))handler
{
	if(self = [super init])
	{
		_handler = handler;
	}
	return self;
}

- (void)removeFromURLObserver
{
	[_URLObserver removeClient:self];
}
@end

// ==============================
// = FileItem observer category =
// ==============================

@implementation FileItem (Observer)
+ (URLObserverClient*)addObserverToDirectoryAtURL:(NSURL*)url usingBlock:(void(^)(NSArray<NSURL*>*))handler
{
	static NSMapTable<NSURL*, URLObserver*>* observers = [NSMapTable strongToWeakObjectsMapTable];

	URLObserver* observer = [observers objectForKey:url];
	if(!observer)
	{
		observer = [[URLObserver alloc] initWithURL:url];
		[observers setObject:observer forKey:url];
	}

	URLObserverClient* client = [[URLObserverClient alloc] initWithBlock:handler];
	[observer addClient:client];

	if(!observer.driver)
	{
		__weak URLObserver* weakObserver = observer;
		observer.driver = [[self classForURL:url] makeObserverForURL:url usingBlock:^(NSArray<NSURL*>* urls){
			weakObserver.cachedURLs = urls;
		}];
	}

	return client;
}

+ (void)removeObserver:(URLObserverClient*)someObserver
{
	[someObserver removeFromURLObserver];
}

+ (id)makeObserverForURL:(NSURL*)url usingBlock:(void(^)(NSArray<NSURL*>*))handler
{
	return url.isFileURL ? [[FileSystemObserver alloc] initWithURL:url usingBlock:handler] : nil;
}
@end
