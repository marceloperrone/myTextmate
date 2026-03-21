#import "AppController.h"

// Forward-declare DocumentWindowController methods needed by Swift.
// Cannot import DocumentWindowController.h directly because it includes C++ headers.
@interface DocumentWindowController : NSResponder
+ (BOOL)saveSessionIncludingUntitledDocuments:(BOOL)includeUntitled;
@end
