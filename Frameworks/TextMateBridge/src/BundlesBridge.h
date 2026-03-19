#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Represents a grammar entry from the C++ bundles system.
@interface GrammarEntry : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *scopeName;
@property (nonatomic, readonly) NSString *uuid;
@property (nonatomic, readonly) BOOL hiddenFromUser;
- (instancetype)initWithName:(NSString *)name scopeName:(NSString *)scopeName uuid:(NSString *)uuid hiddenFromUser:(BOOL)hidden;
@end

/// Bridges the C++ bundles engine to Swift.
@interface BundlesBridge : NSObject
+ (NSArray<GrammarEntry *> *)availableGrammars;
@end

NS_ASSUME_NONNULL_END
