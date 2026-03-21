#import "DocumentWindowController+Private.h"
#import <MenuBuilder/MenuBuilder.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation DocumentWindowController (TabContextMenu)
- (NSMenu*)tabBarModel:(id)model menuForIndex:(NSNumber*)indexNumber
{
	NSInteger tabIndex = indexNumber.integerValue;
	NSInteger total    = self.documents.count;

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

	for(NSUInteger i = 0; i < self.documents.count; ++i)
	{
		if([self isDocumentSticky:self.documents[i]])
		{
			[otherTabs removeIndex:i];
			[rightSideTabs removeIndex:i];
			[leftSideTabs removeIndex:i];
		}
	}

	SEL closeSingleTabSelector = tabIndex == self.selectedTabIndex ? @selector(performCloseTab:) : @selector(takeTabsToCloseFrom:);
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
		// In fullscreen mode the window's delegate is ignored as a target for menu actions, therefore we have to manually set the target for these menu items (as a workaround for what I can only assume is an OS bug)

		if(!item.target && item.action)
			item.target = [NSApp targetForAction:item.action];
	}
	return menu;
}
@end
#pragma clang diagnostic pop
