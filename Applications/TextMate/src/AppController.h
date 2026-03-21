#import <Cocoa/Cocoa.h>

@interface AppController : NSObject <NSApplicationDelegate, NSMenuDelegate>

- (IBAction)orderFrontFindPanel:(id)sender;

- (IBAction)showBundleItemChooser:(id)sender;

- (IBAction)showPreferences:(id)sender;
- (IBAction)showBundleEditor:(id)sender;

- (IBAction)newDocumentAndActivate:(id)sender;
- (IBAction)openDocumentAndActivate:(id)sender;

- (IBAction)runPageLayout:(id)sender;
- (IBAction)openFavorites:(id)sender;
@end

@interface AppController (Documents)
- (void)newDocument:(id)sender;
- (void)openDocument:(id)sender;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender;
@end

@interface AppController (BundlesMenu)
- (BOOL)validateThemeMenuItem:(NSMenuItem*)item;
@end

void OakOpenDocuments (NSArray* paths, BOOL treatFilePackageAsFolder);
