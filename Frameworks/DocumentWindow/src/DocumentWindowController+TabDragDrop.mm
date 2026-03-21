#import "DocumentWindowController+Private.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation DocumentWindowController (TabDragDrop)
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

- (IBAction)selectNextTab:(id)sender            { self.selectedTabIndex = (self.selectedTabIndex + 1) % self.documents.count;                    [self openAndSelectDocument:self.documents[self.selectedTabIndex] activate:YES]; }
- (IBAction)selectPreviousTab:(id)sender        { self.selectedTabIndex = (self.selectedTabIndex + self.documents.count - 1) % self.documents.count; [self openAndSelectDocument:self.documents[self.selectedTabIndex] activate:YES]; }
- (IBAction)takeSelectedTabIndexFrom:(id)sender { self.selectedTabIndex = [sender tag];                                                  [self openAndSelectDocument:self.documents[self.selectedTabIndex] activate:YES]; }
@end
#pragma clang diagnostic pop
