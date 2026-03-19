#import "BundlesBridge.h"
#import <OakFoundation/NSString Additions.h>
#import <bundles/bundles.h>
#import <text/ctype.h>
#import <ns/ns.h>

@implementation GrammarEntry
{
	NSString *_name;
	NSString *_scopeName;
	NSString *_uuid;
	BOOL _hiddenFromUser;
}

- (instancetype)initWithName:(NSString *)name scopeName:(NSString *)scopeName uuid:(NSString *)uuid hiddenFromUser:(BOOL)hidden
{
	if(self = [super init])
	{
		_name           = name;
		_scopeName      = scopeName;
		_uuid           = uuid;
		_hiddenFromUser = hidden;
	}
	return self;
}

- (NSString *)name       { return _name; }
- (NSString *)scopeName  { return _scopeName; }
- (NSString *)uuid       { return _uuid; }
- (BOOL)hiddenFromUser   { return _hiddenFromUser; }
@end

@implementation BundlesBridge

+ (NSArray<GrammarEntry *> *)availableGrammars
{
	std::multimap<std::string, bundles::item_ptr, text::less_t> grammars;
	for(auto const& item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeGrammar))
	{
		std::string const& fileType = item->value_for_field(bundles::kFieldGrammarScope);
		if(fileType != NULL_STR)
			grammars.emplace(item->name(), item);
	}

	NSMutableArray<GrammarEntry *> *result = [NSMutableArray array];
	for(auto const& pair : grammars)
	{
		GrammarEntry *entry = [[GrammarEntry alloc]
			initWithName:[NSString stringWithCxxString:pair.first]
			   scopeName:[NSString stringWithCxxString:pair.second->value_for_field(bundles::kFieldGrammarScope)]
			        uuid:[NSString stringWithCxxString:pair.second->uuid()]
			hiddenFromUser:pair.second->hidden_from_user()
		];
		[result addObject:entry];
	}

	return result;
}

@end
