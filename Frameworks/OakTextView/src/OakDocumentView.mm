#import "OakDocumentView.h"
// GutterView removed — line numbers stripped for Tahoe compatibility

// OTVStatusBar replaced by SwiftUI StatusBarView (via StatusBarViewModel)
#import <OakFoundation/OakFindProtocol.h>
#import <document/OakDocument.h>
#import <file/type.h>
#import <text/ctype.h>
#import <text/parse.h>
#import <ns/ns.h>
#import <oak/debug.h>
#import <bundles/bundles.h>
#import <settings/settings.h>
#import <OakFoundation/NSString Additions.h>
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakAppKit/OakToolTip.h>
#import <OakAppKit/OakPasteboardChooser.h>
#import <OakAppKit/OakPasteboard.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <BundleMenu/BundleMenu.h>

static NSString* const kUserDefaultsLineNumberScaleFactorKey = @"lineNumberScaleFactor";
static NSString* const kUserDefaultsLineNumberFontNameKey    = @"lineNumberFontName";

// MARK: - FindBarFindServer (OakFindServerProtocol bridge)

@interface FindBarFindServer : NSObject <OakFindServerProtocol>
@property (nonatomic, weak) NSObject* findBarModel;
@property (nonatomic) find_operation_t findOperation;
@property (nonatomic) find::options_t findOptions;
@property (nonatomic) NSString* findString;
@property (nonatomic) NSString* replaceString;
@end

@implementation FindBarFindServer
- (void)didFind:(NSUInteger)aNumber occurrencesOf:(NSString*)aFindString atPosition:(text::pos_t const&)aPosition wrapped:(BOOL)didWrap
{
	[_findBarModel setValue:@(aNumber) forKey:@"matchCount"];
}

- (void)didReplace:(NSUInteger)aNumber occurrencesOf:(NSString*)aFindString with:(NSString*)aReplacementString
{
	// After replace, re-trigger a count to update the match display
	[_findBarModel setValue:@(aNumber) forKey:@"matchCount"];
}
@end

// MARK: - OakDocumentView

@interface OakDocumentView () <NSAccessibilityGroup>
{

	NSScrollView* textScrollView;

	NSMutableArray* topAuxiliaryViews;
	NSMutableArray* bottomAuxiliaryViews;

	NSObject* statusBarModel;
	id _documentModel;
	NSObject* findBarModel;
	NSView* findBarView;

	IBOutlet NSPanel* tabSizeSelectorPanel;
}
@property (nonatomic, readonly) NSView* statusBar;
@property (nonatomic) NSArray* observedKeys;
- (void)updateStyle;
@end

@implementation OakDocumentView
@synthesize documentModel = _documentModel;

- (id)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		self.accessibilityRole  = NSAccessibilityGroupRole;
		self.accessibilityLabel = @"Editor";

		_textView = [[OakTextView alloc] initWithFrame:NSZeroRect];
		_textView.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;

		textScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
		textScrollView.hasVerticalScroller               = YES;
		textScrollView.verticalScrollElasticity          = NSScrollElasticityAllowed;
		textScrollView.hasHorizontalScroller             = YES;
		textScrollView.autohidesScrollers                = YES;
		textScrollView.borderType                        = NSNoBorder;
		textScrollView.documentView                      = _textView;

		statusBarModel = [[NSClassFromString(@"StatusBarViewModel") alloc] init];
		[statusBarModel setValue:self forKey:@"delegate"];
		[statusBarModel setValue:self forKey:@"target"];
		_statusBar = [statusBarModel valueForKey:@"hostingView"];

		_documentModel = [[NSClassFromString(@"DocumentModel") alloc] init];

		OakAddAutoLayoutViewsToSuperview(@[ textScrollView, _statusBar ], self);
		OakSetupKeyViewLoop(@[ self, _textView, _statusBar ]);

		self.document = [OakDocument documentWithString:@"" fileType:@"text.plain" customName:@"placeholder"];

		self.observedKeys = @[ @"selectionString", @"symbol", @"themeUUID" ];
		for(NSString* keyPath in self.observedKeys)
			[_textView addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionInitial context:NULL];
	}
	return self;
}

- (void)updateConstraints
{
	[self removeConstraints:[self constraints]];
	[super updateConstraints];

	NSMutableArray* stackedViews = [NSMutableArray array];
	[stackedViews addObjectsFromArray:topAuxiliaryViews];
	[stackedViews addObject:textScrollView];
	[stackedViews addObjectsFromArray:bottomAuxiliaryViews];

	if(_statusBar)
	{
		[stackedViews addObject:_statusBar];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_statusBar]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_statusBar)]];
	}

	[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[textScrollView(>=100)]|" options:NSLayoutFormatAlignAllTop|NSLayoutFormatAlignAllBottom metrics:nil views:NSDictionaryOfVariableBindings(textScrollView)]];
	[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[topView]" options:0 metrics:nil views:@{ @"topView": stackedViews[0] }]];
	[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[bottomView]|" options:0 metrics:nil views:@{ @"bottomView": [stackedViews lastObject] }]];

	for(size_t i = 0; i < [stackedViews count]-1; ++i)
		[self addConstraint:[NSLayoutConstraint constraintWithItem:stackedViews[i] attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:stackedViews[i+1] attribute:NSLayoutAttributeTop multiplier:1 constant:0]];

	NSArray* array[] = { topAuxiliaryViews, bottomAuxiliaryViews };
	for(NSArray* views : array)
	{
		for(NSView* view in views)
			[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(view)]];
	}
}

- (void)setHideStatusBar:(BOOL)flag
{
	if(_hideStatusBar == flag)
		return;

	_hideStatusBar = flag;
	if(_hideStatusBar)
	{
		[_statusBar removeFromSuperview];
		statusBarModel = nil;
		_statusBar = nil;
	}
	else
	{
		statusBarModel = [[NSClassFromString(@"StatusBarViewModel") alloc] init];
		[statusBarModel setValue:self forKey:@"delegate"];
		[statusBarModel setValue:self forKey:@"target"];
		_statusBar = [statusBarModel valueForKey:@"hostingView"];

		OakAddAutoLayoutViewsToSuperview(@[ _statusBar ], self);

		// Restore current property values
		[statusBarModel setValue:[_textView valueForKey:@"selectionString"] forKey:@"selectionString"];
		[statusBarModel setValue:_textView.symbol forKey:@"symbolName"];
		if(self.document)
		{
			NSString* fileType = self.document.fileType;
			[statusBarModel setValue:fileType forKey:@"fileType"];
			for(auto const& item : bundles::query(bundles::kFieldGrammarScope, to_s(fileType)))
				[statusBarModel setValue:[NSString stringWithCxxString:item->name()] forKey:@"grammarName"];
			[statusBarModel setValue:@(self.document.tabSize) forKey:@"tabSize"];
			[statusBarModel setValue:@(self.document.softTabs) forKey:@"softTabs"];
		}
	}
	[self setNeedsUpdateConstraints:YES];
}

- (CGFloat)lineHeight
{
	return round(std::min(1.5 * [_textView.font capHeight], [_textView.font ascender] - [_textView.font descender] + [_textView.font leading]));
}

- (IBAction)makeTextLarger:(id)sender
{
	_textView.fontScaleFactor += 0.1;
}

- (IBAction)makeTextSmaller:(id)sender
{
	if(_textView.fontScaleFactor > 0.1)
		_textView.fontScaleFactor -= 0.1;
}

- (IBAction)makeTextStandardSize:(id)sender
{
	_textView.fontScaleFactor = 1;
}

- (void)changeFont:(id)sender
{
	NSFont* defaultFont = [NSFont userFixedPitchFontOfSize:0];
	if(NSFont* newFont = [sender convertFont:_textView.font ?: defaultFont])
	{
		std::string fontName = [newFont.fontName isEqualToString:defaultFont.fontName] ? NULL_STR : to_s(newFont.fontName);
		settings_t::set(kSettingsFontNameKey, fontName);
		settings_t::set(kSettingsFontSizeKey, [newFont pointSize]);
		_textView.font = newFont;
	}
}

- (void)observeValueForKeyPath:(NSString*)aKeyPath ofObject:(id)observableController change:(NSDictionary*)changeDictionary context:(void*)userData
{
	if([aKeyPath isEqualToString:@"selectionString"])
	{
		NSString* str = [_textView valueForKey:@"selectionString"];
		[statusBarModel setValue:str forKey:@"selectionString"];
		[_documentModel setValue:str forKey:@"selectionString"];
	}
	else if([aKeyPath isEqualToString:@"symbol"])
	{
		[statusBarModel setValue:_textView.symbol forKey:@"symbolName"];
		[_documentModel setValue:_textView.symbol forKey:@"symbolName"];
	}
	else if([aKeyPath isEqualToString:@"fileType"])
	{
		NSString* fileType = self.document.fileType;
		[statusBarModel setValue:fileType forKey:@"fileType"];
		[_documentModel setValue:fileType forKey:@"fileType"];
		for(auto const& item : bundles::query(bundles::kFieldGrammarScope, to_s(fileType)))
		{
			NSString* name = [NSString stringWithCxxString:item->name()];
			[statusBarModel setValue:name forKey:@"grammarName"];
			[_documentModel setValue:name forKey:@"grammarName"];
		}
	}
	else if([aKeyPath isEqualToString:@"tabSize"])
	{
		[statusBarModel setValue:@(self.document.tabSize) forKey:@"tabSize"];
		[_documentModel setValue:@(self.document.tabSize) forKey:@"tabSize"];
	}
	else if([aKeyPath isEqualToString:@"softTabs"])
	{
		[statusBarModel setValue:@(self.document.softTabs) forKey:@"softTabs"];
		[_documentModel setValue:@(self.document.softTabs) forKey:@"softTabs"];
	}
	else if([aKeyPath isEqualToString:@"themeUUID"])
	{
		[_documentModel setValue:[_textView valueForKey:@"themeUUID"] forKey:@"themeUUID"];
		[self updateStyle];
	}
}

- (void)dealloc
{
	for(NSString* keyPath in self.observedKeys)
		[_textView removeObserver:self forKeyPath:keyPath];
	[NSNotificationCenter.defaultCenter removeObserver:self];

	self.document = nil;
}

- (void)setDocument:(OakDocument*)aDocument
{
	NSArray* const documentKeys = @[ @"fileType", @"tabSize", @"softTabs" ];

	OakDocument* oldDocument = self.document;
	if(oldDocument)
	{
		for(NSString* key in documentKeys)
			[oldDocument removeObserver:self forKeyPath:key];
		[NSNotificationCenter.defaultCenter removeObserver:self name:OakDocumentMarksDidChangeNotification object:oldDocument];
	}

	if(aDocument)
		[aDocument loadModalForWindow:self.window completionHandler:nullptr];

	if(_document = aDocument)
	{
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(documentMarksDidChange:) name:OakDocumentMarksDidChangeNotification object:self.document];
		for(NSString* key in documentKeys)
			[self.document addObserver:self forKeyPath:key options:NSKeyValueObservingOptionInitial context:nullptr];
	}

	[_textView setDocument:self.document];
	[self updateStyle];

	if(oldDocument)
		[oldDocument close];
}

- (void)updateStyle
{
	if(theme_ptr theme = _textView.theme)
	{
		[textScrollView setBackgroundColor:[NSColor colorWithCGColor:theme->background(to_s(self.document.fileType))]];
		[textScrollView setScrollerKnobStyle:theme->is_dark() ? NSScrollerKnobStyleLight : NSScrollerKnobStyleDark];

		[_textView setIbeamCursor:NSCursor.IBeamCursor];

		self.window.backgroundColor = [NSColor colorWithCGColor:theme->background(to_s(self.document.fileType))];
	}
}

- (BOOL)validateMenuItem:(NSMenuItem*)aMenuItem
{
	if(NO) { /* toggleLineNumbers removed */ }
	else if([aMenuItem action] == @selector(takeTabSizeFrom:))
		[aMenuItem setState:_textView.tabSize == [aMenuItem tag] ? NSControlStateValueOn : NSControlStateValueOff];
	else if([aMenuItem action] == @selector(showTabSizeSelectorPanel:))
	{
		static NSInteger const predefined[] = { 2, 3, 4, 8 };
		if(oak::contains(std::begin(predefined), std::end(predefined), _textView.tabSize))
		{
			[aMenuItem setTitle:@"Other…"];
			[aMenuItem setState:NSControlStateValueOff];
		}
		else
		{
			[aMenuItem setDynamicTitle:[NSString stringWithFormat:@"Other (%zd)…", _textView.tabSize]];
			[aMenuItem setState:NSControlStateValueOn];
		}
	}
	else if([aMenuItem action] == @selector(setIndentWithTabs:))
		[aMenuItem setState:_textView.softTabs ? NSControlStateValueOff : NSControlStateValueOn];
	else if([aMenuItem action] == @selector(setIndentWithSpaces:))
		[aMenuItem setState:_textView.softTabs ? NSControlStateValueOn : NSControlStateValueOff];
	else if([aMenuItem action] == @selector(takeGrammarUUIDFrom:))
	{
		NSString* uuidString = [aMenuItem representedObject];
		if(bundles::item_ptr bundleItem = bundles::lookup(to_s(uuidString)))
		{
			bool selectedGrammar = to_s(self.document.fileType) == bundleItem->value_for_field(bundles::kFieldGrammarScope);
			[aMenuItem setState:selectedGrammar ? NSControlStateValueOn : NSControlStateValueOff];
		}
	}
	return YES;
}

// ===================
// = Auxiliary Views =
// ===================

- (void)addAuxiliaryView:(NSView*)aView atEdge:(NSRectEdge)anEdge
{
	topAuxiliaryViews    = topAuxiliaryViews    ?: [NSMutableArray new];
	bottomAuxiliaryViews = bottomAuxiliaryViews ?: [NSMutableArray new];
	if(anEdge == NSMinYEdge)
			[bottomAuxiliaryViews addObject:aView];
	else	[topAuxiliaryViews addObject:aView];
	OakAddAutoLayoutViewsToSuperview(@[ aView ], self);
	[self setNeedsUpdateConstraints:YES];
}

- (void)removeAuxiliaryView:(NSView*)aView
{
	if([topAuxiliaryViews containsObject:aView])
		[topAuxiliaryViews removeObject:aView];
	else if([bottomAuxiliaryViews containsObject:aView])
		[bottomAuxiliaryViews removeObject:aView];
	else
		return;
	[aView removeFromSuperview];
	[self setNeedsUpdateConstraints:YES];
}

// ================
// = Find Bar =
// ================

- (BOOL)isFindBarVisible
{
	return findBarView != nil;
}

- (void)showFindBar
{
	if(findBarView)
	{
		[self.window makeFirstResponder:findBarView];
		return;
	}

	findBarModel = [[NSClassFromString(@"FindBarModel") alloc] init];
	[findBarModel setValue:self forKey:@"target"];

	// Pre-populate from find pasteboard
	OakPasteboardEntry* entry = [OakPasteboard.findPasteboard current];
	if(entry.string.length)
		[findBarModel setValue:entry.string forKey:@"findString"];

	// Sync options from pasteboard
	[findBarModel setValue:@(entry.regularExpression) forKey:@"regularExpression"];
	[findBarModel setValue:@(!!(entry.findOptions & find::ignore_case)) forKey:@"ignoreCase"];
	[findBarModel setValue:@(!!(entry.findOptions & find::wrap_around)) forKey:@"wrapAround"];

	// Populate replace from replace pasteboard
	OakPasteboardEntry* replaceEntry = [OakPasteboard.replacePasteboard current];
	if(replaceEntry.string.length)
		[findBarModel setValue:replaceEntry.string forKey:@"replaceString"];

	findBarView = [findBarModel valueForKey:@"hostingView"];
	[self addAuxiliaryView:findBarView atEdge:NSMaxYEdge];
	[self.window makeFirstResponder:findBarView];
}

- (void)showFindBarWithSelection
{
	NSString* selection = [_textView accessibilitySelectedText];
	[self showFindBar];
	if(selection.length > 0 && [selection rangeOfString:@"\n"].location == NSNotFound)
		[findBarModel setValue:selection forKey:@"findString"];
}

- (void)hideFindBar
{
	if(!findBarView)
		return;

	[self removeAuxiliaryView:findBarView];
	findBarView = nil;
	findBarModel = nil;
	[self.window makeFirstResponder:_textView];
}

- (find::options_t)findBarOptions
{
	find::options_t options = find::none;
	if([[findBarModel valueForKey:@"regularExpression"] boolValue])
		options |= find::regular_expression;
	if([[findBarModel valueForKey:@"ignoreCase"] boolValue])
		options |= find::ignore_case;
	if([[findBarModel valueForKey:@"wrapAround"] boolValue])
		options |= find::wrap_around;
	return options;
}

- (void)findBarUpdatePasteboard
{
	NSString* findString = [findBarModel valueForKey:@"findString"];
	if(findString.length == 0)
		return;

	NSMutableDictionary* options = [NSMutableDictionary dictionary];
	if([[findBarModel valueForKey:@"regularExpression"] boolValue])
		options[OakFindRegularExpressionOption] = @YES;
	if([[findBarModel valueForKey:@"ignoreCase"] boolValue])
		options[@"ignoreCase"] = @YES;

	[OakPasteboard.findPasteboard addEntryWithString:findString options:options];
}

- (void)findBarFindNext:(id)sender
{
	[self findBarUpdatePasteboard];

	FindBarFindServer* server = [FindBarFindServer new];
	server.findBarModel  = findBarModel;
	server.findString    = [findBarModel valueForKey:@"findString"];
	server.replaceString = [findBarModel valueForKey:@"replaceString"];
	server.findOperation = kFindOperationFind;
	server.findOptions   = [self findBarOptions];

	[(id<OakFindClientProtocol>)_textView performFindOperation:server];
}

- (void)findBarFindPrevious:(id)sender
{
	[self findBarUpdatePasteboard];

	FindBarFindServer* server = [FindBarFindServer new];
	server.findBarModel  = findBarModel;
	server.findString    = [findBarModel valueForKey:@"findString"];
	server.replaceString = [findBarModel valueForKey:@"replaceString"];
	server.findOperation = kFindOperationFind;
	server.findOptions   = [self findBarOptions] | find::backwards;

	[(id<OakFindClientProtocol>)_textView performFindOperation:server];
}

- (void)findBarReplace:(id)sender
{
	NSString* replaceString = [findBarModel valueForKey:@"replaceString"];
	[OakPasteboard.replacePasteboard addEntryWithString:replaceString ?: @""];
	[self findBarUpdatePasteboard];

	FindBarFindServer* server = [FindBarFindServer new];
	server.findBarModel  = findBarModel;
	server.findString    = [findBarModel valueForKey:@"findString"];
	server.replaceString = replaceString;
	server.findOperation = kFindOperationReplaceAndFind;
	server.findOptions   = [self findBarOptions];

	[(id<OakFindClientProtocol>)_textView performFindOperation:server];
}

- (void)findBarReplaceAll:(id)sender
{
	NSString* replaceString = [findBarModel valueForKey:@"replaceString"];
	[OakPasteboard.replacePasteboard addEntryWithString:replaceString ?: @""];
	[self findBarUpdatePasteboard];

	FindBarFindServer* server = [FindBarFindServer new];
	server.findBarModel  = findBarModel;
	server.findString    = [findBarModel valueForKey:@"findString"];
	server.replaceString = replaceString;
	server.findOperation = kFindOperationReplaceAll;
	server.findOptions   = [self findBarOptions] | find::all_matches;

	[(id<OakFindClientProtocol>)_textView performFindOperation:server];
}

- (void)findBarDismiss:(id)sender
{
	[self hideFindBar];
}

- (void)findBarDidChangeSearchString:(id)sender
{
	// Count matches when search string changes
	NSString* findString = [findBarModel valueForKey:@"findString"];
	if(findString.length == 0)
	{
		[findBarModel setValue:@0 forKey:@"matchCount"];
		return;
	}

	FindBarFindServer* server = [FindBarFindServer new];
	server.findBarModel  = findBarModel;
	server.findString    = findString;
	server.replaceString = @"";
	server.findOperation = kFindOperationCount;
	server.findOptions   = [self findBarOptions] | find::all_matches;

	[(id<OakFindClientProtocol>)_textView performFindOperation:server];
}

- (void)findBarDidChangeOptions:(id)sender
{
	// Re-count when options change
	[self findBarDidChangeSearchString:sender];
}

// ======================
// = Pasteboard History =
// ======================

- (void)showClipboardHistory:(id)sender
{
	OakPasteboardChooser* chooser = [OakPasteboardChooser sharedChooserForPasteboard:OakPasteboard.generalPasteboard];
	chooser.action = @selector(paste:);
	[chooser showWindowRelativeToFrame:[self.window convertRectToScreen:[_textView convertRect:[_textView visibleRect] toView:nil]]];
}

- (void)showFindHistory:(id)sender
{
	OakPasteboardChooser* chooser = [OakPasteboardChooser sharedChooserForPasteboard:OakPasteboard.findPasteboard];
	chooser.action          = @selector(findNext:);
	chooser.alternateAction = @selector(orderFrontFindPanelForProject:);
	[chooser showWindowRelativeToFrame:[self.window convertRectToScreen:[_textView convertRect:[_textView visibleRect] toView:nil]]];
}

// ==================
// = Symbol Chooser =
// ==================

- (void)selectAndCenter:(NSString*)aSelectionString
{
	_textView.selectionString = aSelectionString;
	[_textView centerSelectionInVisibleArea:self];
}

// =======================
// = Status bar delegate =
// =======================

- (void)takeGrammarUUIDFrom:(id)sender
{
	if(bundles::item_ptr item = bundles::lookup(to_s([sender representedObject])))
		[_textView performBundleItem:item];
}

- (void)goToSymbol:(id)sender
{
	[self selectAndCenter:[sender representedObject]];
}

- (void)showSymbolSelector:(NSPopUpButton*)symbolPopUp
{
	NSMenu* symbolMenu = symbolPopUp.menu;
	[symbolMenu removeAllItems];

	text::selection_t sel(to_s(_textView.selectionString));
	text::pos_t caret = sel.last().max();

	__block NSInteger index = 0;
	[self.document enumerateSymbolsUsingBlock:^(text::pos_t const& pos, NSString* symbol){
		if([symbol isEqualToString:@"-"])
		{
			[symbolMenu addItem:[NSMenuItem separatorItem]];
		}
		else
		{
			NSUInteger indent = 0;
			while(indent < symbol.length && [symbol characterAtIndex:indent] == 0x2003) // Em-space
				++indent;

			NSMenuItem* item = [symbolMenu addItemWithTitle:[symbol substringFromIndex:indent] action:@selector(goToSymbol:) keyEquivalent:@""];
			[item setIndentationLevel:indent];
			[item setTarget:self];
			[item setRepresentedObject:to_ns(pos)];
		}

		if(pos <= caret)
			++index;
	}];

	if(symbolMenu.numberOfItems == 0)
		[symbolMenu addItemWithTitle:@"No symbols to show for current document." action:@selector(nop:) keyEquivalent:@""];

	[symbolPopUp selectItemAtIndex:(index ? index-1 : 0)];
}

- (void)showBundlesMenu:(id)sender
{
	NSPopUpButton* popup = [statusBarModel valueForKey:@"bundleItemsPopUp"];
	if(popup)
		[popup performClick:self];
	else
		NSBeep();
}

- (void)showBundleItemSelector:(NSPopUpButton*)bundleItemsPopUp
{
	NSMenu* bundleItemsMenu = bundleItemsPopUp.menu;
	[bundleItemsMenu removeAllItems];

	std::multimap<std::string, bundles::item_ptr, text::less_t> ordered;
	for(auto item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeBundle))
		ordered.emplace(item->name(), item);

	NSMenuItem* selectedItem = nil;
	for(auto pair : ordered)
	{
		bool selectedGrammar = false;
		for(auto item : bundles::query(bundles::kFieldGrammarScope, to_s(self.document.fileType), scope::wildcard, bundles::kItemTypeGrammar, pair.second->uuid(), true, true))
			selectedGrammar = true;
		if(!selectedGrammar && pair.second->hidden_from_user() || pair.second->menu().empty())
			continue;

		NSMenuItem* menuItem = [bundleItemsMenu addItemWithTitle:[NSString stringWithCxxString:pair.first] action:NULL keyEquivalent:@""];
		menuItem.submenu = [[NSMenu alloc] initWithTitle:[NSString stringWithCxxString:pair.second->uuid()]];
		menuItem.submenu.delegate = BundleMenuDelegate.sharedInstance;

		if(selectedGrammar)
		{
			[menuItem setState:NSControlStateValueOn];
			selectedItem = menuItem;
		}
	}

	if(ordered.empty())
		[bundleItemsMenu addItemWithTitle:@"No Bundles Loaded" action:@selector(nop:) keyEquivalent:@""];

	if(selectedItem)
		[bundleItemsPopUp selectItem:selectedItem];
}

- (NSUInteger)tabSize
{
	return _textView.tabSize;
}

- (void)setTabSize:(NSUInteger)newTabSize
{
	_textView.tabSize = newTabSize;
	settings_t::set(kSettingsTabSizeKey, (size_t)newTabSize, to_s(self.document.fileType));
}

- (IBAction)takeTabSizeFrom:(id)sender
{
	ASSERT([sender respondsToSelector:@selector(tag)]);
	if([sender tag] > 0)
		self.tabSize = [sender tag];
}

- (IBAction)setIndentWithSpaces:(id)sender
{
	_textView.softTabs = YES;
	settings_t::set(kSettingsSoftTabsKey, true, to_s(self.document.fileType));
}

- (IBAction)setIndentWithTabs:(id)sender
{
	_textView.softTabs = NO;
	settings_t::set(kSettingsSoftTabsKey, false, to_s(self.document.fileType));
}

- (IBAction)showTabSizeSelectorPanel:(id)sender
{
	if(!tabSizeSelectorPanel)
		[[NSBundle bundleForClass:[self class]] loadNibNamed:@"TabSizeSetting" owner:self topLevelObjects:NULL];
	[tabSizeSelectorPanel makeKeyAndOrderFront:self];
}


// ============
// = Printing =
// ============

- (void)printDocument:(id)sender
{
	[self.document runPrintOperationModalForWindow:self.window fontName:_textView.font.fontName];
}
@end
