#import "AboutWindowController.h"
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>

@interface AboutWindowController () <NSWindowDelegate, WKNavigationDelegate>
@property (nonatomic) WKWebView* webView;
@end

@implementation AboutWindowController
+ (instancetype)sharedInstance
{
	static AboutWindowController* sharedInstance = [self new];
	return sharedInstance;
}

- (id)init
{
	NSRect rect = NSMakeRect(0, 0, 460, 500);
	NSUInteger styleMask = NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskFullSizeContentView;
	NSWindow* win = [[NSPanel alloc] initWithContentRect:rect styleMask:styleMask backing:NSBackingStoreBuffered defer:NO];
	if((self = [super initWithWindow:win]))
	{
		[win center];
		[win setDelegate:self];
		[win setHidesOnDeactivate:NO];
		[win setTitleVisibility:NSWindowTitleHidden];

		WKWebViewConfiguration* webConfig = [[WKWebViewConfiguration alloc] init];

		self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:webConfig];
		self.webView.navigationDelegate = self;
		[self.webView setValue:@NO forKey:@"drawsBackground"];

		if(NSURL* url = [NSBundle.mainBundle URLForResource:@"WKWebView" withExtension:@"js"])
		{
			NSError* error;
			if(NSMutableString* jsBridge = [NSMutableString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error])
			{
				NSDictionary* variables = @{
					@"version":   [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
					@"copyright": [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSHumanReadableCopyright"],
				};

				[variables enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* value, BOOL* stop){
					[jsBridge appendFormat:@"TextMate.%@ = %@;\n", key, [self javaScriptEscapedString:value]];
				}];

				WKUserScript* script = [[WKUserScript alloc] initWithSource:jsBridge injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
				[self.webView.configuration.userContentController addUserScript:script];
			}
			else if(error)
			{
				os_log_error(OS_LOG_DEFAULT, "Failed to load WKWebView.js: %{public}@", error.localizedDescription);
			}
		}
		else
		{
			os_log_error(OS_LOG_DEFAULT, "Failed to locate WKWebView.js in application bundle");
		}

		[self.webView.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
		[self.webView.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

		[win setContentView:self.webView];

		if(NSURL* url = [NSBundle.mainBundle URLForResource:@"About/About" withExtension:@"html"])
			[self.webView loadRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60]];
	}
	return self;
}

- (void)dealloc
{
	[_webView.configuration.userContentController removeAllUserScripts];
	_webView.navigationDelegate = nil;
	[_webView stopLoading];
}

- (void)showAboutWindow:(id)sender
{
	[self showWindow:self];
}

- (NSString*)javaScriptEscapedString:(NSString*)src
{
	static NSRegularExpression* const regex = [NSRegularExpression regularExpressionWithPattern:@"['\"\\\\]" options:0 error:nil];
	NSString* escaped = src ? [regex stringByReplacingMatchesInString:src options:0 range:NSMakeRange(0, src.length) withTemplate:@"\\\\$0"] : @"";
	escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
	return [NSString stringWithFormat:@"'%@'", escaped];
}

- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction decisionHandler:(void(^)(WKNavigationActionPolicy))decisionHandler
{
	if(![navigationAction.request.URL.scheme isEqualToString:@"file"] && [NSWorkspace.sharedWorkspace openURL:navigationAction.request.URL])
			decisionHandler(WKNavigationActionPolicyCancel);
	else	decisionHandler(WKNavigationActionPolicyAllow);
}
@end
