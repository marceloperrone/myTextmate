#import "DocumentWindowController+Private.h"
#import <OakFoundation/NSString Additions.h>
#import <file/path_info.h>
#import <io/entries.h>
#import <regexp/glob.h>
#import <settings/settings.h>
#import <text/format.h>
#import <text/parse.h>
#import <ns/ns.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation DocumentWindowController (ScopeAttributes)
- (void)updateExternalAttributes
{
	struct attribute_rule_t { std::string attribute; path::glob_t glob; std::string group; };
	static auto const rules = new std::vector<attribute_rule_t>
	{
		{ "attr.project.ninja",   "build.ninja",    "build"   },
		{ "attr.project.make",    "Makefile",       "build"   },
		{ "attr.project.xcode",   "*.xcodeproj",    "build"   },
		{ "attr.project.rake",    "Rakefile",       "build"   },
		{ "attr.project.ant",     "build.xml",      "build"   },
		{ "attr.project.cmake",   "CMakeLists.txt", "build"   },
		{ "attr.project.maven",   "pom.xml",        "build"   },
		{ "attr.project.scons",   "SConstruct",     "build"   },
		{ "attr.project.lein",    "project.clj",    "build"   },
		{ "attr.project.cargo",   "Cargo.toml",     "build"   },
		{ "attr.project.swift",   "Package.swift",  "build"   },
		{ "attr.project.vagrant", "Vagrantfile",    NULL_STR  },
		{ "attr.project.jekyll",  "_config.yml",    NULL_STR  },
		{ "attr.project.rave",    "default.rave",   NULL_STR  },
		{ "attr.test.rspec",      ".rspec",         "test"    },
	};

	_externalScopeAttributes.clear();
	if(!self.selectedDocument && !_projectPath)
		return;

	std::string const projectDir   = to_s(_projectPath ?: NSHomeDirectory());
	std::string const documentPath = self.selectedDocument.path ? to_s(self.selectedDocument.path) : path::join(projectDir, "dummy");

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{

		std::vector<std::string> res;
		std::set<std::string> groups;
		std::string dir = documentPath;
		do {

			dir = path::parent(dir);
			auto entries = path::entries(dir);

			for(auto rule : *rules)
			{
				if(groups.find(rule.group) != groups.end())
					continue;

				for(auto entry : entries)
				{
					if(rule.glob.does_match(entry->d_name))
					{
						res.push_back(rule.attribute);
						if(rule.group != NULL_STR)
						{
							groups.insert(rule.group);
							break;
						}
					}
				}
			}

		} while(path::is_child(dir, projectDir) && dir != projectDir);

		dispatch_async(dispatch_get_main_queue(), ^{
			std::string const currentProjectDir   = to_s(_projectPath ?: NSHomeDirectory());
			std::string const currentDocumentPath = self.selectedDocument.path ? to_s(self.selectedDocument.path) : path::join(projectDir, "dummy");
			if(projectDir == currentProjectDir && documentPath == currentDocumentPath)
				_externalScopeAttributes = res;
		});

	});
}

- (void)setProjectPath:(NSString*)newProjectPath
{
	if(_projectPath != newProjectPath && ![_projectPath isEqualToString:newProjectPath])
	{
		_projectPath = newProjectPath;
		_projectScopeAttributes.clear();

		std::string const customAttributes = settings_for_path(NULL_STR, text::join(_projectScopeAttributes, " "), to_s(_projectPath)).get(kSettingsScopeAttributesKey, NULL_STR);
		if(customAttributes != NULL_STR)
			_projectScopeAttributes.push_back(customAttributes);

		[self updateExternalAttributes];
		[self updateWindowTitle];
	}
}

- (void)setDocumentPath:(NSString*)newDocumentPath
{
	if(_documentPath != newDocumentPath && !([_documentPath isEqualToString:newDocumentPath]) || _documentScopeAttributes.empty())
	{
		_documentPath = newDocumentPath;
		_documentScopeAttributes = text::split(file::path_attributes(to_s(_documentPath)), " ");

		std::string docDirectory = _documentPath ? path::parent(to_s(_documentPath)) : to_s(self.projectPath);

		if(self.selectedDocument)
		{
			std::string const customAttributes = settings_for_path(to_s(_documentPath), to_s(self.selectedDocument.fileType) + " " + text::join(_documentScopeAttributes, " "), docDirectory).get(kSettingsScopeAttributesKey, NULL_STR);
			if(customAttributes != NULL_STR)
				_documentScopeAttributes.push_back(customAttributes);
		}

		[self updateExternalAttributes];

		if(self.autoRevealFile && self.selectedDocument.path && self.fileBrowserVisible)
			[self revealFileInProject:self];
	}
}

- (NSString*)scopeAttributes
{
	std::set<std::string> attributes;

	attributes.insert(_documentScopeAttributes.begin(), _documentScopeAttributes.end());
	attributes.insert(_projectScopeAttributes.begin(), _projectScopeAttributes.end());
	attributes.insert(_externalScopeAttributes.begin(), _externalScopeAttributes.end());

	return [NSString stringWithCxxString:text::join(attributes, " ")];
}
@end
#pragma clang diagnostic pop
