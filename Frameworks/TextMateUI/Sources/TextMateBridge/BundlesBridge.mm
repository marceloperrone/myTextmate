#import "include/BundlesBridge.h"

// When integrated with the TextMate build, uncomment:
// #import <bundles/bundles.h>
// #import <text/ctype.h>
// #import <ns/ns.h>

@implementation GrammarEntry
{
    NSString *_name;
    NSString *_scopeName;
    NSString *_uuid;
    BOOL _hiddenFromUser;
}

- (instancetype)initWithName:(NSString *)name scopeName:(NSString *)scopeName uuid:(NSString *)uuid hiddenFromUser:(BOOL)hidden
{
    if (self = [super init]) {
        _name = name;
        _scopeName = scopeName;
        _uuid = uuid;
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
    // Bridge to C++ bundles::query()
    // NSMutableArray *result = [NSMutableArray array];
    // for (auto const& item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeGrammar)) {
    //     if (item->value_for_field(bundles::kFieldGrammarScope) != NULL_STR) {
    //         GrammarEntry *entry = [[GrammarEntry alloc] initWithName:[NSString stringWithCxxString:item->name()]
    //                                                        scopeName:[NSString stringWithCxxString:item->value_for_field(bundles::kFieldGrammarScope)]
    //                                                             uuid:[NSString stringWithCxxString:item->uuid()]
    //                                                   hiddenFromUser:item->hidden_from_user()];
    //         [result addObject:entry];
    //     }
    // }
    // return [result sortedArrayUsingComparator:^(GrammarEntry *a, GrammarEntry *b) {
    //     return [a.name localizedCaseInsensitiveCompare:b.name];
    // }];
    return @[]; // Stub
}

@end
