#import "DocumentWindowController.h"
#import "ProjectLayoutView.h"
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <OakTextView/OakDocumentView.h>
#import <OakTextView/OakTextView.h>
#import <OakFoundation/OakFoundation.h>
#import <Find/Find.h>

@class Bundle;
@class KVDB;

// ==========================================
// = Shared static functions & global state =
// ==========================================

NSMutableDictionary<NSUUID*, DocumentWindowController*>* AllControllers (void);
NSArray<DocumentWindowController*>* SortedControllers (void);
bool is_disposable (OakDocument* doc);

extern NSUInteger DisableSessionSavingCount;

// ==========================================
// = Private class extension                =
// ==========================================
//
// Properties and ivars live here (synthesized in the main @implementation).
// Methods implemented in category files are also declared here so all
// internal callers see them; the -Wincomplete-implementation warnings
// for those methods are suppressed in the main .mm with a pragma.

@interface DocumentWindowController () <NSWindowDelegate, NSToolbarDelegate, NSTouchBarDelegate, OakTextViewDelegate, OakUserDefaultsObserver, FindDelegate>
{
	NSMutableSet<NSUUID*>*                 _stickyDocumentIdentifiers;

	std::vector<std::string>               _projectScopeAttributes;  // kSettingsScopeAttributesKey
	std::vector<std::string>               _externalScopeAttributes; // attr.project.ninja

	std::vector<std::string>               _documentScopeAttributes; // attr.os-version, attr.untitled / attr.rev-path + kSettingsScopeAttributesKey
}
@property (nonatomic) NSTitlebarAccessoryViewController* titlebarViewController;
@property (nonatomic) ProjectLayoutView*          layoutView;
@property (nonatomic) id                          tabBarModel;
@property (nonatomic) id                          splitModel;
@property (nonatomic) OakDocumentView*            documentView;
@property (nonatomic) OakTextView*                textView;

@property (nonatomic) BOOL                        autoRevealFile;

@property (nonatomic) NSSegmentedControl*         previousNextTouchBarControl;

@property (nonatomic) NSString*                   projectPath;

@property (nonatomic) NSString*                   documentPath;

@property (nonatomic) NSArray<Bundle*>*           bundlesAlreadySuggested;

@property (nonatomic, readwrite) NSArray<OakDocument*>* documents;
@property (nonatomic, readwrite) OakDocument*           selectedDocument;
@property (nonatomic) NSArrayController*                arrayController;

// Methods in main @implementation
+ (KVDB*)sharedProjectStateDB;

- (void)makeTextViewFirstResponder:(id)sender;

- (void)fileBrowserModel:(id)model openURLs:(NSArray*)someURLs;
- (void)fileBrowserModel:(id)model closeURL:(NSURL*)anURL;

- (void)takeNewTabIndexFrom:(id)sender;
- (void)takeTabsToTearOffFrom:(id)sender;

- (void)openAndSelectDocument:(OakDocument*)document activate:(BOOL)activateFlag;
- (void)closeTabsAtIndexes:(NSIndexSet*)anIndexSet askToSaveChanges:(BOOL)askToSaveFlag createDocumentIfEmpty:(BOOL)createIfEmptyFlag activate:(BOOL)activateFlag;
- (void)insertDocuments:(NSArray<OakDocument*>*)documents atIndex:(NSInteger)index selecting:(OakDocument*)selectDocument andClosing:(NSArray<NSUUID*>*)closeDocuments;
- (void)reloadTabBarData;
- (BOOL)isDocumentSticky:(OakDocument*)aDocument;
- (void)setDocument:(OakDocument*)aDocument sticky:(BOOL)stickyFlag;
- (NSUUID*)disposableDocument;
- (id)fileBrowser;

// Methods in DocumentWindowController+TouchBar.mm
- (void)updateTouchBarButtons;

// Methods in DocumentWindowController+Session.mm
+ (void)scheduleSessionBackup:(id)sender;
- (NSDictionary*)sessionInfoIncludingUntitledDocuments:(BOOL)includeUntitled;
- (void)setupControllerForProject:(NSDictionary*)project skipMissingFiles:(BOOL)skipMissing;
- (std::map<std::string, std::string>)variables;

// Methods in OakDocumentController+DocumentWindow.mm
- (void)bringToFront;
@end
