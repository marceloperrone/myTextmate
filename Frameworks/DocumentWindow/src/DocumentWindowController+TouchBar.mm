#import "DocumentWindowController+Private.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

static NSTouchBarItemIdentifier kTouchBarCustomizationIdentifier = @"com.wonky.works.myTextMate.touch-bar.customization-identifier";
static NSTouchBarItemIdentifier kTouchBarTabNavigationIdentifier = @"com.wonky.works.myTextMate.touch-bar.tab-navigation";
static NSTouchBarItemIdentifier kTouchBarNewTabItemIdentifier    = @"com.wonky.works.myTextMate.touch-bar.new-tab";

static NSTouchBarItemIdentifier kTouchBarFindItemIdentifier      = @"com.wonky.works.myTextMate.touch-bar.find";
static NSTouchBarItemIdentifier kTouchBarFavoritesItemIdentifier = @"com.wonky.works.myTextMate.touch-bar.favorites";

@implementation DocumentWindowController (TouchBar)
- (NSTouchBar*)makeTouchBar
{
	NSTouchBar* bar = [[NSTouchBar alloc] init];
	bar.delegate = self;
	bar.defaultItemIdentifiers = @[
		NSTouchBarItemIdentifierOtherItemsProxy,
		kTouchBarTabNavigationIdentifier,
		kTouchBarNewTabItemIdentifier,

		NSTouchBarItemIdentifierFlexibleSpace,
		kTouchBarFindItemIdentifier,
		kTouchBarFavoritesItemIdentifier,
	];
	bar.customizationIdentifier = kTouchBarCustomizationIdentifier;
	bar.customizationAllowedItemIdentifiers = @[
		kTouchBarTabNavigationIdentifier,
		kTouchBarNewTabItemIdentifier,

		NSTouchBarItemIdentifierFlexibleSpace,
		kTouchBarFindItemIdentifier,
		kTouchBarFavoritesItemIdentifier,
	];
	return bar;
}

- (void)updateTouchBarButtons
{
	self.previousNextTouchBarControl.enabled = self.documents.count > 1;
}

- (NSTouchBarItem*)touchBar:(NSTouchBar*)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
	NSCustomTouchBarItem* res;
	if([identifier isEqualToString:kTouchBarTabNavigationIdentifier])
	{
		if(!self.previousNextTouchBarControl)
		{
			self.previousNextTouchBarControl = [NSSegmentedControl segmentedControlWithImages:@[ [NSImage imageNamed:NSImageNameTouchBarGoBackTemplate], [NSImage imageNamed:NSImageNameTouchBarGoForwardTemplate] ] trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(didClickPreviousNextTouchBarControl:)];
			self.previousNextTouchBarControl.segmentStyle = NSSegmentStyleSeparated;
			self.previousNextTouchBarControl.enabled      = self.documents.count > 1;
		}

		res = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
		res.view = self.previousNextTouchBarControl;
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
@end
#pragma clang diagnostic pop
