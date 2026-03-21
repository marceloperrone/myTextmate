#import "DocumentWindowController+Private.h"
#import <OakFoundation/NSString Additions.h>
#import <OakSystem/application.h>
#import <io/path.h>
#import <ns/ns.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

NSUInteger DisableSessionSavingCount = 0;

@implementation DocumentWindowController (Session)
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
	for(OakDocument* document in self.documents)
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
@end
#pragma clang diagnostic pop
