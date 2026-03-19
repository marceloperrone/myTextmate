#import "Keys.h"
#import <OakTabBarView/OakTabBarView.h>
#import <BundlesManager/BundlesManager.h>

static NSDictionary* default_settings ()
{
	return @{
		kUserDefaultsHTMLOutputPlacementKey:     @"window",
		kUserDefaultsFileBrowserPlacementKey:    @"right",
		kUserDefaultsShowFileExtensionsKey:      @NO,
		kUserDefaultsDisableBundleUpdatesKey:    @NO,
		kUserDefaultsLicenseOwnerKey:            NSFullUserName(),
		kUserDefaultsLineNumbersKey:             @YES,
		kUserDefaultsCrashReportsContactInfoKey: NSFullUserName() ?: @"Anonymous",
	};
}

static bool register_defaults ()
{
	[NSUserDefaults.standardUserDefaults registerDefaults:default_settings()];
	return true;
}

void RegisterDefaults ()
{
	static bool __attribute__ ((unused)) dummy = register_defaults();
}

// =========
// = Files =
// =========

NSString* const kUserDefaultsDisableSessionRestoreKey            = @"disableSessionRestore";
NSString* const kUserDefaultsDisableNewDocumentAtStartupKey      = @"disableNewDocumentAtStartup";
NSString* const kUserDefaultsDisableNewDocumentAtReactivationKey = @"disableNewDocumentAtReactivation";
NSString* const kUserDefaultsShowFavoritesInsteadOfUntitledKey   = @"showFavoritesInsteadOfUntitled";

// ============
// = Projects =
// ============

NSString* const kUserDefaultsFoldersOnTopKey                   = @"foldersOnTop";
NSString* const kUserDefaultsShowFileExtensionsKey             = @"showFileExtensions";
NSString* const kUserDefaultsInitialFileBrowserURLKey          = @"initialFileBrowserURL";
NSString* const kUserDefaultsFileBrowserPlacementKey           = @"fileBrowserPlacement";
NSString* const kUserDefaultsFileBrowserSingleClickToOpenKey   = @"fileBrowserSingleClickToOpen";
NSString* const kUserDefaultsFileBrowserOpenAnimationDisabled  = @"fileBrowserOpenAnimationDisabled";
NSString* const kUserDefaultsFileBrowserStyleKey               = @"fileBrowserStyle";
NSString* const kUserDefaultsHTMLOutputPlacementKey            = @"htmlOutputPlacement";
NSString* const kUserDefaultsDisableFileBrowserWindowResizeKey = @"disableFileBrowserWindowResize";
NSString* const kUserDefaultsAutoRevealFileKey                 = @"autoRevealFile";
NSString* const kUserDefaultsDisableTabReorderingKey           = @"disableTabReordering";
NSString* const kUserDefaultsDisableTabAutoCloseKey            = @"disableTabAutoClose";
NSString* const kUserDefaultsDisableTabBarCollapsingKey        = @"disableTabBarCollapsing";
NSString* const kUserDefaultsAllowExpandingLinksKey            = @"allowExpandingLinks";
NSString* const kUserDefaultsAllowExpandingPackagesKey         = @"allowExpandingPackages";

// ===========
// = Bundles =
// ===========

// ================
// = Registration =
// ================

NSString* const kUserDefaultsLicenseOwnerKey            = @"licenseOwnerName";

// ==============
// = Appearance =
// ==============

NSString* const kUserDefaultsDisableAntiAliasKey        = @"disableAntiAlias";
NSString* const kUserDefaultsLineNumbersKey             = @"lineNumbers";

// =========
// = Other =
// =========

NSString* const kUserDefaultsFolderSearchFollowLinksKey = @"folderSearchFollowLinks";
NSString* const kUserDefaultsDisableCrashReportingKey   = @"DisableCrashReports";
NSString* const kUserDefaultsCrashReportsContactInfoKey = @"CrashReportsContactInfo";
