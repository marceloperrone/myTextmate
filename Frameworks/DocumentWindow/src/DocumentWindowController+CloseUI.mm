#import "DocumentWindowController+Private.h"
#import <OakAppKit/NSAlert Additions.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation DocumentWindowController (CloseUI)
+ (NSAlert*)saveAlertForDocuments:(NSArray<OakDocument*>*)someDocuments
{
	NSAlert* alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSAlertStyleWarning];
	if(someDocuments.count == 1)
	{
		OakDocument* document = someDocuments.firstObject;
		[alert setMessageText:[NSString stringWithFormat:@"Do you want to save the changes you made in the document \u201c%@\u201d?", document.displayName]];
		[alert setInformativeText:@"Your changes will be lost if you don\u2019t save them."];
		[alert addButtons:@"Save", @"Cancel", @"Don\u2019t Save", nil];
	}
	else
	{
		NSString* body = @"";
		for(OakDocument* document in someDocuments)
			body = [body stringByAppendingFormat:@"\u2022 \u201c%@\u201d\n", document.displayName];
		[alert setMessageText:@"Do you want to save documents with changes?"];
		[alert setInformativeText:body];
		[alert addButtons:@"Save All", @"Cancel", @"Don\u2019t Save", nil];
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

- (BOOL)windowShouldClose:(id)sender
{
	NSArray<OakDocument*>* documentsToSave = [self.documents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDocumentEdited == YES"]];
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
@end
#pragma clang diagnostic pop
