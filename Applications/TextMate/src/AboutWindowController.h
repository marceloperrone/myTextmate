@interface AboutWindowController : NSWindowController
@property (class, readonly) AboutWindowController* sharedInstance;
- (void)showAboutWindow:(id)sender;
@end
