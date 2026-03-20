#import "DocumentWindowController.h"
#import "ProjectLayoutView.h"
#import "SelectGrammarViewController.h"
#import "OakRunCommandWindowController.h"
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <OakAppKit/NSAlert Additions.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakPasteboard.h>
#import <OakAppKit/OakSavePanel.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <MenuBuilder/MenuBuilder.h>
// TabBarModel (SwiftUI) — forward-declare methods used via KVC/messaging on id
@interface NSObject (TabBarModelMethods)
- (void)reloadWithCount:(NSInteger)count titles:(NSArray<NSString*>*)titles paths:(NSArray<NSString*>*)paths identifiers:(NSArray<NSUUID*>*)identifiers editedFlags:(NSArray<NSNumber*>*)editedFlags;
@end

// DocumentSplitModel (SwiftUI) — forward-declare methods used via KVC/messaging on id
@interface NSObject (DocumentSplitModelMethods)
@end
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <Preferences/Keys.h>
#import <OakTextView/OakDocumentView.h>
// FileTreeModel (SwiftUI) — forward-declare methods used via KVC/messaging on id
@interface NSObject (FileTreeModelMethods)
- (void)setupViewWithState:(id)state;
- (void)goToURL:(NSURL*)url;
- (void)selectURL:(NSURL*)url withParentURL:(NSURL*)parentURL;
- (NSURL*)createFile:(id)sender;
- (NSURL*)createFolder:(id)sender;
@end
#import <OakCommand/OakCommand.h>
#import <OakFilterList/FileChooser.h>
#import <OakSystem/application.h>
#import <Find/Find.h>
#import <BundlesManager/BundlesManager.h>
#import <BundleEditor/BundleEditor.h>
#import <file/path_info.h>
#import <io/entries.h>
#import <text/parse.h>
#import <text/tokenize.h>
#import <text/utf8.h>
#import <regexp/glob.h>
#import <settings/settings.h>
#import <ns/ns.h>
#import <kvdb/kvdb.h>
#import <crash/info.h>

static NSString* const kUserDefaultsAlwaysFindInDocument = @"alwaysFindInDocument";
static NSString* const kUserDefaultsDisableFolderStateRestore = @"disableFolderStateRestore";
static NSString* const kUserDefaultsHideStatusBarKey = @"hideStatusBar";
static NSString* const kUserDefaultsDisableBundleSuggestionsKey = @"disableBundleSuggestions";
static NSString* const kUserDefaultsGrammarsToNeverSuggestKey = @"grammarsToNeverSuggest";

static bool can_reach_host (char const* host)
{
	bool res = false;
	if(SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, host))
	{
		SCNetworkReachabilityFlags flags;
		if(SCNetworkReachabilityGetFlags(ref, &flags))
		{
			if(flags & kSCNetworkReachabilityFlagsReachable)
				res = true;
		}
		CFRelease(ref);
	}
	return res;
}

static void show_command_error (std::string const& message, oak::uuid_t const& uuid, NSWindow* window = nil, std::string commandName = NULL_STR)
{
	bundles::item_ptr bundleItem = bundles::lookup(uuid);
	if(commandName == NULL_STR)
		commandName = bundleItem ? bundleItem->name() : "(unknown)";

	NSAlert* alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSAlertStyleCritical];
	[alert setMessageText:[NSString stringWithCxxString:text::format("Failure running “%.*s”.", (int)commandName.size(), commandName.data())]];
	[alert setInformativeText:[NSString stringWithCxxString:message] ?: @"No output"];
	[alert addButtonWithTitle:@"OK"];
	if(bundleItem)
		[alert addButtonWithTitle:@"Edit Command"];

	[alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse button){
		if(button == NSAlertSecondButtonReturn)
			[BundleEditor.sharedInstance revealBundleItem:bundleItem];
	}];
}

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

+ (void)scheduleSessionBackup:(id)sender;

- (void)makeTextViewFirstResponder:(id)sender;

- (void)fileBrowserModel:(id)model openURLs:(NSArray*)someURLs;
- (void)fileBrowserModel:(id)model closeURL:(NSURL*)anURL;

- (void)takeNewTabIndexFrom:(id)sender;   // used by newDocumentInTab:
- (void)takeTabsToTearOffFrom:(id)sender; // used by moveDocumentToNewWindow:
@end

namespace
{
	// ==========================================
	// = tracking document controller instances =
	// ==========================================

	static NSMutableDictionary<NSUUID*, DocumentWindowController*>* AllControllers ()
	{
		static NSMutableDictionary* res = [NSMutableDictionary new];
		return res;
	}

	static NSArray<DocumentWindowController*>* SortedControllers ()
	{
		NSMutableArray* res = [NSMutableArray array];
		for(NSNumber* flag in @[ @NO, @YES ])
		{
			for(NSWindow* window in [NSApp orderedWindows])
			{
				if([window isMiniaturized] == flag.boolValue && [window.delegate respondsToSelector:@selector(identifier)])
				{
					DocumentWindowController* delegate = (DocumentWindowController*)window.delegate;
					if(id controller = AllControllers()[delegate.identifier])
						[res addObject:controller];
				}
			}
		}
		return res;
	}

	// ======================
	// = document_t helpers =
	// ======================

	static bool is_disposable (OakDocument* doc)
	{
		return doc && !doc.isDocumentEdited && !doc.isOnDisk && !doc.path && doc.isLoaded && doc.isBufferEmpty;
	}
}

static NSArray* const kObservedKeyPaths = @[ @"arrayController.arrangedObjects.path", @"arrayController.arrangedObjects.displayName", @"arrayController.arrangedObjects.documentEdited", @"selectedDocument.path", @"selectedDocument.displayName", @"selectedDocument.icon", @"selectedDocument.onDisk" , @"selectedDocument.documentEdited" ];

@implementation DocumentWindowController
+ (KVDB*)sharedProjectStateDB
{
	NSString* appSupport = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"TextMate"];
	return [KVDB sharedDBUsingFile:@"RecentProjects.db" inDirectory:appSupport];
}

- (id)init
{
	if((self = [super init]))
	{
		self.identifier = [NSUUID UUID];

		Class TabBarModelClass = NSClassFromString(@"TabBarModel");
		self.tabBarModel = [[TabBarModelClass alloc] init];
		[self.tabBarModel setValue:self forKey:@"delegate"];
		[self.tabBarModel setValue:self forKey:@"target"];

		self.documentView = [[OakDocumentView alloc] init];
		self.textView = self.documentView.textView;
		self.textView.delegate = self;

		self.layoutView = [[ProjectLayoutView alloc] initWithFrame:NSZeroRect];
		self.layoutView.documentView = self.documentView;

		// Create DocumentSplitModel (NavigationSplitView container)
		Class SplitModelClass = NSClassFromString(@"DocumentSplitModel");
		self.splitModel = [[SplitModelClass alloc] init];
		[self.splitModel setValue:self forKey:@"delegate"];
		[[self.splitModel valueForKey:@"fileBrowser"] setValue:self forKey:@"delegate"];
		[self.splitModel setValue:self.layoutView forKey:@"detailView"];

		NSUInteger windowStyle = (NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskFullSizeContentView);
		self.window = [[NSWindow alloc] initWithContentRect:[NSWindow contentRectForFrameRect:[self frameRectForNewWindow] styleMask:windowStyle] styleMask:windowStyle backing:NSBackingStoreBuffered defer:NO];
		self.window.animationBehavior       = NSWindowAnimationBehaviorDocumentWindow;
		self.window.collectionBehavior     = NSWindowCollectionBehaviorFullScreenPrimary;
		self.window.delegate               = self;
		self.window.releasedWhenClosed     = NO;
		self.window.backgroundColor        = NSColor.windowBackgroundColor;
		self.window.titleVisibility        = NSWindowTitleVisible;
		self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;

		NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
		toolbar.delegate = self;
		toolbar.showsBaselineSeparator = NO;
		toolbar.displayMode = NSToolbarDisplayModeIconOnly;
		self.window.toolbar = toolbar;
		self.window.toolbarStyle = NSWindowToolbarStyleUnified;

		_titlebarViewController = [self.tabBarModel valueForKey:@"titlebarViewController"];
		[self.window addTitlebarAccessoryViewController:_titlebarViewController];

		NSView* hostingView = [self.splitModel valueForKey:@"hostingView"];
		OakAddAutoLayoutViewsToSuperview(@[ hostingView ], self.window.contentView);
		self.window.initialFirstResponder = self.textView;

		[self.window.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{ @"view": hostingView }]];
		[self.window.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{ @"view": hostingView }]];

		_arrayController = [[NSArrayController alloc] init];
		[_arrayController bind:NSContentBinding toObject:self withKeyPath:@"documents" options:nil];

		for(NSString* keyPath in kObservedKeyPaths)
			[self addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionInitial context:nullptr];

		OakObserveUserDefaults(self);
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActiveNotification:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidResignActiveNotification:) name:NSApplicationDidResignActiveNotification object:NSApp];
		[self userDefaultsDidChange:nil];
	}
	return self;
}

- (void)dealloc
{
	for(NSString* keyPath in kObservedKeyPaths)
		[self removeObserver:self forKeyPath:keyPath];

	[NSNotificationCenter.defaultCenter removeObserver:self];

	self.window.delegate        = nil;
	[self.tabBarModel setValue:nil forKey:@"delegate"];
	[self.tabBarModel setValue:nil forKey:@"target"];
	[self.splitModel setValue:nil forKey:@"delegate"];
	[[self.splitModel valueForKey:@"fileBrowser"] setValue:nil forKey:@"delegate"];
	self.textView.delegate      = nil;

	// When option-clicking to close all windows then
	// messages are sent to our window after windowWillClose:
	__autoreleasing __attribute__ ((unused)) NSWindow* delayRelease = self.window;
}

// ======================================
// = Find suitable frame for new window =
// ======================================

- (NSRect)windowFrame
{
	return [self.window frame];
}

- (NSRect)cascadedWindowFrame
{
	NSRect frameRect   = [self windowFrame];
	NSRect contentRect = [NSWindow contentRectForFrameRect:frameRect styleMask:self.window.styleMask];

	CGFloat offset = NSMaxY(frameRect) - NSMaxY(contentRect);
	return NSOffsetRect(frameRect, offset, -offset);
}

- (NSRect)frameRectForNewWindow
{
	std::map<CGFloat, NSWindow*> ourWindows;
	for(NSWindow* win in [NSApp windows])
	{
		if([win isVisible] && [win isOnActiveSpace] && ![win isZoomed] && (([win styleMask] & NSWindowStyleMaskFullScreen)) != NSWindowStyleMaskFullScreen && [[win delegate] isKindOfClass:[self class]])
			ourWindows.emplace(NSMaxY([win frame]), win);
	}

	if(!ourWindows.empty())
	{
		NSRect r = [(DocumentWindowController*)ourWindows.begin()->second.delegate cascadedWindowFrame];

		NSRect scrRect = [[NSScreen mainScreen] visibleFrame];
		if(NSContainsRect(scrRect, r))
			return r;

		r.origin.x = 61;
		r.origin.y = NSMaxY(scrRect) - NSHeight(r);

		BOOL alreadyHasWrappedWindow = NO;
		for(auto pair : ourWindows)
		{
			if(NSEqualPoints([pair.second frame].origin, r.origin))
				alreadyHasWrappedWindow = YES;
		}

		if(alreadyHasWrappedWindow)
		{
			NSWindow* mainWindow = [NSApp mainWindow];
			if([[mainWindow delegate] isKindOfClass:[self class]])
				r = [(DocumentWindowController*)mainWindow.delegate cascadedWindowFrame];
		}

		return r;
	}

	if(NSString* rectStr = [NSUserDefaults.standardUserDefaults stringForKey:@"DocumentControllerWindowFrame"])
		return NSRectFromString(rectStr);

	NSRect r = [[NSScreen mainScreen] visibleFrame];
	return r = NSIntegralRect(NSInsetRect(r, NSWidth(r) / 3, NSHeight(r) / 5));
}

// =========================

- (void)windowWillClose:(NSNotification*)aNotification
{
	if((([self.window styleMask] & NSWindowStyleMaskFullScreen) != NSWindowStyleMaskFullScreen) && !self.window.isZoomed)
		[NSUserDefaults.standardUserDefaults setObject:NSStringFromRect([self windowFrame]) forKey:@"DocumentControllerWindowFrame"];

	[_arrayController unbind:NSContentBinding];

	self.documents           = nil;
	self.selectedDocument    = nil;
	self.fileBrowserVisible  = NO; // Make window frame small as we no longer respond to savableWindowFrame
	self.identifier          = nil; // This removes us from AllControllers and causes a release
}

- (void)showWindow:(id)sender
{
	if(_documents.count == 0)
	{
		OakDocument* defaultDocument = [OakDocumentController.sharedInstance untitledDocument];
		self.documents = @[ defaultDocument ];
		[self openAndSelectDocument:defaultDocument activate:YES];
	}
	[self.window makeKeyAndOrderFront:sender];
}

- (void)makeTextViewFirstResponder:(id)sender { [self.window makeFirstResponder:self.textView]; }
- (void)close                                 { [self.window close]; }

- (IBAction)moveFocus:(id)sender
{
	if([self.window firstResponder] == self.textView)
	{
		self.fileBrowserVisible = YES;
		NSView* fbView = [[self.splitModel valueForKey:@"fileBrowser"] valueForKey:@"hostingView"];
		[self.window makeFirstResponder:fbView];
	}
	else
	{
		[self makeTextViewFirstResponder:sender];
	}
}

// ==========================
// = Notification Callbacks =
// ==========================

- (void)userDefaultsDidChange:(NSNotification*)aNotification
{
	self.autoRevealFile = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsAutoRevealFileKey];
	self.documentView.hideStatusBar = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsHideStatusBarKey];

	BOOL disableTabBarCollapsingKey = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableTabBarCollapsingKey];
	[self.tabBarModel setValue:@(!disableTabBarCollapsingKey && self.documents.count <= 1) forKey:@"isHidden"];
}

- (void)applicationDidBecomeActiveNotification:(NSNotification*)aNotification
{
	if(_documents.count)
		[self.textView performSelector:@selector(applicationDidBecomeActiveNotification:) withObject:aNotification];
}

- (void)applicationDidResignActiveNotification:(NSNotification*)aNotification
{
	static BOOL IsSaving = NO;
	if(std::exchange(IsSaving, YES))
		return;

	NSMutableArray* documentsToSave = [NSMutableArray array];
	for(OakDocument* doc in _documents)
	{
		if(doc.isDocumentEdited && doc.path)
		{
			settings_t const settings = settings_for_path(to_s(doc.virtualPath ?: doc.path), to_s(doc.fileType), path::parent(to_s(doc.path)));
			if(settings.get(kSettingsSaveOnBlurKey, false))
			{
				if([doc isEqual:self.selectedDocument])
					[_textView updateDocumentMetadata];
				[documentsToSave addObject:doc];
			}
		}
	}

	[self saveDocumentsUsingEnumerator:[documentsToSave objectEnumerator] completionHandler:^(OakDocumentIOResult result){
		if(_documents.count)
			[self.textView performSelector:@selector(applicationDidResignActiveNotification:) withObject:aNotification];
		IsSaving = NO;
	}];
}

// =================
// = Close Methods =
// =================

+ (NSAlert*)saveAlertForDocuments:(NSArray<OakDocument*>*)someDocuments
{
	NSAlert* alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSAlertStyleWarning];
	if(someDocuments.count == 1)
	{
		OakDocument* document = someDocuments.firstObject;
		[alert setMessageText:[NSString stringWithFormat:@"Do you want to save the changes you made in the document “%@”?", document.displayName]];
		[alert setInformativeText:@"Your changes will be lost if you don’t save them."];
		[alert addButtons:@"Save", @"Cancel", @"Don’t Save", nil];
	}
	else
	{
		NSString* body = @"";
		for(OakDocument* document in someDocuments)
			body = [body stringByAppendingFormat:@"• “%@”\n", document.displayName];
		[alert setMessageText:@"Do you want to save documents with changes?"];
		[alert setInformativeText:body];
		[alert addButtons:@"Save All", @"Cancel", @"Don’t Save", nil];
	}
	return alert;
}

- (void)showCloseWarningUIForDocuments:(NSArray<OakDocument*>*)someDocuments completionHandler:(void(^)(BOOL canClose))callback
{
	if(someDocuments.count == 0)
		return callback(YES);

	if(someDocuments.count == 1)
	{
		OakDocument* doc = someDocuments.firstObject;
		if(![doc isEqual:self.selectedDocument])
		{
			self.selectedTabIndex = [self.documents indexOfObject:doc];
			[self openAndSelectDocument:doc activate:YES];
		}
	}

	NSAlert* alert = [DocumentWindowController saveAlertForDocuments:someDocuments];
	[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode){
		switch(returnCode)
		{
			case NSAlertFirstButtonReturn: /* "Save" */
			{
				[self saveDocumentsUsingEnumerator:[someDocuments objectEnumerator] completionHandler:^(OakDocumentIOResult result){
					callback(result == OakDocumentIOResultSuccess);
				}];
			}
			break;

			case NSAlertSecondButtonReturn: /* "Cancel" */
			{
				callback(NO);
			}
			break;

			case NSAlertThirdButtonReturn: /* "Don't Save" */
			{
				callback(YES);
			}
			break;
		}
	}];
}

- (void)closeTabsAtIndexes:(NSIndexSet*)anIndexSet askToSaveChanges:(BOOL)askToSaveFlag createDocumentIfEmpty:(BOOL)createIfEmptyFlag activate:(BOOL)activateFlag
{
	NSArray<OakDocument*>* documentsToClose = [_documents objectsAtIndexes:anIndexSet];
	if(documentsToClose.count == 0)
		return;

	if(askToSaveFlag)
	{
		NSArray<OakDocument*>* documentsToSave = [documentsToClose filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDocumentEdited == YES"]];
		if(documentsToSave.count)
		{
			[self showCloseWarningUIForDocuments:documentsToSave completionHandler:^(BOOL canClose){
				if(canClose)
				{
					[self closeTabsAtIndexes:anIndexSet askToSaveChanges:NO createDocumentIfEmpty:createIfEmptyFlag activate:activateFlag];
				}
				else
				{
					NSIndexSet* newIndexes = [_documents indexesOfObjectsAtIndexes:anIndexSet options:0 passingTest:^BOOL(OakDocument* doc, NSUInteger idx, BOOL* stop){
						return doc.isDocumentEdited == NO;
					}];
					[self closeTabsAtIndexes:newIndexes askToSaveChanges:YES createDocumentIfEmpty:createIfEmptyFlag activate:activateFlag];
				}
			}];
			return;
		}
	}

	NSSet<NSUUID*>* uuids = [NSSet setWithArray:[documentsToClose valueForKey:@"identifier"]];
	NSUUID* selectedUUID = _documents[_selectedTabIndex].identifier;

	NSMutableArray<OakDocument*>* newDocuments = [NSMutableArray array];
	NSUInteger newSelectedTabIndex = _selectedTabIndex;
	for(OakDocument* document in _documents)
	{
		if(![uuids containsObject:document.identifier])
			[newDocuments addObject:document];
		if([selectedUUID isEqual:document.identifier])
			newSelectedTabIndex = MAX(newDocuments.count, 1) - 1;
	}

	if(createIfEmptyFlag && newDocuments.count == 0)
		[newDocuments addObject:[OakDocumentController.sharedInstance untitledDocument]];

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context){
		context.allowsImplicitAnimation = YES;
		self.documents        = newDocuments;
		self.selectedTabIndex = newSelectedTabIndex;
	} completionHandler:^{
	}];

	if(newDocuments.count && ![newDocuments[newSelectedTabIndex].identifier isEqual:selectedUUID])
		[self openAndSelectDocument:newDocuments[newSelectedTabIndex] activate:activateFlag];
}

- (void)performClose:(id)sender
{
	[self performCloseTab:sender];
}

- (IBAction)performCloseTab:(id)sender
{
	NSUInteger index = _selectedTabIndex;
	if(index == NSNotFound || _documents.count == 0 || _documents.count == 1 && (is_disposable(self.selectedDocument) || !self.fileBrowserVisible))
		return [self performCloseWindow:sender];
	[self closeTabsAtIndexes:[NSIndexSet indexSetWithIndex:index] askToSaveChanges:YES createDocumentIfEmpty:YES activate:YES];
}

- (IBAction)performCloseSplit:(id)sender
{
	// No-op: HTML output panel removed
}

- (IBAction)performCloseWindow:(id)sender
{
	[self.window performClose:self];
}

- (IBAction)performCloseAllTabs:(id)sender
{
	NSIndexSet* allTabs = [_documents indexesOfObjectsPassingTest:^BOOL(OakDocument* doc, NSUInteger idx, BOOL* stop){
		return [self isDocumentSticky:doc] == NO && (doc.isDocumentEdited == NO || doc.path);
	}];
	[self closeTabsAtIndexes:allTabs askToSaveChanges:YES createDocumentIfEmpty:YES activate:YES];
}

- (IBAction)performCloseOtherTabsXYZ:(id)sender
{
	NSMutableIndexSet* otherTabs = [[_documents indexesOfObjectsPassingTest:^BOOL(OakDocument* doc, NSUInteger idx, BOOL* stop){
		return [self isDocumentSticky:doc] == NO && (doc.isDocumentEdited == NO || doc.path);
	}] mutableCopy];

	NSUInteger tabIndex = _selectedTabIndex;
	[otherTabs removeIndex:tabIndex];

	[self closeTabsAtIndexes:otherTabs askToSaveChanges:YES createDocumentIfEmpty:YES activate:YES];
}

- (IBAction)performCloseTabsToTheRight:(id)sender
{
	NSUInteger from = _selectedTabIndex + 1, to = _documents.count;
	if(from < to)
		[self closeTabsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(from, to - from)] askToSaveChanges:YES createDocumentIfEmpty:YES activate:YES];
}

- (IBAction)performCloseTabsToTheLeft:(id)sender
{
	if(_selectedTabIndex > 0)
		[self closeTabsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _selectedTabIndex)] askToSaveChanges:YES createDocumentIfEmpty:YES activate:YES];
}

- (void)saveProjectState
{
	if(self.treatAsProjectWindow)
		[[DocumentWindowController sharedProjectStateDB] setValue:[self sessionInfoIncludingUntitledDocuments:NO] forKey:self.projectPath];
}

- (BOOL)windowShouldClose:(id)sender
{
	NSArray<OakDocument*>* documentsToSave = [_documents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDocumentEdited == YES"]];
	if(!documentsToSave.count)
	{
		[self saveProjectState];
		return YES;
	}

	[self showCloseWarningUIForDocuments:documentsToSave completionHandler:^(BOOL canClose){
		if(canClose)
		{
			[self saveProjectState];
			[self.window close];
		}
	}];

	return NO;
}


+ (void)saveSessionAndDetachBackups
{
	BOOL restoresSession = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableSessionRestoreKey];
	[DocumentWindowController saveSessionIncludingUntitledDocuments:restoresSession];
	for(DocumentWindowController* controller in [SortedControllers() reverseObjectEnumerator])
	{
		[controller saveProjectState];

		// Ensure we do not remove backup files, as they are used to restore untitled documents
		if(restoresSession)
		{
			for(OakDocument* document in controller.documents)
			{
				NSString* backupPath = document.backupPath;
				document.backupPath = nil;
				if(backupPath && document.path)
					unlink([backupPath fileSystemRepresentation]);
			}
		}
	}
}

- (NSArray<OakDocument*>*)documentsNeedingSaving
{
	BOOL restoresSession = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableSessionRestoreKey];

	NSMutableArray<OakDocument*>* res = [NSMutableArray array];
	for(OakDocument* doc in _documents)
	{
		if(doc.isDocumentEdited && (doc.path || !restoresSession))
			[res addObject:doc];
	}
	return res.count ? res : nil;
}

+ (void)saveControllersUsingEnumerator:(NSEnumerator*)anEnumerator completionHandler:(void(^)(OakDocumentIOResult result))callback
{
	if(DocumentWindowController* controller = [anEnumerator nextObject])
	{
		[controller saveDocumentsUsingEnumerator:[controller.documentsNeedingSaving objectEnumerator] completionHandler:^(OakDocumentIOResult result){
			if(result == OakDocumentIOResultSuccess)
				[self saveControllersUsingEnumerator:anEnumerator completionHandler:callback];
			else if(callback)
				callback(result);
		}];
	}
	else if(callback)
	{
		callback(OakDocumentIOResultSuccess);
	}
}

+ (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender
{
	NSMutableArray<DocumentWindowController*>* controllers = [NSMutableArray array];
	NSMutableArray<OakDocument*>* documents = [NSMutableArray array];
	for(DocumentWindowController* controller in SortedControllers())
	{
		if(NSArray* newDocs = controller.documentsNeedingSaving)
		{
			[controllers addObject:controller];
			[documents addObjectsFromArray:newDocs];
		}
	}

	if(controllers.count == 0)
	{
		[self saveSessionAndDetachBackups];
		return NSTerminateNow;
	}
	else if(controllers.count == 1)
	{
		DocumentWindowController* controller = controllers.firstObject;
		[controller showCloseWarningUIForDocuments:controller.documentsNeedingSaving completionHandler:^(BOOL canClose){
			if(canClose)
				[self saveSessionAndDetachBackups];
			[NSApp replyToApplicationShouldTerminate:canClose];
		}];
	}
	else
	{
		switch([[DocumentWindowController saveAlertForDocuments:documents] runModal])
		{
			case NSAlertFirstButtonReturn: /* "Save" */
			{
				[self saveControllersUsingEnumerator:[controllers objectEnumerator] completionHandler:^(OakDocumentIOResult result){
					if(result == OakDocumentIOResultSuccess)
						[self saveSessionAndDetachBackups];
					[NSApp replyToApplicationShouldTerminate:result == OakDocumentIOResultSuccess];
				}];
			}
			break;

			case NSAlertSecondButtonReturn: /* "Cancel" */
				return NSTerminateCancel;

			case NSAlertThirdButtonReturn: /* "Don't Save" */
				return NSTerminateNow;
		}
	}
	return NSTerminateLater;
}

// =====================
// = Document Tracking =
// =====================

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)anObject change:(NSDictionary*)change context:(void*)context
{
	OakDocument* document = self.selectedDocument;
	if([keyPath isEqualToString:@"selectedDocument.path"] || [keyPath isEqualToString:@"selectedDocument.displayName"])
	{
		self.documentPath = document.virtualPath ?: document.path;
		if(!self.projectPath)
			self.projectPath = [document.path stringByDeletingLastPathComponent];
	}

	if([keyPath isEqualToString:@"selectedDocument.path"] || [keyPath isEqualToString:@"selectedDocument.displayName"])
		[self updateWindowTitle];
	if([keyPath isEqualToString:@"selectedDocument.documentEdited"])
		self.window.documentEdited = document.isDocumentEdited;
	if([keyPath isEqualToString:@"selectedDocument.onDisk"] || [keyPath isEqualToString:@"selectedDocument.path"])
		self.window.representedFilename = document.isOnDisk ? document.path : @"";
	if([keyPath isEqualToString:@"selectedDocument.onDisk"] || [keyPath isEqualToString:@"selectedDocument.icon"])
		[self.window standardWindowButton:NSWindowDocumentIconButton].image = document.isOnDisk ? document.icon : nil;

	if([keyPath hasSuffix:@"arrangedObjects.path"] || [keyPath hasSuffix:@"arrangedObjects.displayName"] || [keyPath hasSuffix:@"arrangedObjects.documentEdited"])
	{
		[self reloadTabBarData];
		[[self class] scheduleSessionBackup:self];
	}
}

- (BOOL)isDocumentSticky:(OakDocument*)aDocument
{
	return [_stickyDocumentIdentifiers containsObject:aDocument.identifier];
}

- (void)setDocument:(OakDocument*)aDocument sticky:(BOOL)stickyFlag
{
	if(stickyFlag)
		_stickyDocumentIdentifiers = _stickyDocumentIdentifiers ?: [NSMutableSet set];

	if(stickyFlag)
			[_stickyDocumentIdentifiers addObject:aDocument.identifier];
	else	[_stickyDocumentIdentifiers removeObject:aDocument.identifier];
}

// ====================
// = Create Documents =
// ====================

- (IBAction)newDocumentInTab:(id)sender
{
	[self takeNewTabIndexFrom:[NSIndexSet indexSetWithIndex:_selectedTabIndex + 1]];
}

- (IBAction)newDocumentInDirectory:(id)sender
{
	if(!self.fileBrowserVisible)
		return;

	if(NSURL* url = [self.fileBrowser createFile:self])
	{
		OakDocument* doc = [OakDocumentController.sharedInstance documentWithPath:url.path];
		[self insertDocuments:@[ doc ] atIndex:_selectedTabIndex + 1 selecting:doc andClosing:self.disposableDocument ? @[ self.disposableDocument ] : nil];
		[self openAndSelectDocument:doc activate:NO];
	}
}

- (IBAction)moveDocumentToNewWindow:(id)sender
{
	if(_documents.count > 1)
		[self takeTabsToTearOffFrom:[NSIndexSet indexSetWithIndex:_selectedTabIndex]];
}

- (IBAction)mergeAllWindows:(id)sender
{
	NSMutableArray<OakDocument*>* documents = [_documents mutableCopy];
	for(DocumentWindowController* delegate in SortedControllers())
	{
		if(delegate != self && !delegate.window.isMiniaturized)
			[documents addObjectsFromArray:delegate.documents];
	}

	self.documents = documents;

	for(DocumentWindowController* delegate in SortedControllers())
	{
		if(delegate != self && !delegate.window.isMiniaturized)
			[delegate.window close];
	}
}

- (NSUUID*)disposableDocument
{
	if(_selectedTabIndex < _documents.count && is_disposable(_documents[_selectedTabIndex]))
		return _documents[_selectedTabIndex].identifier;
	return nil;
}

- (BOOL)documents:(NSArray<OakDocument*>*)lhs hasCommonSubsequenceWithDocuments:(NSArray<OakDocument*>*)rhs
{
	NSMutableSet<NSUUID*>* subsequence = [NSMutableSet setWithArray:[lhs valueForKey:@"identifier"]];
	[subsequence intersectSet:[NSSet setWithArray:[rhs valueForKey:@"identifier"]]];

	NSUInteger i = 0, j = 0;
	while(i < lhs.count && j < rhs.count)
	{
		if(![subsequence containsObject:lhs[i].identifier])
			++i;
		else if(![subsequence containsObject:rhs[j].identifier])
			++j;
		else if(![lhs[i].identifier isEqual:rhs[j].identifier])
			return NO;
		++i;
		++j;
	}

	return YES;
}

- (void)insertDocuments:(NSArray<OakDocument*>*)documents atIndex:(NSInteger)index selecting:(OakDocument*)selectDocument andClosing:(NSArray<NSUUID*>*)closeDocuments
{
	NSSet<NSUUID*>* newUUIDs = [NSSet setWithArray:[documents valueForKey:@"identifier"]];
	NSMutableSet<NSUUID*>* oldUUIDs = [NSMutableSet setWithArray:[self.documents valueForKey:@"identifier"]];
	[oldUUIDs minusSet:[NSSet setWithArray:closeDocuments]];

	BOOL shouldReorder = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableTabReorderingKey];
	NSMutableArray<OakDocument*>* newDocuments = [NSMutableArray array];
	for(NSUInteger i = 0; i <= _documents.count; ++i)
	{
		if(i == MIN(index, _documents.count))
		{
			NSMutableSet<NSUUID*>* didInsert = [NSMutableSet set];
			for(NSUInteger j = 0; j < documents.count; ++j)
			{
				if(![didInsert containsObject:documents[j].identifier] && (shouldReorder || ![oldUUIDs containsObject:documents[j].identifier]))
				{
					[newDocuments addObject:documents[j]];
					[didInsert addObject:documents[j].identifier];
				}
			}
		}

		if(i == _documents.count)
			break;
		else if(shouldReorder && [newUUIDs containsObject:_documents[i].identifier])
			continue;
		else if([closeDocuments containsObject:_documents[i].identifier])
			continue;

		[newDocuments addObject:_documents[i]];
	}

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context){
		context.allowsImplicitAnimation = [self documents:self.documents hasCommonSubsequenceWithDocuments:newDocuments];
		self.documents        = newDocuments;
		self.selectedTabIndex = [_documents indexOfObject:selectDocument];
	} completionHandler:^{
	}];
}

- (void)openItems:(NSArray*)items closingOtherTabs:(BOOL)closeOtherTabsFlag activate:(BOOL)activateFlag
{
	NSMutableArray<OakDocument*>* documents = [NSMutableArray array];
	for(NSDictionary* item in items)
	{
		OakDocument* doc;
		if(!item[@"path"] && item[@"identifier"])
			doc = [OakDocumentController.sharedInstance findDocumentWithIdentifier:[[NSUUID alloc] initWithUUIDString:item[@"identifier"]]];
		if(!doc && item[@"path"])
			doc = [OakDocumentController.sharedInstance documentWithPath:item[@"path"]];

		if(doc)
		{
			doc.recentTrackingDisabled = YES;
			if(item[@"selectionString"])
				doc.selection = item[@"selectionString"];
			[documents addObject:doc];
		}
	}

	if(!documents.count)
		return;

	NSMutableArray<NSUUID*>* tabsToClose = [NSMutableArray array];
	if(closeOtherTabsFlag)
	{
		for(OakDocument* doc in self.documents)
		{
			if(!doc.isDocumentEdited && ![self isDocumentSticky:doc])
				[tabsToClose addObject:doc.identifier];
		}
	}
	else if(NSUUID* uuid = self.disposableDocument)
	{
		[tabsToClose addObject:uuid];
	}

	[self insertDocuments:documents atIndex:_selectedTabIndex + 1 selecting:documents.lastObject andClosing:tabsToClose];
	[self openAndSelectDocument:documents.lastObject activate:activateFlag];

	if(self.tabBarModel && ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableTabAutoCloseKey])
	{
		NSInteger excessTabs = _documents.count - std::max<NSUInteger>([[self.tabBarModel valueForKey:@"countOfVisibleTabs"] integerValue], 8);
		if(excessTabs > 0)
		{
			std::multimap<NSInteger, NSUInteger> ranked;
			for(NSUInteger i = 0; i < _documents.count; ++i)
				ranked.emplace([OakDocumentController.sharedInstance lruRankForDocument:_documents[i]], i);

			NSSet<NSUUID*>* newUUIDs = [NSSet setWithArray:[documents valueForKey:@"identifier"]];

			NSMutableIndexSet* indexSet = [NSMutableIndexSet indexSet];
			for(auto const& pair : ranked)
			{
				OakDocument* doc = _documents[pair.second];
				if(!doc.isDocumentEdited && ![self isDocumentSticky:doc] && doc.isOnDisk && ![newUUIDs containsObject:doc.identifier])
					[indexSet addIndex:pair.second];
				if([indexSet count] == excessTabs)
					break;
			}

			[self closeTabsAtIndexes:indexSet askToSaveChanges:NO createDocumentIfEmpty:NO activate:activateFlag];
		}
	}
}

// ================
// = Document I/O =
// ================

- (void)didOpenDocuemntInTextView:(OakTextView*)textView
{
	for(auto const& item : bundles::query(bundles::kFieldSemanticClass, "callback.document.did-open", [textView scopeContext], bundles::kItemTypeMost, oak::uuid_t(), false))
		[textView performBundleItem:item];
}

- (void)openAndSelectDocument:(OakDocument*)document activate:(BOOL)activateFlag
{
	[document loadModalForWindow:self.window completionHandler:^(OakDocumentIOResult result, NSString* errorMessage, oak::uuid_t const& filterUUID){
		if(result == OakDocumentIOResultSuccess)
		{
			BOOL showBundleSuggestions = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableBundleSuggestionsKey];
			if(!document.fileType && showBundleSuggestions)
			{
				NSArray<BundleGrammar*>* grammars = document.proposedGrammars;
				if(NSArray* excludedGrammars = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsGrammarsToNeverSuggestKey])
					grammars = [grammars filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT (identifier.UUIDString IN %@)", excludedGrammars]];
				if(_bundlesAlreadySuggested)
					grammars = [grammars filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT (bundle IN %@)", _bundlesAlreadySuggested]];

				if([grammars count] && can_reach_host([[[NSURL URLWithString:@(REST_API)] host] UTF8String]))
				{
					self.bundlesAlreadySuggested = [(_bundlesAlreadySuggested ?: @[ ]) arrayByAddingObject:[grammars firstObject].bundle];

					SelectGrammarViewController* installer = [[SelectGrammarViewController alloc] init];
					installer.documentDisplayName = document.path || document.customName ? document.displayName : nil;

					__weak __block id documentCloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:OakDocumentWillCloseNotification object:document queue:nil usingBlock:^(NSNotification*){
						[installer dismiss];
						[NSNotificationCenter.defaultCenter removeObserver:documentCloseObserver];
					}];

					[installer showGrammars:grammars forView:_documentView completionHandler:^(SelectGrammarResponse response, BundleGrammar* grammar){
						if(response == SelectGrammarResponseInstall && grammar.bundle.isInstalled)
						{
							for(OakDocument* doc in _documents)
							{
								if([doc isEqual:document] || [[doc proposedGrammars] containsObject:grammar])
									doc.fileType = grammar.fileType;
							}
						}
						else if(response == SelectGrammarResponseNever)
						{
							NSArray* excludedGrammars = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsGrammarsToNeverSuggestKey] ?: @[ ];
							[NSUserDefaults.standardUserDefaults setObject:[excludedGrammars arrayByAddingObject:grammar.identifier.UUIDString] forKey:kUserDefaultsGrammarsToNeverSuggestKey];
						}

						if(id observer = documentCloseObserver)
							[NSNotificationCenter.defaultCenter removeObserver:observer];
					}];
				}

				std::string const docAttributes = document.path ? "attr.file.unknown-type" : "attr.untitled";
				document.fileType = to_ns(settings_for_path(to_s(document.virtualPath ?: document.path), docAttributes, to_s(self.projectPath)).get(kSettingsFileTypeKey, "text.plain"));
			}

			if(activateFlag)
				[self makeTextViewFirstResponder:self];

			crash_reporter_info_t info("old selected document ‘%s’, new selected document ‘%s’", [_selectedDocument.displayName UTF8String] ?: "nil", [document.displayName UTF8String] ?: "nil");
			self.selectedDocument = document;
			[self performSelector:@selector(didOpenDocuemntInTextView:) withObject:self.documentView.textView afterDelay:0];
			[document close];
		}
		else
		{
			if(filterUUID)
				show_command_error(to_s(errorMessage), filterUUID);

			// Close the tab that failed to open
			NSUInteger i = [_documents indexOfObject:document];
			if(i != NSNotFound)
				[self closeTabsAtIndexes:[NSIndexSet indexSetWithIndex:i] askToSaveChanges:NO createDocumentIfEmpty:self.fileBrowserVisible activate:activateFlag];

			if(_documents.count == 0)
				[self close];
		}
	}];
}

- (IBAction)saveDocument:(id)sender
{
	OakDocument* doc = self.selectedDocument;
	if(!doc)
		return;

	if(doc.path)
	{
		[self saveDocumentsUsingEnumerator:@[ doc ].objectEnumerator completionHandler:nil];
	}
	else
	{
		NSString* const suggestedFolder  = self.untitledSavePath;
		NSString* const suggestedName    = [doc displayNameWithExtension:YES];
		[OakSavePanel showWithPath:suggestedName directory:suggestedFolder fowWindow:self.window encoding:encoding::type(to_s(doc.diskNewlines), to_s(doc.diskEncoding)) fileType:doc.fileType completionHandler:^(NSString* path, encoding::type const& encoding){
			if(!path)
				return;

			std::vector<std::string> const& paths = path::expand_braces(to_s(path));
			ASSERT_LT(0, paths.size());

			doc.path = to_ns(paths[0]);
			doc.diskNewlines = to_ns(encoding.newlines());
			doc.diskEncoding = to_ns(encoding.charset());

			// if(doc.identifier == _scratchDocument)
			// 	self.scratchDocument = nil;

			if(paths.size() > 1)
			{
				// FIXME check if paths[0] already exists (overwrite)

				NSMutableArray<OakDocument*>* documents = [NSMutableArray arrayWithObject:doc];
				for(size_t i = 1; i < paths.size(); ++i)
				{
					OakDocument* newDocument = [OakDocumentController.sharedInstance documentWithPath:to_ns(paths[i])];
					newDocument.diskNewlines = to_ns(encoding.newlines());
					newDocument.diskEncoding = to_ns(encoding.charset());
					[documents addObject:newDocument];
				}

				[self insertDocuments:documents atIndex:_selectedTabIndex selecting:doc andClosing:nil];
			}

			[self saveDocumentsUsingEnumerator:@[ doc ].objectEnumerator completionHandler:nil];
		}];
	}
}

- (IBAction)saveDocumentAs:(id)sender
{
	OakDocument* doc = self.selectedDocument;
	if(!doc)
		return;

	NSString* const suggestedFolder = [doc.path stringByDeletingLastPathComponent] ?: self.untitledSavePath;
	NSString* const suggestedName   = [doc.path lastPathComponent] ?: [doc displayNameWithExtension:YES];
	[OakSavePanel showWithPath:suggestedName directory:suggestedFolder fowWindow:self.window encoding:encoding::type(to_s(doc.diskNewlines), to_s(doc.diskEncoding)) fileType:doc.fileType completionHandler:^(NSString* path, encoding::type const& encoding){
		if(!path)
			return;
		doc.path = path;
		doc.diskNewlines = to_ns(encoding.newlines());
		doc.diskEncoding = to_ns(encoding.charset());
		[self saveDocumentsUsingEnumerator:@[ doc ].objectEnumerator completionHandler:nil];
	}];
}

- (void)saveDocumentsUsingEnumerator:(NSEnumerator*)anEnumerator completionHandler:(void(^)(OakDocumentIOResult result))callback
{
	if(OakDocument* document = [anEnumerator nextObject])
	{
		id token = [NSNotificationCenter.defaultCenter addObserverForName:OakDocumentWillShowAlertNotification object:document queue:nil usingBlock:^(NSNotification*){
			NSUInteger i = [_documents indexOfObject:document];
			if(i != NSNotFound && document.isLoaded)
			{
				if(![document isEqual:self.selectedDocument])
				{
					self.selectedTabIndex = i;
					self.selectedDocument = document;
				}

				if(NSApp.isActive && (self.window.isMiniaturized || !self.window.isKeyWindow))
					[self.window makeKeyAndOrderFront:self];
			}
		}];

		[document saveModalForWindow:self.window completionHandler:^(OakDocumentIOResult result, NSString* errorMessage, oak::uuid_t const& filterUUID){
			[NSNotificationCenter.defaultCenter removeObserver:token];
			if(result == OakDocumentIOResultSuccess)
			{
				[self saveDocumentsUsingEnumerator:anEnumerator completionHandler:callback];
			}
			else
			{
				if(result == OakDocumentIOResultFailure)
				{
					[self.window.attachedSheet orderOut:self];
					if(filterUUID)
							show_command_error(to_s(errorMessage), filterUUID, self.window);
					else	[[NSAlert tmAlertWithMessageText:[NSString stringWithFormat:@"The document “%@” could not be saved.", document.displayName] informativeText:(errorMessage ?: @"Please check Console output for reason.") buttons:@"OK", nil] beginSheetModalForWindow:self.window completionHandler:nil];
				}

				if(callback)
					callback(result);
			}
		}];
	}
	else
	{
		if(callback)
			callback(OakDocumentIOResultSuccess);
	}
}

- (IBAction)saveAllDocuments:(id)sender
{
	NSArray* documentsToSave = [_documents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDocumentEdited == YES"]];
	[self saveDocumentsUsingEnumerator:[documentsToSave objectEnumerator] completionHandler:nil];
}

- (void)saveAllEditedDocuments:(BOOL)includeAllFlag completionHandler:(void(^)(BOOL didSave))callback
{
	NSArray* documentsToSave = @[ ];
	if(includeAllFlag)
		documentsToSave = [_documents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDocumentEdited == YES AND path != NULL"]];
	else if(self.selectedDocument && (self.selectedDocument.isDocumentEdited || !self.selectedDocument.isOnDisk))
		documentsToSave = @[ self.selectedDocument ];

	[self saveDocumentsUsingEnumerator:[documentsToSave objectEnumerator] completionHandler:^(OakDocumentIOResult result){
		callback(result == OakDocumentIOResultSuccess);
	}];
}

- (void)updateEnvironment:(std::map<std::string, std::string>&)res forCommand:(OakCommand*)aCommand
{
	for(auto const& pair : [self variables])
		res[pair.first] = pair.second;

	if(aCommand.firstResponder == self.fileBrowser)
	{
		NSURL* fileURL = [[self.fileBrowser valueForKey:@"selectedFileURLs"] firstObject];
		res = bundles::scope_variables(res);
		res = variables_for_path(res, to_s(fileURL.path));
	}
	else if(aCommand.firstResponder != _textView)
	{
		if([aCommand.firstResponder respondsToSelector:@selector(updateEnvironment:)])
			[(id)aCommand.firstResponder updateEnvironment:res];
	}
	else // OakTextView
	{
		[_textView updateEnvironment:res];
	}
}

- (void)showDocument:(OakDocument*)aDocument
{
	[OakDocumentController.sharedInstance showDocument:aDocument inProject:self.identifier bringToFront:YES];
}

// ================
// = Window Title =
// ================

- (void)updateWindowTitle
{
	if(self.selectedDocument.displayName)
	{
		self.window.title = [self titleForDocument:self.selectedDocument withSetting:kSettingsWindowTitleKey];
	}
	else
	{
		self.window.title = @"«no documents»";
	}
}

- (void)updateExternalAttributes
{
	struct attribute_rule_t { std::string attribute; path::glob_t glob; std::string group; };
	static auto const rules = new std::vector<attribute_rule_t>
	{
		{ "attr.project.ninja",   "build.ninja",    "build"   },
		{ "attr.project.make",    "Makefile",       "build"   },
		{ "attr.project.xcode",   "*.xcodeproj",    "build"   },
		{ "attr.project.rake",    "Rakefile",       "build"   },
		{ "attr.project.ant",     "build.xml",      "build"   },
		{ "attr.project.cmake",   "CMakeLists.txt", "build"   },
		{ "attr.project.maven",   "pom.xml",        "build"   },
		{ "attr.project.scons",   "SConstruct",     "build"   },
		{ "attr.project.lein",    "project.clj",    "build"   },
		{ "attr.project.cargo",   "Cargo.toml",     "build"   },
		{ "attr.project.swift",   "Package.swift",  "build"   },
		{ "attr.project.vagrant", "Vagrantfile",    NULL_STR  },
		{ "attr.project.jekyll",  "_config.yml",    NULL_STR  },
		{ "attr.project.rave",    "default.rave",   NULL_STR  },
		{ "attr.test.rspec",      ".rspec",         "test"    },
	};

	_externalScopeAttributes.clear();
	if(!self.selectedDocument && !_projectPath)
		return;

	std::string const projectDir   = to_s(_projectPath ?: NSHomeDirectory());
	std::string const documentPath = self.selectedDocument.path ? to_s(self.selectedDocument.path) : path::join(projectDir, "dummy");

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{

		std::vector<std::string> res;
		std::set<std::string> groups;
		std::string dir = documentPath;
		do {

			dir = path::parent(dir);
			auto entries = path::entries(dir);

			for(auto rule : *rules)
			{
				if(groups.find(rule.group) != groups.end())
					continue;

				for(auto entry : entries)
				{
					if(rule.glob.does_match(entry->d_name))
					{
						res.push_back(rule.attribute);
						if(rule.group != NULL_STR)
						{
							groups.insert(rule.group);
							break;
						}
					}
				}
			}

		} while(path::is_child(dir, projectDir) && dir != projectDir);

		dispatch_async(dispatch_get_main_queue(), ^{
			std::string const currentProjectDir   = to_s(_projectPath ?: NSHomeDirectory());
			std::string const currentDocumentPath = self.selectedDocument.path ? to_s(self.selectedDocument.path) : path::join(projectDir, "dummy");
			if(projectDir == currentProjectDir && documentPath == currentDocumentPath)
				_externalScopeAttributes = res;
		});

	});
}

- (void)setProjectPath:(NSString*)newProjectPath
{
	if(_projectPath != newProjectPath && ![_projectPath isEqualToString:newProjectPath])
	{
		_projectPath = newProjectPath;
		_projectScopeAttributes.clear();

		std::string const customAttributes = settings_for_path(NULL_STR, text::join(_projectScopeAttributes, " "), to_s(_projectPath)).get(kSettingsScopeAttributesKey, NULL_STR);
		if(customAttributes != NULL_STR)
			_projectScopeAttributes.push_back(customAttributes);

		[self updateExternalAttributes];
		[self updateWindowTitle];
	}
}

- (void)setDocumentPath:(NSString*)newDocumentPath
{
	if(_documentPath != newDocumentPath && !([_documentPath isEqualToString:newDocumentPath]) || _documentScopeAttributes.empty())
	{
		_documentPath = newDocumentPath;
		_documentScopeAttributes = text::split(file::path_attributes(to_s(_documentPath)), " ");

		std::string docDirectory = _documentPath ? path::parent(to_s(_documentPath)) : to_s(self.projectPath);

		if(self.selectedDocument)
		{
			std::string const customAttributes = settings_for_path(to_s(_documentPath), to_s(self.selectedDocument.fileType) + " " + text::join(_documentScopeAttributes, " "), docDirectory).get(kSettingsScopeAttributesKey, NULL_STR);
			if(customAttributes != NULL_STR)
				_documentScopeAttributes.push_back(customAttributes);
		}

		[self updateExternalAttributes];

		if(self.autoRevealFile && self.selectedDocument.path && self.fileBrowserVisible)
			[self revealFileInProject:self];
	}
}

- (void)takeProjectPathFrom:(NSMenuItem*)aMenuItem
{
	if(NSString* path = [aMenuItem respondsToSelector:@selector(representedObject)] ? [aMenuItem representedObject] : nil)
		self.projectPath = self.defaultProjectPath = path;
}

// ========================
// = OakTextView Delegate =
// ========================

- (NSString*)scopeAttributes
{
	std::set<std::string> attributes;

	attributes.insert(_documentScopeAttributes.begin(), _documentScopeAttributes.end());
	attributes.insert(_projectScopeAttributes.begin(), _projectScopeAttributes.end());
	attributes.insert(_externalScopeAttributes.begin(), _externalScopeAttributes.end());

	return [NSString stringWithCxxString:text::join(attributes, " ")];
}

// ==============
// = Properties =
// ==============

- (void)setDocuments:(NSArray<OakDocument*>*)newDocuments
{
	for(OakDocument* document in newDocuments)
	{
		document.keepBackupFile = YES;
		[document open];

		// Avoid resetting directory when tearing off a tab (unless moved to new project)
		if(!document.path && (self.projectPath || !document.directory))
			document.directory = self.projectPath ?: self.defaultProjectPath;
	}

	for(OakDocument* document in _documents)
		[document close];

	_documents = newDocuments;
	if(_documents.count)
	{
		[self reloadTabBarData];
		NSInteger currentSelected = [[self.tabBarModel valueForKey:@"selectedIndex"] integerValue];
		if(currentSelected < 0 || (NSUInteger)currentSelected >= _documents.count)
			[self.tabBarModel setValue:@(MIN(_selectedTabIndex, _documents.count-1)) forKey:@"selectedIndex"];
	}

	BOOL disableTabBarCollapsingKey = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableTabBarCollapsingKey];
	[self.tabBarModel setValue:@(!disableTabBarCollapsingKey && self.documents.count <= 1) forKey:@"isHidden"];

	[self updateTouchBarButtons];
	[[self class] scheduleSessionBackup:self];
}

- (void)setSelectedDocument:(OakDocument*)newDocument
{
	ASSERT(!newDocument || newDocument.isLoaded);
	if([_selectedDocument isEqual:newDocument])
	{
		self.documentView.document = _selectedDocument;
		return;
	}

	[OakDocumentController.sharedInstance didTouchDocument:_selectedDocument];
	[OakDocumentController.sharedInstance didTouchDocument:newDocument];

	if(_selectedDocument = newDocument)
	{
		NSString* projectPath = self.defaultProjectPath ?: [self.fileBrowser valueForKey:@"path"] ?: [newDocument.path stringByDeletingLastPathComponent];
		if(projectPath)
		{
			std::map<std::string, std::string> const map = { { "projectDirectory", to_s(projectPath) } };
			settings_t const settings = settings_for_path(NULL_STR, scope::scope_t(), to_s(projectPath), map);
			std::string const userProjectDirectory = settings.get(kSettingsProjectDirectoryKey, NULL_STR);
			if(path::is_absolute(userProjectDirectory))
				projectPath = [NSString stringWithCxxString:path::normalize(userProjectDirectory)];
		}
		else if(NSString* urlString = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsInitialFileBrowserURLKey])
		{
			if(NSURL* url = [NSURL URLWithString:urlString])
				projectPath = [[url filePathURL] path];
		}

		self.projectPath = projectPath;

		self.documentView.document = _selectedDocument;
		[[self class] scheduleSessionBackup:self];
	}
	else
	{
		self.projectPath = nil;
	}
}

- (void)setSelectedTabIndex:(NSUInteger)newSelectedTabIndex
{
	_selectedTabIndex = newSelectedTabIndex;
	[self.tabBarModel setValue:@(newSelectedTabIndex) forKey:@"selectedIndex"];
}

- (void)setIdentifier:(NSUUID*)newIdentifier
{
	if(_identifier == newIdentifier || [_identifier isEqual:newIdentifier])
		return;

	NSUUID* oldIdentifier = _identifier;
	if(_identifier = newIdentifier)
		[AllControllers() setObject:self forKey:newIdentifier];

	if(oldIdentifier)
		[AllControllers() removeObjectForKey:oldIdentifier]; // This may release our object
}

// =============================
// = TabBarModel Data Reloading =
// =============================

- (void)reloadTabBarData
{
	NSUInteger count = _documents.count;
	NSMutableArray<NSString*>* titles      = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray<NSString*>* paths       = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray<NSUUID*>*   identifiers = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray<NSNumber*>* editedFlags = [NSMutableArray arrayWithCapacity:count];

	for(NSUInteger i = 0; i < count; ++i)
	{
		[titles addObject:[self titleForDocument:_documents[i] withSetting:kSettingsTabTitleKey]];
		[paths addObject:_documents[i].path ?: @""];
		[identifiers addObject:_documents[i].identifier];
		[editedFlags addObject:@(_documents[i].isDocumentEdited)];
	}

	[self.tabBarModel reloadWithCount:count titles:titles paths:paths identifiers:identifiers editedFlags:editedFlags];
}

// ==============================
// = TabBarModel Context Menu   =
// ==============================

- (NSIndexSet*)tryObtainIndexSetFrom:(id)sender
{
	id res = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : sender;
	if([res isKindOfClass:[NSIndexSet class]])
		return res;
	else if(_documents.count)
		return [NSIndexSet indexSetWithIndex:self.selectedTabIndex];
	return nil;
}

- (void)takeNewTabIndexFrom:(id)sender
{
	if(NSIndexSet* indexSet = [self tryObtainIndexSetFrom:sender])
	{
		OakDocument* doc = [OakDocumentController.sharedInstance untitledDocument];
		[self insertDocuments:@[ doc ] atIndex:[indexSet firstIndex] selecting:doc andClosing:nil];
		[self openAndSelectDocument:doc activate:YES];
	}
}

- (void)takeTabsToCloseFrom:(id)sender
{
	if(NSIndexSet* indexSet = [self tryObtainIndexSetFrom:sender])
		[self closeTabsAtIndexes:indexSet askToSaveChanges:YES createDocumentIfEmpty:YES activate:YES];
}

- (void)takeTabsToTearOffFrom:(id)sender
{
	if(NSIndexSet* indexSet = [self tryObtainIndexSetFrom:sender])
	{
		NSArray<OakDocument*>* documents = [_documents objectsAtIndexes:indexSet];
		if(documents.count == 1)
		{
			DocumentWindowController* controller = [DocumentWindowController new];
			controller.documents = documents;
			if(path::is_child(to_s(documents.firstObject.path), to_s(self.projectPath)))
				controller.defaultProjectPath = self.projectPath;
			[controller openAndSelectDocument:documents.firstObject activate:YES];
			[controller showWindow:self];
			[self closeTabsAtIndexes:indexSet askToSaveChanges:NO createDocumentIfEmpty:YES activate:YES];
		}
	}
}

- (IBAction)toggleSticky:(id)sender
{
	if(NSIndexSet* indexSet = [self tryObtainIndexSetFrom:sender])
	{
		for(OakDocument* doc in [_documents objectsAtIndexes:indexSet])
			[self setDocument:doc sticky:![self isDocumentSticky:doc]];
	}
}

- (NSMenu*)tabBarModel:(id)model menuForIndex:(NSNumber*)indexNumber
{
	NSInteger tabIndex = indexNumber.integerValue;
	NSInteger total    = _documents.count;

	NSMutableIndexSet* newTabAtTab   = tabIndex == -1 ? [NSMutableIndexSet indexSetWithIndex:total] : [NSMutableIndexSet indexSetWithIndex:tabIndex + 1];
	NSMutableIndexSet* clickedTab    = tabIndex == -1 ? [NSMutableIndexSet indexSet] : [NSMutableIndexSet indexSetWithIndex:tabIndex];
	NSMutableIndexSet* otherTabs     = tabIndex == -1 ? [NSMutableIndexSet indexSet] : [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, total)];
	NSMutableIndexSet* rightSideTabs = tabIndex == -1 ? [NSMutableIndexSet indexSet] : [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, total)];
	NSMutableIndexSet* leftSideTabs  = tabIndex == -1 ? [NSMutableIndexSet indexSet] : [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, tabIndex)];

	if(tabIndex != -1)
	{
		[otherTabs removeIndex:tabIndex];
		[rightSideTabs removeIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, tabIndex + 1)]];
		// No need to modify leftSideTabs
	}

	for(NSUInteger i = 0; i < _documents.count; ++i)
	{
		if([self isDocumentSticky:_documents[i]])
		{
			[otherTabs removeIndex:i];
			[rightSideTabs removeIndex:i];
			[leftSideTabs removeIndex:i];
		}
	}

	SEL closeSingleTabSelector = tabIndex == _selectedTabIndex ? @selector(performCloseTab:) : @selector(takeTabsToCloseFrom:);
	MBMenu const items = {
		{ @"New Tab",                  @selector(takeNewTabIndexFrom:),    .representedObject = newTabAtTab   },
		{ @"Move Tab to New Window",   @selector(takeTabsToTearOffFrom:),  .representedObject = total > 1 ? clickedTab : [NSIndexSet indexSet] },
		{ /* -------- */ },
		{ @"Close Tab",                closeSingleTabSelector,                                                                           .representedObject = clickedTab    },
		{ @"Close Other Tabs",         @selector(takeTabsToCloseFrom:),                                                                  .representedObject = otherTabs     },
		{ @"Close Tabs to the Right",  @selector(takeTabsToCloseFrom:),                                                                  .representedObject = rightSideTabs },
		{ @"Close Tabs to the Left",   @selector(takeTabsToCloseFrom:),    .modifierFlags = NSEventModifierFlagOption, .alternate = YES, .representedObject = leftSideTabs  },
		{ /* -------- */ },
		{ @"Sticky",                   @selector(toggleSticky:),           .representedObject = clickedTab    },
	};

	NSMenu* menu = MBCreateMenu(items);
	for(NSMenuItem* item in menu.itemArray)
	{
		// In fullscreen mode the window’s delegate is ignored as a target for menu actions, therefore we have to manually set the target for these menu items (as a workaround for what I can only assume is an OS bug)

		if(!item.target && item.action)
			item.target = [NSApp targetForAction:item.action];
	}
	return menu;
}

// ============================
// = TabBarModel Delegate     =
// ============================

- (void)tabBarModel:(id)model didSelectIndex:(NSNumber*)indexNumber
{
	NSUInteger anIndex = indexNumber.unsignedIntegerValue;
	if(anIndex < _documents.count)
	{
		[self openAndSelectDocument:_documents[anIndex] activate:YES];
		self.selectedTabIndex = anIndex;
	}
}

- (void)tabBarModel:(id)model didDoubleClickIndex:(NSNumber*)indexNumber
{
	NSUInteger anIndex = indexNumber.unsignedIntegerValue;
	if(_documents.count > 1)
		[self takeTabsToTearOffFrom:[NSMutableIndexSet indexSetWithIndex:anIndex]];
}

- (void)tabBarModelDidDoubleClickBackground:(id)model
{
	[self takeNewTabIndexFrom:[NSIndexSet indexSetWithIndex:_documents.count]];
}

- (void)tabBarModel:(id)model didCloseIndex:(NSNumber*)indexNumber
{
	NSUInteger anIndex = indexNumber.unsignedIntegerValue;
	if(anIndex < _documents.count)
		[self closeTabsAtIndexes:[NSIndexSet indexSetWithIndex:anIndex] askToSaveChanges:YES createDocumentIfEmpty:YES activate:YES];
}

// ================
// = Tab Dragging =
// ================

- (BOOL)performDropOfTabItem:(NSUUID*)tabItemUUID atIndex:(NSUInteger)droppedIndex operation:(NSDragOperation)operation
{
	OakDocument* srcDocument = [OakDocumentController.sharedInstance findDocumentWithIdentifier:tabItemUUID];
	if(!srcDocument)
		return NO;

	[self insertDocuments:@[ srcDocument ] atIndex:droppedIndex selecting:self.selectedDocument andClosing:@[ srcDocument.identifier ]];

	if(operation == NSDragOperationMove)
	{
		// Find the source window controller that owns this document and close its tab
		for(DocumentWindowController* controller in SortedControllers())
		{
			if(controller == self)
				continue;

			NSUInteger dragIndex = [controller.documents indexOfObjectPassingTest:^BOOL(OakDocument* doc, NSUInteger idx, BOOL* stop){
				return [doc.identifier isEqual:tabItemUUID];
			}];

			if(dragIndex != NSNotFound)
			{
				BOOL wasSelected = dragIndex == controller.selectedTabIndex;

				if(controller.fileBrowserVisible || controller.documents.count > 1)
						[controller closeTabsAtIndexes:[NSIndexSet indexSetWithIndex:dragIndex] askToSaveChanges:NO createDocumentIfEmpty:YES activate:YES];
				else	[controller close];

				if(wasSelected)
				{
					self.selectedTabIndex = [self.documents indexOfObject:srcDocument];
					[self openAndSelectDocument:srcDocument activate:YES];
				}

				return YES;
			}
		}
	}

	return YES;
}

- (IBAction)selectNextTab:(id)sender            { self.selectedTabIndex = (_selectedTabIndex + 1) % _documents.count;                    [self openAndSelectDocument:_documents[_selectedTabIndex] activate:YES]; }
- (IBAction)selectPreviousTab:(id)sender        { self.selectedTabIndex = (_selectedTabIndex + _documents.count - 1) % _documents.count; [self openAndSelectDocument:_documents[_selectedTabIndex] activate:YES]; }
- (IBAction)takeSelectedTabIndexFrom:(id)sender { self.selectedTabIndex = [sender tag];                                                  [self openAndSelectDocument:_documents[_selectedTabIndex] activate:YES]; }

// ==================
// = OakFileBrowser =
// ==================

- (void)fileBrowserModel:(id)model openURLs:(NSArray*)someURLs
{
	NSMutableArray* items = [NSMutableArray array];
	for(NSURL* url in someURLs)
	{
		if([url isFileURL])
			[items addObject:@{ @"path": [url path] }];
	}
	[self openItems:items closingOtherTabs:OakIsAlternateKeyOrMouseEvent() activate:YES];
}

- (void)fileBrowserModel:(id)model closeURL:(NSURL*)anURL
{
	if(![anURL isFileURL])
		return;

	NSIndexSet* indexSet = [_documents indexesOfObjectsPassingTest:^BOOL(OakDocument* doc, NSUInteger idx, BOOL* stop){
		return [doc.path isEqualToString:anURL.path];
	}];
	[self closeTabsAtIndexes:indexSet askToSaveChanges:YES createDocumentIfEmpty:YES activate:NO];
}

- (void)setFileBrowserVisible:(BOOL)makeVisibleFlag
{
	if(_fileBrowserVisible != makeVisibleFlag)
	{
		_fileBrowserVisible = makeVisibleFlag;
		[self.splitModel setValue:@(makeVisibleFlag) forKey:@"sidebarVisible"];

		if(makeVisibleFlag)
		{
			id fileBrowser = [self.splitModel valueForKey:@"fileBrowser"];
			if(![fileBrowser valueForKey:@"path"])
			{
				[fileBrowser setupViewWithState:_fileBrowserHistory];
				if(!_fileBrowserHistory)
				{
					if(NSString* path = self.projectPath ?: self.defaultProjectPath)
						[fileBrowser goToURL:[NSURL fileURLWithPath:path]];
				}
			}

			if(self.autoRevealFile && self.selectedDocument.path)
				[self revealFileInProject:self];
		}
	}
	[[self class] scheduleSessionBackup:self];
}

- (IBAction)toggleFileBrowser:(id)sender    { self.fileBrowserVisible = !self.fileBrowserVisible; }

- (id)fileBrowser                           { return [self.splitModel valueForKey:@"fileBrowser"]; }
- (id)fileBrowserHistory                    { return [self.fileBrowser valueForKey:@"sessionState"] ?: _fileBrowserHistory; }
- (CGFloat)fileBrowserWidth                 { return 0; /* sidebar width now managed by NavigationSplitView */ }
- (void)setFileBrowserWidth:(CGFloat)aWidth { /* no-op — sidebar width managed by NavigationSplitView */ }

- (IBAction)newFolder:(id)sender            { if(self.fileBrowser) [self.fileBrowser createFolder:sender]; }
- (IBAction)reload:(id)sender               { if(self.fileBrowser) [self.fileBrowser reload:sender];      }
- (IBAction)deselectAll:(id)sender          { if(self.fileBrowser) [self.fileBrowser deselectAll:sender]; }

- (IBAction)revealFileInProject:(id)sender  { if(self.selectedDocument) { self.fileBrowserVisible = YES; [self.fileBrowser selectURL:[NSURL fileURLWithPath:self.selectedDocument.path] withParentURL:self.projectPath ? [NSURL fileURLWithPath:self.projectPath] : nil]; } }
- (IBAction)goToProjectFolder:(id)sender    { self.fileBrowserVisible = YES; [self.fileBrowser goToURL:[NSURL fileURLWithPath:self.projectPath]]; }

- (IBAction)goBack:(id)sender               { self.fileBrowserVisible = YES; [self.fileBrowser goBack:sender];               }
- (IBAction)goForward:(id)sender            { self.fileBrowserVisible = YES; [self.fileBrowser goForward:sender];            }
- (IBAction)goToParentFolder:(id)sender     { self.fileBrowserVisible = YES; [self.fileBrowser goToParentFolder:sender];     }

- (IBAction)goToComputer:(id)sender         { self.fileBrowserVisible = YES; [self.fileBrowser goToComputer:sender];         }
- (IBAction)goToHome:(id)sender             { self.fileBrowserVisible = YES; [self.fileBrowser goToHome:sender];             }
- (IBAction)goToDesktop:(id)sender          { self.fileBrowserVisible = YES; [self.fileBrowser goToDesktop:sender];          }
- (IBAction)goToFavorites:(id)sender        { self.fileBrowserVisible = YES; [self.fileBrowser goToFavorites:sender];        }
- (IBAction)orderFrontGoToFolder:(id)sender { self.fileBrowserVisible = YES; [self.fileBrowser orderFrontGoToFolder:sender]; }

// =============================
// = Opening Auxiliary Windows =
// =============================

- (void)positionWindow:(NSWindow*)aWindow
{
	if(![aWindow isVisible])
	{
		[aWindow layoutIfNeeded];
		NSRect frame  = [aWindow frame];
		NSRect parent = [self.window convertRectToScreen:[_textView convertRect:[_textView visibleRect] toView:nil]];

		frame.origin.x = NSMinX(parent) + round((NSWidth(parent)  - NSWidth(frame))  * 1 / 4);
		frame.origin.y = NSMinY(parent) + round((NSHeight(parent) - NSHeight(frame)) * 3 / 4);
		[aWindow setFrame:frame display:NO];
	}
}

- (NSUUID*)selectedDocumentUUID
{
	return self.selectedDocument.identifier;
}

- (Find*)prepareAndReturnFindPanel
{
	Find* find = Find.sharedInstance;
	find.documentIdentifier = self.selectedDocumentUUID;
	find.projectFolder      = self.projectPath ?: self.untitledSavePath ?: NSHomeDirectory();
	find.delegate           = self;

	NSArray* items;
	if(self.fileBrowserVisible)
	{
		items = [[self.fileBrowser valueForKey:@"selectedFileURLs"] valueForKey:@"path"];
		if(items.count == 0)
			items = @[ [self.fileBrowser valueForKey:@"path"] ?: find.projectFolder ];
	}
	find.fileBrowserItems = items.count ? items : nil;

	return find;
}

- (IBAction)orderFrontFindPanel:(id)sender
{
	Find* find              = Find.sharedInstance;
	BOOL didOwnDialog       = find.delegate == self;
	[self prepareAndReturnFindPanel];

	NSInteger mode = [sender respondsToSelector:@selector(tag)] ? [sender tag] : FFSearchTargetDocument;
	if(mode == FFSearchTargetDocument && ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsAlwaysFindInDocument] && [self.window isKeyWindow] && self.textView.hasMultiLineSelection)
		mode = FFSearchTargetSelection;

	switch(mode)
	{
		case FFSearchTargetDocument:  find.searchTarget = FFSearchTargetDocument;  break;
		case FFSearchTargetSelection: find.searchTarget = FFSearchTargetSelection; break;
		case FFSearchTargetOther:     return [find showFolderSelectionPanel:self]; break;

		case FFSearchTargetProject:
		{
			// Only reset search target if the dialog is not already showing potential search results from “Other…”
			if(!find.isVisible || !didOwnDialog || find.searchTarget == FFSearchTargetDocument || find.searchTarget == FFSearchTargetSelection)
			{
				BOOL fileBrowserHasFocus = [self.window.firstResponder respondsToSelector:@selector(isDescendantOf:)] && [(NSView*)self.window.firstResponder isDescendantOf:[self.fileBrowser valueForKey:@"hostingView"]];
				find.searchTarget = fileBrowserHasFocus ? FFSearchTargetFileBrowserItems : FFSearchTargetProject;
			}
		}
		break;
	}
	[find showWindow:self];
}

- (IBAction)orderFrontFindPanelForFileBrowser:(id)sender
{
	Find* find = [self prepareAndReturnFindPanel];
	find.searchTarget = FFSearchTargetFileBrowserItems;
	[find showWindow:self];
}

- (IBAction)orderFrontFindPanelForProject:(id)sender
{
	Find* find = [self prepareAndReturnFindPanel];
	find.searchTarget = FFSearchTargetProject;
	[find showWindow:self];
}

- (IBAction)orderFrontRunCommandWindow:(id)sender
{
	OakRunCommandWindowController* runCommand = OakRunCommandWindowController.sharedInstance;
	[self positionWindow:runCommand.window];
	[runCommand showWindow:nil];
}

// ================
// = FindDelegate =
// ================

- (void)selectRange:(text::range_t const&)range inDocument:(OakDocument*)aDocument
{
	if(range != text::range_t::undefined)
		aDocument.selection = to_ns(range);
	[self openItems:@[ @{ @"identifier": aDocument.identifier.UUIDString } ] closingOtherTabs:NO activate:YES];
}

// ==================
// = OakFileChooser =
// ==================

- (IBAction)goToFile:(id)sender
{
	FileChooser* fc = FileChooser.sharedInstance;

	fc.path            = nil; // Disable potential work when updating filterString/currentDocument
	fc.filterString    = @"";
	fc.currentDocument = self.selectedDocumentUUID;
	fc.target          = self;
	fc.action          = @selector(fileChooserDidSelectItems:);
	fc.path            = self.projectPath ?: self.untitledSavePath ?: NSHomeDirectory();

	if(OakPasteboardEntry* entry = [OakPasteboard.findPasteboard current])
	{
		std::string str = to_s(entry.string);
		if(regexp::search("\\A.*?(\\.|/).*?:\\d+\\z", str))
		{
			if([entry.string hasPrefix:fc.path])
					fc.filterString = [NSString stringWithCxxString:path::relative_to(str, to_s(fc.path))];
			else	fc.filterString = entry.string;
		}
	}

	[fc showWindowRelativeToFrame:[self.window convertRectToScreen:[self.textView convertRect:[self.textView visibleRect] toView:nil]]];
}

- (void)fileChooserDidSelectItems:(FileChooser*)sender
{
	ASSERT([sender respondsToSelector:@selector(selectedItems)]);
	[self openItems:[sender selectedItems] closingOtherTabs:OakIsAlternateKeyOrMouseEvent() activate:YES];
}

// ===========
// = Methods =
// ===========

- (NSString*)titleForDocument:(OakDocument*)document withSetting:(std::string const&)setting
{
	auto map = document.variables;
	if(self.projectPath)
		map["projectDirectory"] = to_s(self.projectPath);

	NSString* docDirectory = document.path ? [document.path stringByDeletingLastPathComponent] : self.untitledSavePath;
	settings_t const settings = settings_for_path(to_s(document.virtualPath ?: document.path), to_s(document.fileType) + " " + to_s(self.scopeAttributes), to_s(docDirectory), map);
	return to_ns(settings.get(setting, to_s(document.displayName)));
}

- (NSString*)untitledSavePath
{
	NSString* res;
	if(self.fileBrowserVisible)
	{
		NSArray* selected = [self.fileBrowser valueForKey:@"selectedFileURLs"];
		res = selected.count == 1 ? [[self.fileBrowser valueForKey:@"directoryURLForNewItems"] path] : [self.fileBrowser valueForKey:@"path"];
	}
	return res ?: self.projectPath ?: [self.selectedDocument.path stringByDeletingLastPathComponent];
}

- (BOOL)treatAsProjectWindow
{
	return self.projectPath && (self.fileBrowserVisible || _documents.count > 1);
}

- (NSPoint)positionForWindowUnderCaret
{
	return [self.textView positionForWindowUnderCaret];
}

- (void)performBundleItem:(bundles::item_ptr)anItem
{
	if(anItem->kind() == bundles::kItemTypeTheme)
	{
		self.documentView.textView.themeUUID = [NSString stringWithCxxString:anItem->uuid()];
	}
	else
	{
		[self showWindow:self];
		[self makeTextViewFirstResponder:self];
		[self.textView performBundleItem:anItem];
	}
}

- (IBAction)goToRelatedFile:(id)sender
{
	if(!self.selectedDocument.path)
		return (void)NSBeep();

	std::string const documentPath = to_s(self.selectedDocument.path);
	std::string const documentDir  = path::parent(documentPath);
	std::string const documentName = path::name(documentPath);
	std::string const documentBase = path::strip_extensions(documentName);

	std::set<std::string> candidates = { documentName };
	for(OakDocument* document in _documents)
	{
		if(documentDir == path::parent(to_s(document.path)) && documentBase == path::strip_extensions(path::name(to_s(document.path))))
			candidates.insert(path::name(to_s(document.path)));
	}

	auto map = self.selectedDocument.variables;
	if(self.projectPath)
		map["projectDirectory"] = to_s(self.projectPath);

	settings_t const settings = settings_for_path(to_s(self.selectedDocument.virtualPath ?: self.selectedDocument.path), to_s(self.selectedDocument.fileType) + " " + to_s(self.scopeAttributes), path::parent(documentPath), map);
	std::string const customCandidate = settings.get(kSettingsRelatedFilePathKey, NULL_STR);

	if(customCandidate != NULL_STR && customCandidate != documentPath && ([_documents indexOfObjectPassingTest:^BOOL(OakDocument* doc, NSUInteger, BOOL*){ return customCandidate == to_s(doc.path); }] != NSNotFound || path::exists(customCandidate)))
		return [self openItems:@[ @{ @"path": [NSString stringWithCxxString:customCandidate] } ] closingOtherTabs:NO activate:YES];

	for(auto const& entry : path::entries(documentDir))
	{
		std::string const name = entry->d_name;
		if(entry->d_type == DT_REG && documentBase == path::strip_extensions(name) && path::extensions(name) != "")
		{
			std::string const content = path::content(path::join(documentDir, name));
			if(utf8::is_valid(content.data(), content.data() + content.size()))
				candidates.insert(name);
		}
	}

	path::glob_t const excludeGlob(settings.get(kSettingsExcludeKey, ""));
	path::glob_t const binaryGlob(settings.get(kSettingsBinaryKey, ""));

	std::vector<std::string> v;
	for(auto const& name : candidates)
	{
		if(name == documentName || !binaryGlob.does_match(name) && !excludeGlob.does_match(name))
			v.push_back(name);
	}

	if(v.size() == 1)
	{
		if(customCandidate == NULL_STR || customCandidate == documentPath)
			return (void)NSBeep();
		v.push_back(customCandidate);
	}

	std::vector<std::string>::const_iterator it = std::find(v.begin(), v.end(), documentName);
	ASSERT(it != v.end());

	NSString* path = [NSString stringWithCxxString:path::join(documentDir, v[((it - v.begin()) + 1) % v.size()])];
	[self openItems:@[ @{ @"path": path } ] closingOtherTabs:NO activate:YES];
}

// ==========================
// = Show Tab Menu Delegate =
// ==========================

- (void)updateShowTabMenu:(NSMenu*)aMenu
{
	if(![self.window isKeyWindow])
	{
		[aMenu addItemWithTitle:@"No Tabs" action:@selector(nop:) keyEquivalent:@""];
		return;
	}

	int i = 0;
	for(OakDocument* document in _documents)
	{
		NSMenuItem* item = [aMenu addItemWithTitle:document.displayName action:@selector(takeSelectedTabIndexFrom:) keyEquivalent:i < 8 ? [NSString stringWithFormat:@"%c", '1' + i] : @""];
		item.tag     = i;
		item.toolTip = [document.path stringByAbbreviatingWithTildeInPath];
		if(aMenu.propertiesToUpdate & NSMenuPropertyItemImage)
		{
			item.image = [document.icon copy];
			item.image.size = NSMakeSize(16, 16);
		}
		if(i == _selectedTabIndex)
			item.state = NSControlStateValueOn;
		else if(document.isDocumentEdited)
			item.modifiedState = YES;
		++i;
	}

	if(i == 0)
	{
		[aMenu addItemWithTitle:@"No Tabs Open" action:@selector(nop:) keyEquivalent:@""];
	}
	else
	{
		[aMenu addItem:[NSMenuItem separatorItem]];

		NSMenuItem* item = [aMenu addItemWithTitle:@"Last Tab" action:@selector(takeSelectedTabIndexFrom:) keyEquivalent:@"9"];
		item.tag     = _documents.count-1;
		item.toolTip = _documents.lastObject.displayName;
	}
}

// ====================
// = NSMenuValidation =
// ====================

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem
{
	static std::set<SEL> const delegateToFileBrowser = {
		@selector(newFolder:), @selector(goBack:), @selector(goForward:),
		@selector(reload:), @selector(deselectAll:)
	};

	BOOL active = YES;
	if([menuItem action] == @selector(toggleFileBrowser:))
		[menuItem setTitle:self.fileBrowserVisible ? @"Hide File Browser" : @"Show File Browser"];
	else if([menuItem action] == @selector(newDocumentInDirectory:))
	{
		NSURL* dirURL = [self.fileBrowser valueForKey:@"directoryURLForNewItems"];
		active = self.fileBrowserVisible && dirURL;
		[menuItem setDynamicTitle:active ? [NSString stringWithFormat:@"New File in “%@”", [NSFileManager.defaultManager displayNameAtPath:dirURL.path]] : @"New File"];
	}
	else if(delegateToFileBrowser.find([menuItem action]) != delegateToFileBrowser.end())
		active = self.fileBrowserVisible && [self.fileBrowser validateMenuItem:menuItem];
	else if([menuItem action] == @selector(moveDocumentToNewWindow:))
		active = _documents.count > 1;
	else if([menuItem action] == @selector(selectNextTab:) || [menuItem action] == @selector(selectPreviousTab:))
		active = _documents.count > 1;
	else if([menuItem action] == @selector(revealFileInProject:) || [menuItem action] == @selector(revealFileInProjectByExpandingAncestors:))
	{
		active = self.selectedDocument.path != nil;
		[menuItem setDynamicTitle:active ? [NSString stringWithFormat:@"Select “%@”", self.selectedDocument.displayName] : @"Select Document"];
	}
	else if([menuItem action] == @selector(goToProjectFolder:))
		active = self.projectPath != nil;
	else if([menuItem action] == @selector(goToParentFolder:))
		active = [self.window firstResponder] != self.textView;
	else if([menuItem action] == @selector(moveFocus:))
		[menuItem setTitle:self.window.firstResponder == self.textView ? @"Move Focus to File Browser" : @"Move Focus to Document"];
	else if([menuItem action] == @selector(takeProjectPathFrom:))
		[menuItem setState:[self.defaultProjectPath isEqualToString:[menuItem representedObject]] ? NSControlStateValueOn : NSControlStateValueOff];
	else if([menuItem action] == @selector(performCloseOtherTabsXYZ:))
		active = _documents.count > 1;
	else if([menuItem action] == @selector(performCloseTabsToTheRight:))
		active = _selectedTabIndex + 1 < _documents.count;
	else if([menuItem action] == @selector(performCloseTabsToTheLeft:))
		active = _selectedTabIndex > 0;
	else if([menuItem action] == @selector(performBundleItemWithUUIDStringFrom:))
		active = [_textView validateMenuItem:menuItem];

	SEL tabBarActions[] = { @selector(performCloseTab:), @selector(takeNewTabIndexFrom::), @selector(takeTabsToCloseFrom:), @selector(takeTabsToTearOffFrom:), @selector(toggleSticky:) };
	if(oak::contains(std::begin(tabBarActions), std::end(tabBarActions), [menuItem action]))
	{
		if(NSIndexSet* indexSet = [self tryObtainIndexSetFrom:menuItem])
		{
			active = [indexSet count] != 0;
			if(active && [menuItem action] == @selector(toggleSticky:))
				[menuItem setState:[self isDocumentSticky:_documents[indexSet.firstIndex]] ? NSControlStateValueOn : NSControlStateValueOff];
		}
	}

	return active;
}

// =============
// = Touch Bar =
// =============

static NSTouchBarItemIdentifier kTouchBarCustomizationIdentifier = @"com.macromates.TextMate.touch-bar.customization-identifier";
static NSTouchBarItemIdentifier kTouchBarTabNavigationIdentifier = @"com.macromates.TextMate.touch-bar.tab-navigation";
static NSTouchBarItemIdentifier kTouchBarNewTabItemIdentifier    = @"com.macromates.TextMate.touch-bar.new-tab";
static NSTouchBarItemIdentifier kTouchBarQuickOpenItemIdentifier = @"com.macromates.TextMate.touch-bar.quick-open";
static NSTouchBarItemIdentifier kTouchBarFindItemIdentifier      = @"com.macromates.TextMate.touch-bar.find";
static NSTouchBarItemIdentifier kTouchBarFavoritesItemIdentifier = @"com.macromates.TextMate.touch-bar.favorites";

- (NSTouchBar*)makeTouchBar
{
	NSTouchBar* bar = [[NSTouchBar alloc] init];
	bar.delegate = self;
	bar.defaultItemIdentifiers = @[
		NSTouchBarItemIdentifierOtherItemsProxy,
		kTouchBarTabNavigationIdentifier,
		kTouchBarNewTabItemIdentifier,
		kTouchBarQuickOpenItemIdentifier,
		NSTouchBarItemIdentifierFlexibleSpace,
		kTouchBarFindItemIdentifier,
		kTouchBarFavoritesItemIdentifier,
	];
	bar.customizationIdentifier = kTouchBarCustomizationIdentifier;
	bar.customizationAllowedItemIdentifiers = @[
		kTouchBarTabNavigationIdentifier,
		kTouchBarNewTabItemIdentifier,
		kTouchBarQuickOpenItemIdentifier,
		NSTouchBarItemIdentifierFlexibleSpace,
		kTouchBarFindItemIdentifier,
		kTouchBarFavoritesItemIdentifier,
	];
	return bar;
}

- (void)updateTouchBarButtons
{
	_previousNextTouchBarControl.enabled = _documents.count > 1;
}

- (NSTouchBarItem*)touchBar:(NSTouchBar*)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
	NSCustomTouchBarItem* res;
	if([identifier isEqualToString:kTouchBarTabNavigationIdentifier])
	{
		if(!_previousNextTouchBarControl)
		{
			_previousNextTouchBarControl = [NSSegmentedControl segmentedControlWithImages:@[ [NSImage imageNamed:NSImageNameTouchBarGoBackTemplate], [NSImage imageNamed:NSImageNameTouchBarGoForwardTemplate] ] trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(didClickPreviousNextTouchBarControl:)];
			_previousNextTouchBarControl.segmentStyle = NSSegmentStyleSeparated;
			_previousNextTouchBarControl.enabled      = _documents.count > 1;
		}

		res = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
		res.view = _previousNextTouchBarControl;
		res.customizationLabel = @"Back/Forward Tab";
	}
	else if([identifier isEqualToString:kTouchBarNewTabItemIdentifier])
	{
		NSImage* newTabImage = [NSImage imageNamed:@"TouchBarNewTabTemplate"];
		newTabImage.accessibilityDescription = @"new tab";
		res = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
		res.view = [NSButton buttonWithImage:newTabImage target:self action:@selector(newDocumentInTab:)];
		res.visibilityPriority = NSTouchBarItemPriorityNormal;
		res.customizationLabel = @"New Tab";
	}
	else if([identifier isEqualToString:kTouchBarQuickOpenItemIdentifier])
	{
		NSImage* quickOpenImage = [NSImage imageNamed:@"TouchBarQuickOpenTemplate"];
		quickOpenImage.accessibilityDescription = @"quick open";
		res = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
		res.view = [NSButton buttonWithImage:quickOpenImage target:self action:@selector(goToFile:)];
		res.visibilityPriority = NSTouchBarItemPriorityNormal;
		res.customizationLabel = @"Quick Open";
	}
	else if([identifier isEqualToString:kTouchBarFindItemIdentifier])
	{
		NSButton* findInProjectButton = [NSButton buttonWithImage:[NSImage imageNamed:NSImageNameTouchBarSearchTemplate] target:self action:@selector(orderFrontFindPanel:)];
		findInProjectButton.tag = FFSearchTargetProject;
		res = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
		res.view = findInProjectButton;
		res.visibilityPriority = NSTouchBarItemPriorityNormal;
		res.customizationLabel = @"Find";
	}
	else if([identifier isEqualToString:kTouchBarFavoritesItemIdentifier])
	{
		NSImage* favoritesProjectsImage = [NSImage imageNamed:NSImageNameTouchBarBookmarksTemplate];
		favoritesProjectsImage.accessibilityDescription = @"favorite projects";
		res = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
		res.view = [NSButton buttonWithImage:favoritesProjectsImage target:nil action:@selector(openFavorites:)];
		res.visibilityPriority = NSTouchBarItemPriorityNormal;
		res.customizationLabel = @"Favorite Projects";
	}
	return res;
}

- (void)didClickPreviousNextTouchBarControl:(NSSegmentedControl*)control
{
	switch(control.selectedSegment)
	{
		case 0: [self selectPreviousTab:control]; break;
		case 1: [self selectNextTab:control];     break;
	}
}

// ======================
// = Session Management =
// ======================

+ (void)initialize
{
	static dispatch_once_t onceToken = 0;
	dispatch_once(&onceToken, ^{
		for(NSString* notification in @[ NSWindowDidBecomeKeyNotification, NSWindowDidDeminiaturizeNotification, NSWindowDidExposeNotification, NSWindowDidMiniaturizeNotification, NSWindowDidMoveNotification, NSWindowDidResizeNotification, NSWindowWillCloseNotification ])
			[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleSessionBackup:) name:notification object:nil];
	});
}

+ (void)backupSessionFiredTimer:(NSTimer*)aTimer
{
	[self saveSessionIncludingUntitledDocuments:YES];
}

+ (void)scheduleSessionBackup:(id)sender
{
	static NSTimer* saveTimer;
	[saveTimer invalidate];
	saveTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(backupSessionFiredTimer:) userInfo:nil repeats:NO];
}

+ (NSString*)sessionPath
{
	static NSString* const res = [NSString stringWithCxxString:path::join(oak::application_t::support("Session"), "Info.plist")];
	return res;
}

static NSUInteger DisableSessionSavingCount = 0;

+ (void)disableSessionSave { ++DisableSessionSavingCount; }
+ (void)enableSessionSave  { --DisableSessionSavingCount; }

+ (BOOL)restoreSession
{
	BOOL res = NO;
	++DisableSessionSavingCount;

	NSWindow* keyWindow;

	NSDictionary* session = [NSDictionary dictionaryWithContentsOfFile:[self sessionPath]];
	for(NSDictionary* project in session[@"projects"])
	{
		DocumentWindowController* controller = [DocumentWindowController new];
		[controller setupControllerForProject:project skipMissingFiles:NO];
		if(controller.documents.count == 0)
			continue;

		if(NSString* windowFrame = project[@"windowFrame"])
		{
			if([windowFrame hasPrefix:@"{"]) // Legacy NSRect
					[controller.window setFrame:NSRectFromString(windowFrame) display:NO];
			else	[controller.window setFrameFromString:windowFrame];
		}

		if([project[@"miniaturized"] boolValue])
		{
			[controller.window miniaturize:nil];
		}
		else
		{
			if([project[@"fullScreen"] boolValue])
				[controller.window toggleFullScreen:self];
			else if([project[@"zoomed"] boolValue])
				[controller.window zoom:self];

			[controller.window orderFront:self];
			keyWindow = controller.window;
		}

		res = YES;
	}

	[keyWindow makeKeyWindow];

	--DisableSessionSavingCount;
	return res;
}

- (void)setupControllerForProject:(NSDictionary*)project skipMissingFiles:(BOOL)skipMissing
{
	if(NSString* fileBrowserWidth = project[@"fileBrowserWidth"])
		self.fileBrowserWidth = [fileBrowserWidth floatValue];
	self.defaultProjectPath = project[@"projectPath"];
	self.projectPath        = project[@"projectPath"];
	self.fileBrowserHistory = project[@"archivedFileBrowserState"] ?: project[@"fileBrowserState"];
	self.fileBrowserVisible = [project[@"fileBrowserVisible"] boolValue];

	NSMutableArray<OakDocument*>* documents = [NSMutableArray array];
	NSInteger selectedTabIndex = 0;

	for(NSDictionary* info in project[@"documents"])
	{
		OakDocument* doc;
		NSString* identifier = info[@"identifier"];
		if(!identifier || !(doc = [OakDocument documentWithIdentifier:[[NSUUID alloc] initWithUUIDString:identifier]]))
		{
			NSString* path = info[@"path"];
			if(path && skipMissing && access([path fileSystemRepresentation], F_OK) != 0)
				continue;

			doc = [OakDocumentController.sharedInstance documentWithPath:path];
			if(NSString* fileType = info[@"fileType"])
				doc.fileType = fileType;
			if(NSString* displayName = info[@"displayName"])
				doc.customName = displayName;
			if([info[@"sticky"] boolValue])
				[self setDocument:doc sticky:YES];
		}

		if(!doc.path) // Add untitled documents to LRU-list
			[OakDocumentController.sharedInstance didTouchDocument:doc];

		doc.recentTrackingDisabled = YES;
		[documents addObject:doc];

		if([info[@"selected"] boolValue])
			selectedTabIndex = documents.count - 1;
	}

	if(documents.count == 0)
		[documents addObject:[OakDocumentController.sharedInstance untitledDocument]];

	self.documents        = documents;
	self.selectedTabIndex = selectedTabIndex;

	[self openAndSelectDocument:documents[selectedTabIndex] activate:YES];
}

- (NSDictionary*)sessionInfoIncludingUntitledDocuments:(BOOL)includeUntitled
{
	NSMutableDictionary* res = [NSMutableDictionary dictionary];

	if(NSString* projectPath = self.defaultProjectPath)
		res[@"projectPath"] = projectPath;
	if(id history = self.fileBrowserHistory)
		res[@"archivedFileBrowserState"] = history;

	if(([self.window styleMask] & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen)
		res[@"fullScreen"] = @YES;
	else if(self.window.isZoomed)
		res[@"zoomed"] = @YES;
	else
		res[@"windowFrame"] = [self.window stringWithSavedFrame];

	res[@"miniaturized"]       = @([self.window isMiniaturized]);
	res[@"fileBrowserVisible"] = @(self.fileBrowserVisible);
	res[@"fileBrowserWidth"]   = @(self.fileBrowserWidth);

	NSMutableArray* docs = [NSMutableArray array];
	for(OakDocument* document in _documents)
	{
		if(!includeUntitled && (!document.path || !path::exists(to_s(document.path))))
			continue;

		NSMutableDictionary* doc = [NSMutableDictionary dictionary];
		if(document.isDocumentEdited || !document.path)
		{
			doc[@"identifier"] = document.identifier.UUIDString;
			if(document.isLoaded)
				[document saveBackup:self];
		}
		if(document.path)
			doc[@"path"] = document.path;
		if(document.fileType) // TODO Only necessary when document.isBufferEmpty
			doc[@"fileType"] = document.fileType;
		if(document.displayName)
			doc[@"displayName"] = document.displayName;
		if([document isEqual:self.selectedDocument])
			doc[@"selected"] = @YES;
		if([self isDocumentSticky:document])
			doc[@"sticky"] = @YES;
		[docs addObject:doc];
	}
	res[@"documents"] = docs;
	res[@"lastRecentlyUsed"] = [NSDate date];
	return res;
}

+ (BOOL)saveSessionIncludingUntitledDocuments:(BOOL)includeUntitled
{
	if(DisableSessionSavingCount)
		return NO;

	NSArray* controllers = SortedControllers();
	if(controllers.count == 1)
	{
		DocumentWindowController* controller = controllers.firstObject;
		if(!controller.projectPath && !controller.fileBrowserVisible && controller.documents.count == 1 && is_disposable(controller.selectedDocument))
			controllers = nil;
	}

	NSMutableArray* projects = [NSMutableArray array];
	for(DocumentWindowController* controller in [controllers reverseObjectEnumerator])
		[projects addObject:[controller sessionInfoIncludingUntitledDocuments:includeUntitled]];

	NSDictionary* session = @{ @"projects": projects };
	return [session writeToFile:[self sessionPath] atomically:YES];
}

// ==========
// = Legacy =
// ==========

- (std::map<std::string, std::string>)variables
{
	std::map<std::string, std::string> res;
	if(self.fileBrowser)
	{
		NSDictionary<NSString*, NSString*>* vars = [self.fileBrowser valueForKey:@"environmentVariables"];
		for(NSString* key in vars)
			res[to_s(key)] = to_s(vars[key]);
	}

	if(NSString* projectDir = self.projectPath)
	{
		res["TM_PROJECT_DIRECTORY"] = [projectDir fileSystemRepresentation];
		res["TM_PROJECT_UUID"]      = to_s(self.identifier);
	}

	return res;
}

+ (instancetype)controllerForDocument:(OakDocument*)aDocument
{
	if(!aDocument)
		return nil;

	for(DocumentWindowController* delegate in SortedControllers())
	{
		if(delegate.fileBrowserVisible && aDocument.path && [aDocument.path hasPrefix:delegate.projectPath])
			return delegate;

		for(OakDocument* document in delegate.documents)
		{
			if([aDocument isEqual:document])
				return delegate;
		}
	}
	return nil;
}

- (void)bringToFront
{
	[self showWindow:nil];
	if(NSApp.isActive)
	{
		// If we call ‘mate -w’ in quick succession there is a chance that we have a pending “re-activate the terminal app” when this code is executed, which will make ‘isActive’ return ‘YES’ but shortly after, our application will become inactive. For this reason, we monitor the NSApplicationDidResignActiveNotification for 200 ms and re-activate TextMate if we see the notification.

		__weak __block id token = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidResignActiveNotification object:NSApp queue:nil usingBlock:^(NSNotification*){
			[NSNotificationCenter.defaultCenter removeObserver:token];
			[NSApp activateIgnoringOtherApps:YES];
		}];

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 5), dispatch_get_main_queue(), ^{
			[NSNotificationCenter.defaultCenter removeObserver:token];
		});
	}
	else
	{
		__weak __block id token = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidBecomeActiveNotification object:NSApp queue:nil usingBlock:^(NSNotification*){
			// If our window is not on the active desktop but another one is, the system gives focus to the wrong window.
			[self showWindow:nil];
			[NSNotificationCenter.defaultCenter removeObserver:token];
		}];
		[NSApp activateIgnoringOtherApps:YES];
	}
}

// MARK: - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
	return @[ NSToolbarToggleSidebarItemIdentifier, NSToolbarSidebarTrackingSeparatorItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier ];
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
	return @[ NSToolbarToggleSidebarItemIdentifier, NSToolbarSidebarTrackingSeparatorItemIdentifier ];
}

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag
{
	if([identifier isEqualToString:NSToolbarToggleSidebarItemIdentifier])
	{
		NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
		item.target = self;
		item.action = @selector(toggleFileBrowser:);
		return item;
	}
	return nil;
}
@end

@implementation OakDocumentController (OakDocumentWindowControllerCategory)
- (DocumentWindowController*)findOrCreateController:(NSArray<OakDocument*>*)documents project:(NSUUID*)projectUUID
{
	ASSERT(documents.count);

	// =========================================
	// = Return requested window, if it exists =
	// =========================================

	if(projectUUID)
	{
		if(DocumentWindowController* res = AllControllers()[projectUUID])
			return res;

		if([projectUUID.UUIDString isEqualToString:@"00000000-0000-0000-0000-000000000000"])
			return [DocumentWindowController new];
	}

	// =========================================
	// = Find window with one of our documents =
	// =========================================

	NSSet<NSUUID*>* uuids = [NSSet setWithArray:[documents valueForKey:@"identifier"]];

	for(DocumentWindowController* candidate in SortedControllers())
	{
		for(OakDocument* document in candidate.documents)
		{
			if([uuids containsObject:document.identifier])
				return candidate;
		}
	}

	// ================================================================
	// = Find window with project folder closest to document’s parent =
	// ================================================================

	NSArray<OakDocument*>* documentsWithPath = [documents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"path != NULL"]];
	NSSet<NSString*>* parents = [NSSet setWithArray:[documentsWithPath valueForKeyPath:@"path.stringByDeletingLastPathComponent"]];

	std::map<size_t, DocumentWindowController*> candidates;
	for(DocumentWindowController* candidate in SortedControllers())
	{
		if(candidate.projectPath)
		{
			std::string const projectPath = to_s(candidate.projectPath);
			for(NSString* parent in parents)
			{
				if(path::is_child(to_s(parent), projectPath))
					candidates.emplace(parent.length - candidate.projectPath.length, candidate);
			}
		}
	}

	if(!candidates.empty())
		return candidates.begin()->second;

	// ==============================================
	// = Use frontmost window if a “scratch” window =
	// ==============================================

	if(DocumentWindowController* candidate = [SortedControllers() firstObject])
	{
		if(!candidate.fileBrowserVisible && candidate.documents.count == 1 && is_disposable(candidate.selectedDocument))
			return candidate;
	}

	// ===================================
	// = Give up and create a new window =
	// ===================================

	DocumentWindowController* res = [DocumentWindowController new];

	if(parents.count) // setup project folder for new window
	{
		NSArray* rankedParents = [parents.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString* lhs, NSString* rhs){
			return lhs.length < rhs.length ? NSOrderedAscending : (lhs.length > rhs.length ? NSOrderedDescending : NSOrderedSame);
		}];
		res.defaultProjectPath = rankedParents.firstObject;
	}

	return res;
}

- (DocumentWindowController*)controllerWithDocuments:(NSArray<OakDocument*>*)documents project:(NSUUID*)projectUUID
{
	DocumentWindowController* controller = [self findOrCreateController:documents project:projectUUID];
	BOOL hasDisposable = controller.disposableDocument ? YES : NO;
	OakDocument* documentToSelect = controller.documents.count <= (hasDisposable ? 1 : 0) ? documents.firstObject : documents.lastObject;
	[controller insertDocuments:documents atIndex:controller.selectedTabIndex + 1 selecting:documentToSelect andClosing:hasDisposable ? @[ controller.disposableDocument ] : nil];
	return controller;
}

- (void)showDocument:(OakDocument*)aDocument andSelect:(text::range_t const&)range inProject:(NSUUID*)identifier bringToFront:(BOOL)bringToFront
{
	if(range != text::range_t::undefined)
		aDocument.selection = to_ns(range);

	DocumentWindowController* controller = [self controllerWithDocuments:@[ aDocument ] project:identifier];
	if(bringToFront)
		[controller bringToFront];
	else if(![controller.window isVisible])
		[controller.window orderWindow:NSWindowBelow relativeTo:[([NSApp keyWindow] ?: [NSApp mainWindow]) windowNumber]];
	[controller openAndSelectDocument:aDocument activate:YES];
}

- (void)showDocuments:(NSArray<OakDocument*>*)someDocument
{
	if(someDocument.count == 0)
		return;

	NSUUID* projectUUID = nil;
	if(NSEvent.modifierFlags & NSEventModifierFlagOption)
		projectUUID = [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];

	DocumentWindowController* controller = [self controllerWithDocuments:someDocument project:projectUUID];
	[controller bringToFront];
	[controller openAndSelectDocument:controller.documents[controller.selectedTabIndex] activate:YES];

	// If we launch TextMate with a document to open and there are also session to restore
	// then the document window ends up behind all the other windows, despite being active
	// and the last window ordered front. Problem only seen on MAC_OS_X_VERSION_10_11.
	// Running the next line somehow fixes the issue.
	[NSApp orderedWindows];
}

- (void)showFileBrowserAtPath:(NSString*)aPath
{
	NSString* const folder = to_ns(path::resolve(to_s(aPath)));
	[NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:[NSURL fileURLWithPath:folder]];

	for(DocumentWindowController* candidate in SortedControllers())
	{
		if([folder isEqualToString:candidate.projectPath ?: candidate.defaultProjectPath])
			return [candidate bringToFront];
	}

	DocumentWindowController* controller = nil;
	for(DocumentWindowController* candidate in SortedControllers())
	{
		if(!candidate.fileBrowserVisible && candidate.documents.count == 1 && is_disposable(candidate.selectedDocument))
		{
			controller = candidate;
			break;
		}
	}

	if(!controller)
		controller = [DocumentWindowController new];
	else if(controller.selectedDocument)
		controller.selectedDocument.customName = @"not untitled"; // release potential untitled token used

	NSDictionary* project;
	if(![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableFolderStateRestore])
		project = [[DocumentWindowController sharedProjectStateDB] valueForKey:folder];

	if(project && [project[@"documents"] count])
	{
		[controller setupControllerForProject:project skipMissingFiles:YES];
	}
	else
	{
		controller.defaultProjectPath = folder;
		controller.fileBrowserVisible = YES;
		controller.documents          = @[ [OakDocumentController.sharedInstance untitledDocument] ];

		[controller.fileBrowser goToURL:[NSURL fileURLWithPath:folder]];
		[controller openAndSelectDocument:controller.documents[controller.selectedTabIndex] activate:YES];
	}
	[controller bringToFront];
}
@end
