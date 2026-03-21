#import "Find.h"
#import "FFResultNode.h"
#import "FFResultsViewController.h"
#import "FFDocumentSearch.h"
#import "CommonAncestor.h"
#import "FFFolderMenu.h"
#import "FFStatusBarViewController.h"
#import <OakFoundation/OakFindProtocol.h>
#import <OakFoundation/NSString Additions.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/OakHistoryList.h>
#import <OakAppKit/NSAlert Additions.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakPasteboard.h>
#import <OakAppKit/OakPasteboardSelector.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <MenuBuilder/MenuBuilder.h>
#import <Preferences/Keys.h>
#import <ns/ns.h>
#import <text/types.h>
#import <text/utf8.h>
#import <regexp/format_string.h>
#import <regexp/regexp.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <io/path.h>
#import <settings/settings.h>

static NSString* const kUserDefaultsFolderOptionsKey               = @"Folder Search Options";
static NSString* const kUserDefaultsFindResultsHeightKey           = @"findResultsHeight";
static NSString* const kUserDefaultsDefaultFindGlobsKey            = @"defaultFindInFolderGlobs";
static NSString* const kUserDefaultsKeepSearchResultsOnDoubleClick = @"keepSearchResultsOnDoubleClick";
static NSString* const kSearchMarkIdentifier                       = @"search";
static NSString* const FFFindWasTriggeredByEnter                   = @"FFFindWasTriggeredByEnter";

enum FindActionTag
{
	FindActionFindNext = 1,
	FindActionFindPrevious,
	FindActionCountMatches,
	FindActionFindAll,
	FindActionReplaceAll,
	FindActionReplaceAndFind,
	FindActionReplaceSelected,
	FindActionReplace,
};

@implementation FindMatch
- (instancetype)initWithUUID:(NSUUID*)uuid firstRange:(text::range_t const&)firstRange lastRange:(text::range_t const&)lastRange
{
	if(self = [super init])
	{
		_UUID       = uuid;
		_firstRange = firstRange;
		_lastRange  = lastRange;
	}
	return self;
}
@end

// ==============================
// = FindPanelModel Interop     =
// ==============================

@interface NSObject (FindPanelModelMethods)
- (NSView*)hostingView;
@end

// ========================
// = FindWindowController =
// ========================

@interface Find () <OakFindServerProtocol, OakUserDefaultsObserver, NSWindowDelegate, NSMenuDelegate>
{
	id                           _findPanelModel;

	NSPopUpButton*               _wherePopUpButton;

	FFStatusBarViewController*   _statusBarViewController;
}
@property (nonatomic, readonly)           FFResultsViewController* resultsViewController;
@property (nonatomic) BOOL                showsResultsOutlineView;

@property (nonatomic) NSString*           otherFolder;
@property (nonatomic, readonly) NSString* searchFolder;

@property (nonatomic) NSString* globString;

@property (nonatomic) BOOL ignoreCase;
@property (nonatomic) BOOL ignoreWhitespace;
@property (nonatomic) BOOL regularExpression;
@property (nonatomic) BOOL wrapAround;
@property (nonatomic) BOOL fullWords; // not implemented

@property (nonatomic) BOOL searchHiddenFolders;
@property (nonatomic) BOOL searchFolderLinks;
@property (nonatomic) BOOL searchFileLinks;
@property (nonatomic) BOOL searchBinaryFiles;

@property (nonatomic) OakHistoryList<NSString*>* globHistoryList;
@property (nonatomic) OakHistoryList<NSString*>* recentFolders;
@property (nonatomic) CGFloat                    findResultsHeight;

@property (nonatomic, readonly) BOOL  canIgnoreWhitespace;
@property (nonatomic) BOOL            canEditGlob;
@property (nonatomic) BOOL            canReplaceInDocument;

@property (nonatomic) FFDocumentSearch* documentSearch;
@property (nonatomic) FFResultNode*     results;

@property (nonatomic) NSUInteger        countOfMatches;
@property (nonatomic) NSUInteger        countOfExcludedMatches;
@property (nonatomic) NSUInteger        countOfReadOnlyMatches;
@property (nonatomic) NSUInteger        countOfExcludedReadOnlyMatches;

@property (nonatomic) BOOL              closeWindowOnSuccess;
@property (nonatomic) BOOL              performingFolderSearch;

// =========================
// = OakFindProtocolServer =
// =========================

@property (nonatomic) find_operation_t findOperation;
@property (nonatomic) find::options_t  findOptions;

- (void)didFind:(NSUInteger)aNumber occurrencesOf:(NSString*)aFindString atPosition:(text::pos_t const&)aPosition wrapped:(BOOL)didWrap;
- (void)didReplace:(NSUInteger)aNumber occurrencesOf:(NSString*)aFindString with:(NSString*)aReplacementString;
@end

@implementation Find
+ (NSSet*)keyPathsForValuesAffectingCanIgnoreWhitespace  { return [NSSet setWithObject:@"regularExpression"]; }
+ (NSSet*)keyPathsForValuesAffectingIgnoreWhitespace     { return [NSSet setWithObject:@"regularExpression"]; }

+ (instancetype)sharedInstance
{
	static Find* sharedInstance = [self new];
	return sharedInstance;
}

+ (void)initialize
{
	[NSUserDefaults.standardUserDefaults registerDefaults:@{
		kUserDefaultsDefaultFindGlobsKey: @[ @"*", @"*.txt", @"*.{c,h}" ],
	}];
}

- (id)init
{
	if(self = [super initWithWindowNibName:@"UNUSED"])
	{
		_projectFolder    = NSHomeDirectory();

		self.globHistoryList = [[OakHistoryList alloc] initWithName:@"Find in Folder Globs.default" stackSize:10 fallbackUserDefaultsKey:kUserDefaultsDefaultFindGlobsKey];
		self.recentFolders   = [[OakHistoryList alloc] initWithName:@"findRecentPlaces" stackSize:21];

		_findPanelModel = [[NSClassFromString(@"FindPanelModel") alloc] init];
		[_findPanelModel setValue:self forKey:@"target"];
	}
	return self;
}

- (void)loadWindow
{
	NSRect r = NSScreen.mainScreen.visibleFrame;
	if(NSWindow* window = [[NSPanel alloc] initWithContentRect:NSMakeRect(NSMidX(r)-100, NSMidY(r)+100, 200, 200) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable) backing:NSBackingStoreBuffered defer:NO])
	{
		window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace|NSWindowCollectionBehaviorFullScreenAuxiliary;
		window.delegate           = self;
		window.frameAutosaveName  = @"Find";
		window.hidesOnDeactivate  = NO;

		_resultsViewController = [[FFResultsViewController alloc] init];
		_resultsViewController.selectResultAction      = @selector(didSelectResult:);
		_resultsViewController.removeResultAction      = @selector(didRemoveResult:);
		_resultsViewController.doubleClickResultAction = @selector(didDoubleClickResult:);
		_resultsViewController.target                  = self;

		_statusBarViewController = [[FFStatusBarViewController alloc] init];
		_statusBarViewController.stopAction = @selector(stopSearch:);
		_statusBarViewController.stopTarget = self;

		// Wire the "Where" popup — create it here so Find.mm controls its menu
		_wherePopUpButton = OakCreatePopUpButton(NO, nil, nil);
		[_wherePopUpButton.widthAnchor constraintLessThanOrEqualToConstant:150].active = YES;
		[self updateSearchInPopUpMenu];

		// Create action popup menu
		NSPopUpButton* actionsPopUpButton = OakCreateActionPopUpButton(YES /* bordered */);
		MBMenu const actionItems = {
			{ /* Placeholder */ },
			{ @"Search",                               @selector(nop:)                                    },
			{ @"Binary Files",                         @selector(toggleSearchBinaryFiles:),   .indent = 1 },
			{ @"Hidden Folders",                       @selector(toggleSearchHiddenFolders:), .indent = 1 },
			{ @"Symbolic Links to Folders",            @selector(toggleSearchFolderLinks:),   .indent = 1 },
			{ @"Symbolic Links to Files",              @selector(toggleSearchFileLinks:),     .indent = 1 },
			{ /* -------- */ },
			{ @"Collapse Results",                     @selector(toggleCollapsedState:),      @"1", .modifierFlags = NSEventModifierFlagCommand|NSEventModifierFlagOption, .target = _resultsViewController },
			{ @"Select Result",                        .delegate = self                                   },
			{ /* -------- */ },
			{ @"Copy Matching Parts",                  @selector(copyMatchingParts:)                      },
			{ @"Copy Matching Parts With Filenames",   @selector(copyMatchingPartsWithFilename:)          },
			{ @"Copy Entire Lines",                    @selector(copyEntireLines:)                        },
			{ @"Copy Entire Lines With Filenames",     @selector(copyEntireLinesWithFilename:)            },
			{ @"Copy Replacements",                    @selector(copyReplacements:)                       },
			{ /* -------- */ },
			{ @"Check All",                            @selector(checkAll:)                               },
			{ @"Uncheck All",                          @selector(uncheckAll:)                             },
		};
		if(NSMenu* actionMenu = MBCreateMenu(actionItems))
			actionsPopUpButton.menu = actionMenu;

		// Pass AppKit views to the SwiftUI model
		[_findPanelModel setValue:_resultsViewController.view forKey:@"resultsView"];
		[_findPanelModel setValue:_statusBarViewController.view forKey:@"statusBarView"];
		[_findPanelModel setValue:_wherePopUpButton forKey:@"wherePopUpButton"];
		[_findPanelModel setValue:actionsPopUpButton forKey:@"actionsPopUpButton"];

		// Set the SwiftUI hosting view as the window content
		window.contentView = [_findPanelModel hostingView];

		// setup find/replace strings/options
		[self userDefaultsDidChange:nil];
		[self findClipboardDidChange:nil];
		[self replaceClipboardDidChange:nil];

		OakObserveUserDefaults(self);
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(findClipboardDidChange:) name:OakPasteboardDidChangeNotification object:OakPasteboard.findPasteboard];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(replaceClipboardDidChange:) name:OakPasteboardDidChangeNotification object:OakPasteboard.replacePasteboard];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(textViewWillPerformFindOperation:) name:@"OakTextViewWillPerformFindOperation" object:nil];

		[window layoutIfNeeded];
		self.window = window;
		[self updateWindowTitle];
	}
}

- (void)menuNeedsUpdate:(NSMenu*)aMenu
{
	[aMenu removeAllItems];
	[NSApp sendAction:@selector(updateShowTabMenu:) to:nil from:aMenu];
}

// ==============================
// = Sync state to SwiftUI model =
// ==============================

- (void)syncOptionsToModel
{
	[_findPanelModel setValue:@(self.regularExpression) forKey:@"regularExpression"];
	[_findPanelModel setValue:@(self.ignoreCase)        forKey:@"ignoreCase"];
	[_findPanelModel setValue:@(self.wrapAround)        forKey:@"wrapAround"];
	[_findPanelModel setValue:@(self.ignoreWhitespace)  forKey:@"ignoreWhitespace"];
	[_findPanelModel setValue:@(self.fullWords)         forKey:@"fullWords"];
	[_findPanelModel setValue:@(self.searchHiddenFolders) forKey:@"searchHiddenFolders"];
	[_findPanelModel setValue:@(self.searchFolderLinks)   forKey:@"searchFolderLinks"];
	[_findPanelModel setValue:@(self.searchFileLinks)     forKey:@"searchFileLinks"];
	[_findPanelModel setValue:@(self.searchBinaryFiles)   forKey:@"searchBinaryFiles"];
	[_findPanelModel setValue:@(self.canEditGlob)          forKey:@"canEditGlob"];
	[_findPanelModel setValue:@(self.canReplaceInDocument)  forKey:@"canReplaceInDocument"];
}

- (void)syncMatchCountsToModel
{
	[_findPanelModel setValue:@(self.countOfMatches)                  forKey:@"countOfMatches"];
	[_findPanelModel setValue:@(self.countOfExcludedMatches)          forKey:@"countOfExcludedMatches"];
	[_findPanelModel setValue:@(self.countOfReadOnlyMatches)          forKey:@"countOfReadOnlyMatches"];
	[_findPanelModel setValue:@(self.countOfExcludedReadOnlyMatches)  forKey:@"countOfExcludedReadOnlyMatches"];
	[_findPanelModel setValue:@(self.canReplaceAll)                   forKey:@"canReplaceAll"];
	[_findPanelModel setValue:self.replaceAllButtonTitle              forKey:@"replaceAllButtonTitle"];
}

// ====================================
// = FindPanelModel delegate methods  =
// ====================================

- (void)findPanelDidChangeFindString:(id)sender
{
	// Model's findString changed — sync to pasteboard on commit
}

- (void)findPanelDidChangeReplaceString:(id)sender
{
	// Model's replaceString changed — update results preview
	NSString* replaceString = [_findPanelModel valueForKey:@"replaceString"];
	_resultsViewController.replaceString = replaceString;
	_resultsViewController.showReplacementPreviews = (replaceString.length > 0);
}

- (void)findPanelDidChangeOptions:(id)sender
{
	// Read options back from model
	self.regularExpression = [[_findPanelModel valueForKey:@"regularExpression"] boolValue];
	self.ignoreCase        = [[_findPanelModel valueForKey:@"ignoreCase"] boolValue];
	self.wrapAround        = [[_findPanelModel valueForKey:@"wrapAround"] boolValue];
	self.ignoreWhitespace  = [[_findPanelModel valueForKey:@"ignoreWhitespace"] boolValue];
	self.fullWords         = [[_findPanelModel valueForKey:@"fullWords"] boolValue];
}

- (void)findPanelDidChangeFolderOptions:(id)sender
{
	self.searchHiddenFolders = [[_findPanelModel valueForKey:@"searchHiddenFolders"] boolValue];
	self.searchFolderLinks   = [[_findPanelModel valueForKey:@"searchFolderLinks"] boolValue];
	self.searchFileLinks     = [[_findPanelModel valueForKey:@"searchFileLinks"] boolValue];
	self.searchBinaryFiles   = [[_findPanelModel valueForKey:@"searchBinaryFiles"] boolValue];
}

- (void)findPanelDidChangeGlob:(id)sender
{
	NSString* glob = [_findPanelModel valueForKey:@"globString"];
	if(glob)
		[_globHistoryList addObject:glob];
}

- (void)findPanelFindAll:(id)sender        { [self performFindAction:FindActionFindAll];        }
- (void)findPanelFindNext:(id)sender       { [self performFindAction:FindActionFindNext];       }
- (void)findPanelFindPrevious:(id)sender   { [self performFindAction:FindActionFindPrevious];   }
- (void)findPanelReplaceAll:(id)sender     { [self performFindAction:FindActionReplaceAll];     }
- (void)findPanelReplace:(id)sender        { [self performFindAction:FindActionReplace];        }
- (void)findPanelReplaceAndFind:(id)sender { [self performFindAction:FindActionReplaceAndFind]; }

- (void)findPanelCountOccurrences:(id)sender { [self performFindAction:FindActionCountMatches]; }

- (void)findPanelStopSearch:(id)sender { [self stopSearch:self]; }

- (void)findPanelShowFindHistory:(id)sender
{
	if(!OakPasteboardSelector.sharedInstance.window.isVisible)
		[OakPasteboard.findPasteboard selectItemForControl:[_findPanelModel hostingView]];
}

- (void)findPanelShowReplaceHistory:(id)sender
{
	if(!OakPasteboardSelector.sharedInstance.window.isVisible)
		[OakPasteboard.replacePasteboard selectItemForControl:[_findPanelModel hostingView]];
}

// ==============================

- (void)userDefaultsDidChange:(NSNotification*)aNotification
{
	self.ignoreCase = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindIgnoreCase];
	self.wrapAround = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindWrapAround];

	NSDictionary* options = [NSUserDefaults.standardUserDefaults dictionaryForKey:kUserDefaultsFolderOptionsKey];
	self.searchHiddenFolders = [[options objectForKey:@"searchHiddenFolders"] boolValue];
	self.searchFolderLinks   = [[options objectForKey:@"searchFolderLinks"] boolValue];
	self.searchFileLinks     = ![[options objectForKey:@"skipFileLinks"] boolValue];
	self.searchBinaryFiles   = [[options objectForKey:@"searchBinaryFiles"] boolValue];

	[self syncOptionsToModel];
}

- (void)findClipboardDidChange:(NSNotification*)aNotification
{
	OakPasteboardEntry* entry = OakPasteboard.findPasteboard.current;
	[_findPanelModel setValue:entry.string forKey:@"findString"];
	self.regularExpression = entry.regularExpression;
	self.ignoreWhitespace  = entry.ignoreWhitespace;
	self.fullWords         = entry.fullWordMatch;
	[self syncOptionsToModel];
}

- (void)replaceClipboardDidChange:(NSNotification*)aNotification
{
	[_findPanelModel setValue:OakPasteboard.replacePasteboard.current.string forKey:@"replaceString"];
}

- (NSString*)findString
{
	return [_findPanelModel valueForKey:@"findString"] ?: @"";
}

- (NSString*)replaceString
{
	return [_findPanelModel valueForKey:@"replaceString"] ?: @"";
}

- (void)updateWindowTitle
{
	if(NSString* folder = self.searchFolder)
		self.window.title = [NSString localizedStringWithFormat:@"Find \u2014 %@", [folder stringByAbbreviatingWithTildeInPath]];
	else if(_searchTarget == FFSearchTargetOpenFiles)
		self.window.title = @"Find \u2014 Open Files";
	else
		self.window.title = @"Find";
}

- (BOOL)isVisible
{
	return self.isWindowLoaded && self.window.isVisible;
}

- (void)showWindow:(id)sender
{
	BOOL isVisibleAndKey = self.isVisible && self.window.isKeyWindow;
	[super showWindow:sender];
	if(!isVisibleAndKey)
		[self.window makeFirstResponder:[_findPanelModel hostingView]];
}

- (BOOL)commitEditing
{
	// =====================
	// = Update Pasteboard =
	// =====================

	if(OakNotEmptyString(self.findString))
	{
		OakPasteboardEntry* entry = OakPasteboard.findPasteboard.current;
		BOOL newFindString        = ![self.findString isEqualToString:entry.string];
		BOOL newRegularExpression = entry.regularExpression != self.regularExpression;
		BOOL newIgnoreWhitespace  = entry.ignoreWhitespace  != self.ignoreWhitespace;
		BOOL newFullWords         = entry.fullWordMatch     != self.fullWords;

		if(newFindString || newRegularExpression || newIgnoreWhitespace || newFullWords)
		{
			NSDictionary* newOptions = @{
				OakFindRegularExpressionOption: @(self.regularExpression),
				OakFindIgnoreWhitespaceOption:  @(self.ignoreWhitespace),
				OakFindFullWordsOption:         @(self.fullWords),
			};
			[OakPasteboard.findPasteboard addEntryWithString:self.findString options:newOptions];
		}
	}

	if(self.replaceString && ![self.replaceString isEqualToString:OakPasteboard.findPasteboard.current.string])
		[OakPasteboard.replacePasteboard addEntryWithString:self.replaceString];

	// Sync glob from model
	NSString* glob = [_findPanelModel valueForKey:@"globString"];
	if(glob && ![glob isEqualToString:_globHistoryList.head])
		[_globHistoryList addObject:glob];

	return YES;
}

- (void)resultsFrameDidChange:(NSNotification*)aNotification
{
	if(self.showsResultsOutlineView)
		self.findResultsHeight = NSHeight(_resultsViewController.view.frame);
}

- (void)windowDidResignKey:(NSNotification*)aNotification
{
	[self commitEditing];
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	[self stopSearch:self];
	[self commitEditing];
}

- (void)textViewWillPerformFindOperation:(NSNotification*)aNotification
{
	if([self isWindowLoaded] && [self.window isVisible] && [self.window isKeyWindow])
		[self commitEditing];
}

// ==============================
// = Create "where" pop-up menu =
// ==============================

- (NSString*)displayNameForFolder:(NSString*)path
{
	std::vector<std::string> paths;
	for(NSUInteger i = 0; i < [self.recentFolders count]; ++i)
		paths.push_back(to_s([self.recentFolders objectAtIndex:i]));
	if(NSString* folder = self.searchFolder)
		paths.push_back(to_s(folder));
	paths.push_back(to_s(self.projectFolder));

	auto it = std::find(paths.begin(), paths.end(), to_s(path));
	if(it != paths.end())
		return [NSString stringWithCxxString:path::display_name(*it, path::disambiguate(paths)[it - paths.begin()])];
	return [NSFileManager.defaultManager displayNameAtPath:path];
}

- (void)updateSearchInPopUpMenu
{
	NSMenuItem* folderItem;

	MBMenu const items = {
		{ @"Document",            @selector(orderFrontFindPanel:),  @"f", .tag = FFSearchTargetDocument          },
		{ @"Selection",           @selector(orderFrontFindPanel:),        .tag = FFSearchTargetSelection         },
		{ /* -------- */ },
		{ @"Open Files",          @selector(orderFrontFindPanel:),        .tag = FFSearchTargetOpenFiles         },
		{ @"Project Folder",      @selector(orderFrontFindPanel:),  @"F", .tag = FFSearchTargetProject           },
		{ @"File Browser Items",  @selector(orderFrontFindPanel:),        .tag = FFSearchTargetFileBrowserItems  },
		{ @"Other Folder\u2026",  @selector(showFolderSelectionPanel:),   .tag = FFSearchTargetOther             },
		{ /* -------- */ },
		{ @"\u00ABLast Folder\u00BB",       @selector(orderFrontFindPanel:),        .ref = &folderItem                     },
		{ /* -------- */ },
		{ @"Recent Places",       @selector(nop:),                                                               },
	};

	NSMenu* whereMenu = _wherePopUpButton.menu;
	[whereMenu removeAllItems];
	MBCreateMenu(items, whereMenu);

	if(NSString* lastFolder = self.searchFolder ?: self.projectFolder)
	{
		[folderItem setTitle:[self displayNameForFolder:lastFolder]];
		[folderItem setIconForFile:lastFolder];
		[FFFolderMenu addSubmenuForDirectoryAtPath:lastFolder toMenuItem:folderItem];
	}

	if(_searchTarget == FFSearchTargetProject || _searchTarget == FFSearchTargetOther || (_searchTarget == FFSearchTargetFileBrowserItems && _fileBrowserItems.count == 1))
			[_wherePopUpButton selectItem:folderItem];
	else	[_wherePopUpButton selectItemWithTag:_searchTarget];

	// =================
	// = Recent Places =
	// =================

	NSInteger selectedIndex = -1;
	NSMutableArray<NSString*>* recentPaths = [NSMutableArray array];
	for(NSUInteger i = 0; i < _recentFolders.count; ++i)
	{
		NSString* path = [_recentFolders objectAtIndex:i];
		if([path isEqualToString:_projectFolder] || ![NSFileManager.defaultManager fileExistsAtPath:path])
			continue;

		if(_searchTarget == FFSearchTargetOther && [path isEqualToString:_otherFolder])
			selectedIndex = recentPaths.count;
		[recentPaths addObject:path];
	}

	for(NSUInteger i = 0; i < recentPaths.count; ++i)
	{
		if(i == selectedIndex)
			continue;

		NSString* path = recentPaths[i];

		NSMenuItem* recentItem = [whereMenu addItemWithTitle:[self displayNameForFolder:path] action:@selector(orderFrontFindPanel:) keyEquivalent:@""];
		[recentItem setIconForFile:path];
		[recentItem setRepresentedObject:path];

		if(selectedIndex+1 == i)
		{
			recentItem.action        = @selector(goBack:);
			recentItem.target        = self;
			recentItem.keyEquivalent = @"[";
			recentItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
		}
		else if(i+1 == selectedIndex)
		{
			recentItem.action        = @selector(goForward:);
			recentItem.target        = self;
			recentItem.keyEquivalent = @"]";
			recentItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
		}
	}
}

- (void)setSearchTarget:(FFSearchTarget)newTarget
{
	_searchTarget = newTarget;

	self.canEditGlob          = _searchTarget != FFSearchTargetDocument && _searchTarget != FFSearchTargetSelection;
	self.canReplaceInDocument = _searchTarget == FFSearchTargetDocument || _searchTarget == FFSearchTargetSelection;

	[_findPanelModel setValue:@(self.canEditGlob) forKey:@"canEditGlob"];
	[_findPanelModel setValue:@(self.canReplaceInDocument) forKey:@"canReplaceInDocument"];

	[self updateSearchInPopUpMenu];
	[self updateWindowTitle];

	BOOL isFolderSearch = _searchTarget != FFSearchTargetDocument && _searchTarget != FFSearchTargetSelection;
	self.showsResultsOutlineView = isFolderSearch;
}

- (void)orderFrontFindPanel:(id)sender
{
	if([sender respondsToSelector:@selector(representedObject)])
	{
		if(NSString* folder = [sender representedObject])
		{
			self.otherFolder = folder;
			self.searchTarget = FFSearchTargetOther;
			return;
		}
	}

	if([sender respondsToSelector:@selector(tag)])
		self.searchTarget = FFSearchTarget([sender tag]);
}

// ==============================

- (void)setShowsResultsOutlineView:(BOOL)flag
{
	if(_showsResultsOutlineView == flag)
		return;

	if(_showsResultsOutlineView = flag)
	{
		_resultsViewController.view.frame = { .size = NSMakeSize(400, MAX(50, self.findResultsHeight)) };
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resultsFrameDidChange:) name:NSViewFrameDidChangeNotification object:_resultsViewController.view];
	}
	else
	{
		[NSNotificationCenter.defaultCenter removeObserver:self name:NSViewFrameDidChangeNotification object:_resultsViewController.view];
	}

	[_findPanelModel setValue:@(flag) forKey:@"showResults"];
}

- (void)setStatusString:(NSString*)aString
{
	_statusBarViewController.statusText = aString;
	[_findPanelModel setValue:aString forKey:@"statusText"];
}

- (void)setAlternateStatusString:(NSString*)aString
{
	_statusBarViewController.alternateStatusText = aString;
	[_findPanelModel setValue:aString forKey:@"alternateStatusText"];
}

- (NSString*)searchFolder
{
	if(_searchTarget == FFSearchTargetProject)
		return self.projectFolder;
	else if(_searchTarget == FFSearchTargetFileBrowserItems && _fileBrowserItems.count == 1)
		return _fileBrowserItems.firstObject;
	else if(_searchTarget == FFSearchTargetOther)
		return self.otherFolder;
	return nil;
}

- (IBAction)goToParentFolder:(id)sender
{
	if(_searchTarget == FFSearchTargetFileBrowserItems && _fileBrowserItems.count > 1)
	{
		self.otherFolder = CommonAncestor(_fileBrowserItems);
		self.searchTarget = FFSearchTargetOther;
	}
	else if(NSString* parent = [self.searchFolder stringByDeletingLastPathComponent])
	{
		self.otherFolder = parent;
		self.searchTarget = FFSearchTargetOther;
	}
}

- (void)setFindResultsHeight:(CGFloat)height { [NSUserDefaults.standardUserDefaults setInteger:height forKey:kUserDefaultsFindResultsHeightKey]; }
- (CGFloat)findResultsHeight                 { return [NSUserDefaults.standardUserDefaults integerForKey:kUserDefaultsFindResultsHeightKey] ?: 200; }

- (void)setRegularExpression:(BOOL)flag
{
	if(_regularExpression == flag)
		return;

	_regularExpression = flag;
	[_findPanelModel setValue:@(flag) forKey:@"regularExpression"];
}

- (void)setIgnoreCase:(BOOL)flag        { if(_ignoreCase != flag) { [NSUserDefaults.standardUserDefaults setObject:@(_ignoreCase = flag) forKey:kUserDefaultsFindIgnoreCase]; [_findPanelModel setValue:@(_ignoreCase) forKey:@"ignoreCase"]; } }
- (void)setWrapAround:(BOOL)flag        { if(_wrapAround != flag) { [NSUserDefaults.standardUserDefaults setObject:@(_wrapAround = flag) forKey:kUserDefaultsFindWrapAround]; [_findPanelModel setValue:@(_wrapAround) forKey:@"wrapAround"]; } }
- (BOOL)ignoreWhitespace                { return _ignoreWhitespace && self.canIgnoreWhitespace; }
- (BOOL)canIgnoreWhitespace             { return _regularExpression == NO; }

- (NSString*)globString                 { return [_findPanelModel valueForKey:@"globString"] ?: _globHistoryList.head; }
- (void)setGlobString:(NSString*)aGlob  { [_globHistoryList addObject:aGlob]; [_findPanelModel setValue:aGlob forKey:@"globString"]; }

- (void)setProjectFolder:(NSString*)aFolder
{
	if(_projectFolder != aFolder && ![_projectFolder isEqualToString:aFolder])
	{
		_projectFolder = aFolder ?: @"";
		self.globHistoryList = [[OakHistoryList alloc] initWithName:[NSString stringWithFormat:@"Find in Folder Globs.%@", _projectFolder] stackSize:10 fallbackUserDefaultsKey:kUserDefaultsDefaultFindGlobsKey];
		[self updateSearchInPopUpMenu];
	}
}

- (void)updateFolderSearchUserDefaults
{
	NSMutableDictionary* options = [NSMutableDictionary dictionary];

	if(self.searchHiddenFolders) options[@"searchHiddenFolders"] = @YES;
	if(self.searchFolderLinks)   options[@"searchFolderLinks"]   = @YES;
	if(!self.searchFileLinks)    options[@"skipFileLinks"]       = @YES;
	if(self.searchBinaryFiles)   options[@"searchBinaryFiles"]   = @YES;

	if([options count])
			[NSUserDefaults.standardUserDefaults setObject:options forKey:kUserDefaultsFolderOptionsKey];
	else	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsFolderOptionsKey];
}

- (void)setSearchHiddenFolders:(BOOL)flag { if(_searchHiddenFolders != flag) { _searchHiddenFolders = flag; [self updateFolderSearchUserDefaults]; } }
- (void)setSearchFolderLinks:(BOOL)flag   { if(_searchFolderLinks != flag)   { _searchFolderLinks   = flag; [self updateFolderSearchUserDefaults]; } }
- (void)setSearchFileLinks:(BOOL)flag     { if(_searchFileLinks != flag)     { _searchFileLinks     = flag; [self updateFolderSearchUserDefaults]; } }
- (void)setSearchBinaryFiles:(BOOL)flag   { if(_searchBinaryFiles != flag)   { _searchBinaryFiles   = flag; [self updateFolderSearchUserDefaults]; } }

- (IBAction)toggleSearchHiddenFolders:(id)sender { self.searchHiddenFolders = !self.searchHiddenFolders; [self syncOptionsToModel]; }
- (IBAction)toggleSearchFolderLinks:(id)sender   { self.searchFolderLinks   = !self.searchFolderLinks;   [self syncOptionsToModel]; }
- (IBAction)toggleSearchFileLinks:(id)sender     { self.searchFileLinks     = !self.searchFileLinks;     [self syncOptionsToModel]; }
- (IBAction)toggleSearchBinaryFiles:(id)sender   { self.searchBinaryFiles   = !self.searchBinaryFiles;   [self syncOptionsToModel]; }

- (IBAction)takeLevelToFoldFrom:(id)sender       { [_resultsViewController toggleCollapsedState:sender];                    }
- (IBAction)selectNextResult:(id)sender          { [_resultsViewController selectNextResultWrapAround:self.wrapAround];     }
- (IBAction)selectPreviousResult:(id)sender      { [_resultsViewController selectPreviousResultWrapAround:self.wrapAround]; }
- (IBAction)selectNextTab:(id)sender             { [_resultsViewController selectNextDocument:sender];                      }
- (IBAction)selectPreviousTab:(id)sender         { [_resultsViewController selectPreviousDocument:sender];                  }

// ========
// = Find =
// ========

- (IBAction)showFolderSelectionPanel:(id)sender
{
	NSOpenPanel* openPanel = [NSOpenPanel openPanel];
	openPanel.title = @"Find in Folder";
	openPanel.canChooseFiles = NO;
	openPanel.canChooseDirectories = YES;
	if(NSString* folder = self.searchFolder)
		openPanel.directoryURL = [NSURL fileURLWithPath:folder];
	if(self.isWindowLoaded && self.window.isVisible)
	{
		[openPanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
			if(result == NSModalResponseOK)
			{
				self.otherFolder  = openPanel.URLs.lastObject.filePathURL.path;
				self.searchTarget = FFSearchTargetOther;
			}
			else if(self.window.isVisible) // Reset selected item in pop-up button
			{
				self.searchTarget = self.searchTarget;
			}
		}];
	}
	else
	{
		[openPanel beginWithCompletionHandler:^(NSInteger result) {
			if(result == NSModalResponseOK)
			{
				self.otherFolder  = openPanel.URLs.lastObject.filePathURL.path;
				self.searchTarget = FFSearchTargetOther;
				[self showWindow:self];
			}
		}];
	}
}

- (void)goBack:(id)sender
{
	NSInteger index = [_wherePopUpButton.menu indexOfItemWithTarget:self andAction:_cmd];
	if(index != -1)
		[self orderFrontFindPanel:_wherePopUpButton.menu.itemArray[index]];
}

- (void)goForward:(id)sender
{
	NSInteger index = [_wherePopUpButton.menu indexOfItemWithTarget:self andAction:_cmd];
	if(index != -1)
		[self orderFrontFindPanel:_wherePopUpButton.menu.itemArray[index]];
	else if(_searchTarget == FFSearchTargetOther && _otherFolder)
		self.searchTarget = FFSearchTargetProject;
}

// ================
// = Find actions =
// ================

+ (NSSet*)keyPathsForValuesAffectingCanReplaceAll         { return [NSSet setWithArray:@[ @"countOfMatches", @"countOfExcludedMatches", @"countOfReadOnlyMatches", @"countOfExcludedReadOnlyMatches", @"showsResultsOutlineView" ]]; }
+ (NSSet*)keyPathsForValuesAffectingReplaceAllButtonTitle { return [NSSet setWithArray:@[ @"countOfMatches", @"countOfExcludedMatches", @"countOfReadOnlyMatches", @"countOfExcludedReadOnlyMatches", @"showsResultsOutlineView" ]]; }

- (BOOL)canReplaceAll                { return _showsResultsOutlineView ? (_countOfExcludedMatches - _countOfExcludedReadOnlyMatches < _countOfMatches - _countOfReadOnlyMatches) : YES; }
- (NSString*)replaceAllButtonTitle   { return _showsResultsOutlineView && (_countOfExcludedMatches || _countOfReadOnlyMatches && _countOfReadOnlyMatches != _countOfMatches) ? @"Replace Selected" : @"Replace All"; }

- (IBAction)countOccurrences:(id)sender   { [self performFindAction:FindActionCountMatches];   }
- (IBAction)findAll:(id)sender            { [self performFindAction:FindActionFindAll];        }
- (IBAction)findAllInSelection:(id)sender { [self performFindAction:FindActionFindAll];        }
- (IBAction)findNext:(id)sender           { [self performFindAction:FindActionFindNext];       }
- (IBAction)findPrevious:(id)sender       { [self performFindAction:FindActionFindPrevious];   }
- (IBAction)replaceAll:(id)sender         { [self performFindAction:FindActionReplaceAll];     }
- (IBAction)replaceAndFind:(id)sender     { [self performFindAction:FindActionReplaceAndFind]; }
- (IBAction)replace:(id)sender            { [self performFindAction:FindActionReplace];        }

- (IBAction)stopSearch:(id)sender
{
	if(_performingFolderSearch)
	{
		[_documentSearch stop];
		[self folderSearchDidFinish:nil];
		self.statusString = @"Stopped.";
	}
}

- (void)performFindAction:(FindActionTag)action
{
	[self commitEditing];

	if(self.regularExpression)
	{
		std::string error = regexp::validate(to_s(self.findString));
		if(error != NULL_STR)
		{
			self.statusString = to_ns(text::format("Invalid regular expression: %s.", error.c_str()));
			return;
		}
	}

	_findOptions = (self.regularExpression ? find::regular_expression : find::none) | (self.ignoreWhitespace ? find::ignore_whitespace : find::none) | (self.fullWords ? find::full_words : find::none) | (self.ignoreCase ? find::ignore_case : find::none) | (self.wrapAround ? find::wrap_around : find::none);
	if(action == FindActionFindPrevious)
		_findOptions |= find::backwards;
	else if(action == FindActionCountMatches || action == FindActionFindAll || action == FindActionReplaceAll)
		_findOptions |= find::all_matches;

	FFSearchTarget searchTarget = self.searchTarget;
	if(searchTarget != FFSearchTargetSelection && (searchTarget != FFSearchTargetDocument || action == FindActionFindAll && self.documentIdentifier))
	{
		switch(action)
		{
			case FindActionFindAll:
			{
				if(searchTarget == FFSearchTargetDocument && self.documentIdentifier)
				{
					if(OakDocument* document = [OakDocumentController.sharedInstance findDocumentWithIdentifier:self.documentIdentifier])
					{
						self.documentSearch = nil;
						self.showsResultsOutlineView = YES;
						_resultsViewController.hideCheckBoxes = YES;
						[_findPanelModel setValue:@YES forKey:@"hideCheckBoxes"];
						[self acceptMatches:[document matchesForString:self.findString options:_findOptions]];
						[self folderSearchDidFinish:nil];
					}
				}
				else if(searchTarget == FFSearchTargetOpenFiles)
				{
					self.documentSearch = nil;
					self.showsResultsOutlineView = YES;
					_resultsViewController.hideCheckBoxes = NO;
					[_findPanelModel setValue:@NO forKey:@"hideCheckBoxes"];
					for(OakDocument* document in [OakDocumentController.sharedInstance openDocuments])
						[self acceptMatches:[document matchesForString:self.findString options:_findOptions]];
					[self folderSearchDidFinish:nil];
				}
				else
				{
					NSArray* paths;
					if(searchTarget == FFSearchTargetProject)
						paths = @[ self.projectFolder ];
					else if(searchTarget == FFSearchTargetFileBrowserItems)
						paths = self.fileBrowserItems;
					else // searchTarget == FFSearchTargetOther
						paths = @[ self.otherFolder ];

					BOOL isDirectory = NO;
					if((searchTarget == FFSearchTargetOther || searchTarget == FFSearchTargetFileBrowserItems) && paths.count == 1 && [NSFileManager.defaultManager fileExistsAtPath:paths.firstObject isDirectory:&isDirectory] && isDirectory)
						[self.recentFolders addObject:paths.firstObject];

					FFDocumentSearch* folderSearch = [FFDocumentSearch new];
					folderSearch.searchBinaryFiles   = YES;
					folderSearch.searchString        = self.findString;
					folderSearch.options             = _findOptions;
					folderSearch.paths               = paths;
					folderSearch.glob                = self.globString;
					folderSearch.searchFolderLinks   = self.searchFolderLinks;
					folderSearch.searchFileLinks     = self.searchFileLinks;
					folderSearch.searchHiddenFolders = self.searchHiddenFolders;
					folderSearch.searchBinaryFiles   = self.searchBinaryFiles;

					self.documentSearch = folderSearch;
				}
			}
			break;

			case FindActionReplaceAll:
			case FindActionReplaceSelected:
			{
				NSUInteger replaceCount = 0, fileCount = 0;
				std::string replaceString = to_s(self.replaceString);

				for(FFResultNode* parent in _results.children)
				{
					if(parent.countOfExcluded == parent.countOfLeafs)
						continue;

					std::multimap<std::pair<size_t, size_t>, std::string> replacements;
					for(FFResultNode* child in parent.children)
					{
						if(child.excluded)
							continue;
						child.replaceString = self.replaceString;
						replacements.emplace(std::make_pair(child.match.first, child.match.last), self.regularExpression ? format_string::expand(replaceString, child.match.captures) : replaceString);
					}

					if(OakDocument* doc = parent.document)
					{
						if(doc.isLoaded)
						{
							[doc performReplacements:replacements checksum:parent.match.checksum];
						}
						else
						{
							if(![doc performReplacements:replacements checksum:parent.match.checksum])
							{
								[parent.children setValue:nil forKey:@"replaceString"];
								continue;
							}

							[doc saveModalForWindow:self.window completionHandler:^(OakDocumentIOResult result, NSString* errorMessage, oak::uuid_t const& filterUUID){
								if(!doc.isLoaded)
									doc.content = nil;
							}];
						}

						parent.readOnly = YES;
						replaceCount += replacements.size();
						++fileCount;
					}
				}
				self.statusString = [NSString stringWithFormat:@"%@ replacement%@ made across %@ file%@.", [NSNumberFormatter localizedStringFromNumber:@(replaceCount) numberStyle:NSNumberFormatterDecimalStyle], replaceCount == 1 ? @"" : @"s", [NSNumberFormatter localizedStringFromNumber:@(fileCount) numberStyle:NSNumberFormatterDecimalStyle], fileCount == 1 ? @"" : @"s"];
				[self syncMatchCountsToModel];
			}
			break;

			case FindActionFindNext:     [self selectNextResult:self];     break;
			case FindActionFindPrevious: [self selectPreviousResult:self]; break;
		}
	}
	else
	{
		bool onlySelection = searchTarget == FFSearchTargetSelection;
		switch(action)
		{
			case FindActionFindNext:
			case FindActionFindPrevious:
			case FindActionFindAll:        _findOperation = onlySelection ? kFindOperationFindInSelection       : kFindOperationFind;       break;
			case FindActionCountMatches:   _findOperation = onlySelection ? kFindOperationCountInSelection      : kFindOperationCount;      break;
			case FindActionReplaceAll:     _findOperation = onlySelection ? kFindOperationReplaceAllInSelection : kFindOperationReplaceAll; break;
			case FindActionReplaceAndFind: _findOperation = kFindOperationReplaceAndFind;                                                   break;
			case FindActionReplace:        _findOperation = kFindOperationReplace;                                                          break;
		}

		self.closeWindowOnSuccess = action == FindActionFindNext && [[NSApp currentEvent] type] == NSEventTypeKeyDown && to_s([NSApp currentEvent]) == utf8::to_s(NSCarriageReturnCharacter);
		self.findMatches = nil;
		[NSApp sendAction:@selector(performFindOperation:) to:nil from:self];
	}
}

- (void)didFind:(NSUInteger)aNumber occurrencesOf:(NSString*)aFindString atPosition:(text::pos_t const&)aPosition wrapped:(BOOL)didWrap
{
	static std::string const formatStrings[4][3] = {
		{ "No more occurrences of \"${found}\".", "Found \"${found}\"${line:+ at line ${line}, column ${column}}.",               "${count} occurrences of \"${found}\"." },
		{ "No more matches for \"${found}\".",    "Found one match for \"${found}\"${line:+ at line ${line}, column ${column}}.", "${count} matches for \"${found}\"."    },
	};

	std::map<std::string, std::string> variables;
	variables["count"]  = to_s([NSNumberFormatter localizedStringFromNumber:@(aNumber) numberStyle:NSNumberFormatterDecimalStyle]);
	variables["found"]  = to_s(aFindString);
	variables["line"]   = aPosition ? std::to_string(aPosition.line + 1)   : NULL_STR;
	variables["column"] = aPosition ? std::to_string(aPosition.column + 1) : NULL_STR;
	NSString* statusString = [NSString stringWithCxxString:format_string::expand(formatStrings[(_findOptions & find::regular_expression) ? 1 : 0][std::min<size_t>(aNumber, 2)], variables)];
	self.statusString = statusString;

	NSResponder* keyView = [[NSApp keyWindow] firstResponder];
	id element = [keyView respondsToSelector:@selector(cell)] ? [keyView performSelector:@selector(cell)] : keyView;
	if([element respondsToSelector:@selector(isAccessibilityElement)] && [element isAccessibilityElement])
		NSAccessibilityPostNotificationWithUserInfo(element, NSAccessibilityAnnouncementRequestedNotification, @{ NSAccessibilityAnnouncementKey: statusString });

	if(self.closeWindowOnSuccess && aNumber != 0)
		return [self close];
}

- (void)didReplace:(NSUInteger)aNumber occurrencesOf:(NSString*)aFindString with:(NSString*)aReplacementString
{
	static NSString* const formatStrings[2][3] = {
		{ @"Nothing replaced (no occurrences of \u201C%@\u201D).", @"Replaced one occurrence of \u201C%@\u201D.", @"Replaced %2$@ occurrences of \u201C%@\u201D." },
		{ @"Nothing replaced (no matches for \u201C%@\u201D).",    @"Replaced one match of \u201C%@\u201D.",      @"Replaced %2$@ matches of \u201C%@\u201D."     }
	};
	NSString* format = formatStrings[(_findOptions & find::regular_expression) ? 1 : 0][aNumber > 2 ? 2 : aNumber];
	self.statusString = [NSString stringWithFormat:format, aFindString, [NSNumberFormatter localizedStringFromNumber:@(aNumber) numberStyle:NSNumberFormatterDecimalStyle]];
}

// ===========
// = Options =
// ===========

- (IBAction)takeFindOptionToToggleFrom:(id)sender
{
	ASSERT([sender respondsToSelector:@selector(tag)]);

	find::options_t option = find::options_t([sender tag]);
	switch(option)
	{
		case find::full_words:         self.fullWords         = !self.fullWords;         break;
		case find::ignore_case:        self.ignoreCase        = !self.ignoreCase;        break;
		case find::ignore_whitespace:  self.ignoreWhitespace  = !self.ignoreWhitespace;  break;
		case find::regular_expression: self.regularExpression = !self.regularExpression; break;
		case find::wrap_around:        self.wrapAround        = !self.wrapAround;        break;
		default:
			ASSERTF(false, "Unknown find option tag %d\n", option);
	}

	[self syncOptionsToModel];

	if([OakPasteboard.findPasteboard.current.string isEqualToString:self.findString])
		[self commitEditing];
}

// ====================
// = Search in Folder =
// ====================

- (void)clearMatches
{
	if(_results)
	{
		for(FFResultNode* parent in _results.children)
			[parent.document removeAllMarksOfType:kSearchMarkIdentifier];

		[self unbind:@"countOfMatches"];
		[self unbind:@"countOfExcludedMatches"];
		[self unbind:@"countOfReadOnlyMatches"];
		[self unbind:@"countOfExcludedReadOnlyMatches"];

		self.countOfMatches = self.countOfExcludedMatches = self.countOfReadOnlyMatches = self.countOfExcludedReadOnlyMatches = 0;
		[self syncMatchCountsToModel];
	}

	_resultsViewController.results = _results = [FFResultNode new];
}

- (void)setDocumentSearch:(FFDocumentSearch*)newSearcher
{
	[self clearMatches];

	if(_documentSearch)
	{
		[_documentSearch removeObserver:self forKeyPath:@"currentPath"];
		[NSNotificationCenter.defaultCenter removeObserver:self name:FFDocumentSearchDidReceiveResultsNotification object:_documentSearch];
		[NSNotificationCenter.defaultCenter removeObserver:self name:FFDocumentSearchDidFinishNotification object:_documentSearch];
		[_documentSearch stop];
	}

	if(_documentSearch = newSearcher)
	{
		_statusBarViewController.progressIndicatorVisible = YES;
		[_findPanelModel setValue:@YES forKey:@"isSearching"];
		self.statusString            = @"Searching\u2026";
		self.showsResultsOutlineView = YES;
		_resultsViewController.hideCheckBoxes = NO;
		[_findPanelModel setValue:@NO forKey:@"hideCheckBoxes"];

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(folderSearchDidReceiveResults:) name:FFDocumentSearchDidReceiveResultsNotification object:_documentSearch];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(folderSearchDidFinish:) name:FFDocumentSearchDidFinishNotification object:_documentSearch];
		[_documentSearch addObserver:self forKeyPath:@"currentPath" options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld) context:NULL];
		self.performingFolderSearch = YES;
		[_documentSearch start];
	}
}

- (void)acceptMatches:(NSArray<OakDocumentMatch*>*)matches
{
	NSUInteger countOfExistingItems = _results.children.count;

	FFResultNode* parent = nil;
	for(OakDocumentMatch* match in matches)
	{
		[match.document setMarkOfType:kSearchMarkIdentifier atPosition:match.range.from content:nil];

		FFResultNode* node = [FFResultNode resultNodeWithMatch:match];
		if(!parent || ![parent.document isEqual:node.document])
			[_results addResultNode:(parent = [FFResultNode resultNodeWithMatch:match baseDirectory:CommonAncestor(_documentSearch.paths)])];
		[parent addResultNode:node];
	}

	[_resultsViewController insertItemsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(countOfExistingItems, _results.children.count - countOfExistingItems)]];
}

- (void)folderSearchDidReceiveResults:(NSNotification*)aNotification
{
	[self acceptMatches:[aNotification userInfo][@"matches"]];
}

- (void)setUpFindMatches:(id)sender
{
	NSMutableArray* findMatches = [NSMutableArray array];
	for(FFResultNode* parent in _results.children)
		[findMatches addObject:[[FindMatch alloc] initWithUUID:parent.firstResultNode.document.identifier firstRange:parent.firstResultNode.match.range lastRange:parent.lastResultNode.match.range]];
	self.findMatches = findMatches;
}

- (void)folderSearchDidFinish:(NSNotification*)aNotification
{
	self.performingFolderSearch = NO;
	_statusBarViewController.progressIndicatorVisible = NO;
	[_findPanelModel setValue:@NO forKey:@"isSearching"];
	if(!_results)
		return;

	[self bind:@"countOfMatches" toObject:_results withKeyPath:@"countOfLeafs" options:nil];
	[self bind:@"countOfExcludedMatches" toObject:_results withKeyPath:@"countOfExcluded" options:nil];
	[self bind:@"countOfReadOnlyMatches" toObject:_results withKeyPath:@"countOfReadOnly" options:nil];
	[self bind:@"countOfExcludedReadOnlyMatches" toObject:_results withKeyPath:@"countOfExcludedReadOnly" options:nil];

	[self setUpFindMatches:self];
	[self syncMatchCountsToModel];

	NSString* fmt;
	switch(self.countOfMatches)
	{
		case 0:  fmt = @"No results found for \u201C%@\u201D.";     break;
		case 1:  fmt = @"Found one result for \u201C%@\u201D.";     break;
		default: fmt = @"Found %2$@ results for \u201C%1$@\u201D."; break;
	}

	NSString* searchString = [_documentSearch searchString] ?: self.findString;
	NSString* msg = [NSString stringWithFormat:fmt, searchString, [NSNumberFormatter localizedStringFromNumber:@(self.countOfMatches) numberStyle:NSNumberFormatterDecimalStyle]];
	if(_documentSearch)
	{
		NSNumberFormatter* formatter = [NSNumberFormatter new];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
		formatter.maximumFractionDigits = 1;
		NSString* seconds = [formatter stringFromNumber:@([_documentSearch searchDuration])];

		self.statusString          = [msg stringByAppendingFormat:([_documentSearch scannedFileCount] == 1 ? @" (searched one file in %@ seconds)" : @" (searched %2$@ files in %1$@ seconds)"), seconds, [NSNumberFormatter localizedStringFromNumber:@([_documentSearch scannedFileCount]) numberStyle:NSNumberFormatterDecimalStyle]];
		self.alternateStatusString = [msg stringByAppendingFormat:@" (searched %2$@ in %1$@ seconds)", seconds, [NSByteCountFormatter stringFromByteCount:_documentSearch.scannedByteCount countStyle:NSByteCountFormatterCountStyleFile]];
	}
	else
	{
		self.statusString = msg;
	}

	__weak __block id token = [NSNotificationCenter.defaultCenter addObserverForName:OakPasteboardDidChangeNotification object:OakPasteboard.findPasteboard queue:nil usingBlock:^(NSNotification*){
		self.findMatches = nil;
		for(FFResultNode* parent in _results.children)
			[parent.document removeAllMarksOfType:kSearchMarkIdentifier];
		[NSNotificationCenter.defaultCenter removeObserver:token];
	}];
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if([keyPath isEqualToString:@"currentPath"])
	{
		id newValue = [change objectForKey:NSKeyValueChangeNewKey], oldValue = [change objectForKey:NSKeyValueChangeOldKey];
		std::string searchPath     = [newValue respondsToSelector:@selector(UTF8String)] ? [newValue UTF8String] : "";
		std::string lastSearchPath = [oldValue respondsToSelector:@selector(UTF8String)] ? [oldValue UTF8String] : "";

		if(searchPath != lastSearchPath && !path::is_directory(searchPath))
			searchPath = path::parent(searchPath);

		std::string relative = path::relative_to(searchPath, to_s(self.searchFolder));
		if(path::is_directory(searchPath))
			relative += "/";

		self.statusString = [NSString localizedStringWithFormat:@"Searching \u201C%@\u201D\u2026", [NSString stringWithCxxString:relative]];
	}
}

// =============================
// = Selecting Results Actions =
// =============================

- (void)didSelectResult:(FFResultNode*)item
{
	OakDocument* doc = item.document;
	if(!doc.isOpen)
		doc.recentTrackingDisabled = YES;

	NSMutableDictionary* captures = [NSMutableDictionary dictionary];
	for(auto pair : item.match.captures)
		captures[to_ns(pair.first)] = to_ns(pair.second);
	doc.matchCaptures = [captures copy];

	[_delegate selectRange:item.match.range inDocument:doc];
}

- (void)didDoubleClickResult:(FFResultNode*)item
{
	if([[NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsKeepSearchResultsOnDoubleClick] boolValue])
		return;
	[_delegate bringToFront];
	[self close];
}

- (void)didRemoveResult:(FFResultNode*)item
{
	if(OakIsAlternateKeyOrMouseEvent())
	{
		if(item.document.path)
		{
			std::string path = path::relative_to(to_s(item.document.path), to_s(CommonAncestor(_documentSearch.paths)));
			NSString* newGlob = [self.globString stringByAppendingFormat:@"~%@", [NSString stringWithCxxString:path]];
			self.globString = newGlob;
		}
	}

	[item.document removeAllMarksOfType:kSearchMarkIdentifier];
	[self setUpFindMatches:self];

	NSString* fmt;
	switch(self.countOfMatches)
	{
		case 0:  fmt = @"No results for \u201C%@\u201D.";             break;
		case 1:  fmt = @"Showing one result for \u201C%@\u201D.";     break;
		default: fmt = @"Showing %2$@ results for \u201C%1$@\u201D."; break;
	}
	self.statusString = [NSString stringWithFormat:fmt, [_documentSearch searchString], [NSNumberFormatter localizedStringFromNumber:@(self.countOfMatches) numberStyle:NSNumberFormatterDecimalStyle]];
}

// =====================
// = Show Tab… Submenu =
// =====================

- (IBAction)takeSelectedPathFrom:(id)sender
{
	FFResultNode* item = [sender representedObject];
	if([item isKindOfClass:[FFResultNode class]])
		[_resultsViewController showResultNode:item.firstResultNode];
}

- (void)updateShowTabMenu:(NSMenu*)aMenu
{
	if(self.countOfMatches == 0)
	{
		[[aMenu addItemWithTitle:@"No Results" action:@selector(nop:) keyEquivalent:@""] setEnabled:NO];
	}
	else
	{
		char key = 0;
		for(FFResultNode* parent in _results.children)
		{
			if(OakDocument* doc = parent.document)
			{
				NSMenuItem* item = [aMenu addItemWithTitle:(doc.path ? to_ns(path::relative_to(to_s(doc.path), to_s(self.searchFolder))) : doc.displayName) action:@selector(takeSelectedPathFrom:) keyEquivalent:key < 9 ? [NSString stringWithFormat:@"%c", '0' + (++key % 10)] : @""];
				if(aMenu.propertiesToUpdate & NSMenuPropertyItemImage)
					[item setImage:parent.document.icon];
				[item setRepresentedObject:parent];
			}
		}
	}
}

// =====================
// = Copy Find Results =
// =====================

- (void)copyReplacements:(id)sender
{
	NSMutableArray* array = [NSMutableArray array];

	std::string const replacementString = to_s(self.replaceString);
	for(FFResultNode* item in _resultsViewController.selectedResults)
	{
		auto const& captures = item.match.captures;
		[array addObject:captures.empty() ? self.replaceString : to_ns(format_string::expand(replacementString, captures))];
	}

	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard writeObjects:@[ [array componentsJoinedByString:@"\n"] ]];
}

- (void)copyEntireLines:(BOOL)entireLines withFilename:(BOOL)withFilename
{
	NSMutableArray* array = [NSMutableArray array];

	for(FFResultNode* item in _resultsViewController.selectedResults)
	{
		OakDocumentMatch* m = item.match;
		std::string str = to_s(m.excerpt);

		if(!entireLines)
			str = str.substr(m.first - m.excerptOffset, m.last - m.first);
		else if(str.size() && str.back() == '\n')
			str.erase(str.size()-1);

		if(withFilename)
			str = text::format("%s:%lu\t", [item.path UTF8String], m.lineNumber + 1) + str;

		[array addObject:to_ns(str)];
	}

	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard writeObjects:@[ [array componentsJoinedByString:@"\n"] ]];
}

- (void)copy:(id)sender                          { [self copyEntireLines:YES withFilename:NO ]; }
- (void)copyMatchingParts:(id)sender             { [self copyEntireLines:NO  withFilename:NO ]; }
- (void)copyMatchingPartsWithFilename:(id)sender { [self copyEntireLines:NO  withFilename:YES]; }
- (void)copyEntireLines:(id)sender               { [self copyEntireLines:YES withFilename:NO ]; }
- (void)copyEntireLinesWithFilename:(id)sender   { [self copyEntireLines:YES withFilename:YES]; }

// =====================
// = Check/Uncheck All =
// =====================

- (void)allMatchesSetExclude:(BOOL)exclude
{
	_results.excluded = exclude;
}

- (IBAction)checkAll:(id)sender
{
	[self allMatchesSetExclude:NO];
}

- (IBAction)uncheckAll:(id)sender
{
	[self allMatchesSetExclude:YES];
}

- (BOOL)validateMenuItem:(NSMenuItem*)aMenuItem
{
	BOOL res = YES;
	static std::set<SEL> const copyActions = { @selector(copy:), @selector(copyReplacements:), @selector(copyMatchingParts:), @selector(copyMatchingPartsWithFilename:), @selector(copyEntireLines:), @selector(copyEntireLinesWithFilename:) };
	if(copyActions.find(aMenuItem.action) != copyActions.end())
		res = _results.countOfLeafs != 0;
	else if(aMenuItem.action == @selector(checkAll:))
		res = _countOfExcludedMatches > _countOfExcludedReadOnlyMatches;
	else if(aMenuItem.action == @selector(uncheckAll:) )
		res = _countOfExcludedMatches - _countOfExcludedReadOnlyMatches < _countOfMatches - _countOfReadOnlyMatches;
	else if(aMenuItem.action == @selector(toggleSearchHiddenFolders:))
		aMenuItem.state = self.searchHiddenFolders ? NSControlStateValueOn : NSControlStateValueOff;
	else if(aMenuItem.action == @selector(toggleSearchFolderLinks:))
		aMenuItem.state = self.searchFolderLinks ? NSControlStateValueOn : NSControlStateValueOff;
	else if(aMenuItem.action == @selector(toggleSearchFileLinks:))
		aMenuItem.state = self.searchFileLinks ? NSControlStateValueOn : NSControlStateValueOff;
	else if(aMenuItem.action == @selector(toggleSearchBinaryFiles:))
		aMenuItem.state = self.searchBinaryFiles ? NSControlStateValueOn : NSControlStateValueOff;
	else if(aMenuItem.action == @selector(goToParentFolder:))
		res = self.searchFolder != nil || _searchTarget == FFSearchTargetFileBrowserItems && CommonAncestor(_fileBrowserItems);
	else if(aMenuItem.action == @selector(goBack:))
		res = [_wherePopUpButton.menu indexOfItemWithTarget:self andAction:aMenuItem.action] != -1;
	else if(aMenuItem.action == @selector(goForward:))
		res = [_wherePopUpButton.menu indexOfItemWithTarget:self andAction:aMenuItem.action] != -1 || _searchTarget == FFSearchTargetOther && _otherFolder;
	return res;
}
@end
