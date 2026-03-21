#import "DocumentWindowController+Private.h"
#import <OakAppKit/NSMenuItem Additions.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation DocumentWindowController (ShowTabsMenu)
- (void)updateShowTabMenu:(NSMenu*)aMenu
{
	if(![self.window isKeyWindow])
	{
		[aMenu addItemWithTitle:@"No Tabs" action:@selector(nop:) keyEquivalent:@""];
		return;
	}

	int i = 0;
	for(OakDocument* document in self.documents)
	{
		NSMenuItem* item = [aMenu addItemWithTitle:document.displayName action:@selector(takeSelectedTabIndexFrom:) keyEquivalent:i < 8 ? [NSString stringWithFormat:@"%c", '1' + i] : @""];
		item.tag     = i;
		item.toolTip = [document.path stringByAbbreviatingWithTildeInPath];
		if(aMenu.propertiesToUpdate & NSMenuPropertyItemImage)
		{
			item.image = [document.icon copy];
			item.image.size = NSMakeSize(16, 16);
		}
		if(i == self.selectedTabIndex)
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
		item.tag     = self.documents.count-1;
		item.toolTip = self.documents.lastObject.displayName;
	}
}
@end
#pragma clang diagnostic pop
