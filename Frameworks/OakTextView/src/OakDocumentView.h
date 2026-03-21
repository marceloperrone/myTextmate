#import "OakTextView.h"
#import <oak/debug.h>

@class OakDocument;

@interface OakDocumentView : NSView
@property (nonatomic, readonly) OakTextView* textView;
@property (nonatomic) OakDocument* document;
@property (nonatomic, readonly) id documentModel;
@property (nonatomic) BOOL hideStatusBar;
- (void)addAuxiliaryView:(NSView*)aView atEdge:(NSRectEdge)anEdge;
- (void)removeAuxiliaryView:(NSView*)aView;

- (void)showFindBar;
- (void)showFindBarWithSelection;
- (void)hideFindBar;
@property (nonatomic, readonly) BOOL isFindBarVisible;

@end
