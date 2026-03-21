#import "DocumentWindowController+Private.h"
#import <OakAppKit/NSMenuItem Additions.h>
#import <oak/oak.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation DocumentWindowController (MenuValidation)
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
		[menuItem setDynamicTitle:active ? [NSString stringWithFormat:@"New File in \u201c%@\u201d", [NSFileManager.defaultManager displayNameAtPath:dirURL.path]] : @"New File"];
	}
	else if(delegateToFileBrowser.find([menuItem action]) != delegateToFileBrowser.end())
		active = self.fileBrowserVisible && [self.fileBrowser validateMenuItem:menuItem];
	else if([menuItem action] == @selector(moveDocumentToNewWindow:))
		active = self.documents.count > 1;
	else if([menuItem action] == @selector(selectNextTab:) || [menuItem action] == @selector(selectPreviousTab:))
		active = self.documents.count > 1;
	else if([menuItem action] == @selector(revealFileInProject:) || [menuItem action] == @selector(revealFileInProjectByExpandingAncestors:))
	{
		active = self.selectedDocument.path != nil;
		[menuItem setDynamicTitle:active ? [NSString stringWithFormat:@"Select \u201c%@\u201d", self.selectedDocument.displayName] : @"Select Document"];
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
		active = self.documents.count > 1;
	else if([menuItem action] == @selector(performCloseTabsToTheRight:))
		active = self.selectedTabIndex + 1 < self.documents.count;
	else if([menuItem action] == @selector(performCloseTabsToTheLeft:))
		active = self.selectedTabIndex > 0;
	else if([menuItem action] == @selector(performBundleItemWithUUIDStringFrom:))
		active = [self.textView validateMenuItem:menuItem];

	SEL tabBarActions[] = { @selector(performCloseTab:), @selector(takeNewTabIndexFrom::), @selector(takeTabsToCloseFrom:), @selector(takeTabsToTearOffFrom:), @selector(toggleSticky:) };
	if(oak::contains(std::begin(tabBarActions), std::end(tabBarActions), [menuItem action]))
	{
		if(NSIndexSet* indexSet = [self tryObtainIndexSetFrom:menuItem])
		{
			active = [indexSet count] != 0;
			if(active && [menuItem action] == @selector(toggleSticky:))
				[menuItem setState:[self isDocumentSticky:self.documents[indexSet.firstIndex]] ? NSControlStateValueOn : NSControlStateValueOff];
		}
	}

	return active;
}
@end
#pragma clang diagnostic pop
