#import "DocumentWindowController+Private.h"
#import <OakFoundation/NSString Additions.h>
#import <Preferences/Keys.h>
#import <io/path.h>
#import <ns/ns.h>
#import <kvdb/kvdb.h>
#import <text/types.h>

static NSString* const kUserDefaultsDisableFolderStateRestore = @"disableFolderStateRestore";

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// FileTreeModel (SwiftUI) — forward-declare methods for file browser navigation
@interface NSObject (FileTreeModelMethods_WindowRouting)
- (void)goToURL:(NSURL*)url;
@end

// ==========================================
// = DocumentWindowController helper methods
// = used by OakDocumentController category
// ==========================================

@implementation DocumentWindowController (WindowRouting)
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
		// If we call 'mate -w' in quick succession there is a chance that we have a pending "re-activate the terminal app" when this code is executed, which will make 'isActive' return 'YES' but shortly after, our application will become inactive. For this reason, we monitor the NSApplicationDidResignActiveNotification for 200 ms and re-activate TextMate if we see the notification.

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
@end

// ==========================================
// = OakDocumentController window routing   =
// ==========================================

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
	// = Find window with project folder closest to document's parent =
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
	// = Use frontmost window if a "scratch" window =
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
#pragma clang diagnostic pop
