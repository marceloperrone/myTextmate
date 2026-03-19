#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges the C++ settings_t engine to Swift.
/// Routes keys through either NSUserDefaults or the C++ settings_t store.
@interface SettingsBridge : NSObject

+ (nullable id)valueForSettingsKey:(NSString *)key;
+ (void)setValue:(nullable id)value forSettingsKey:(NSString *)key;

+ (nullable id)valueForDefaultsKey:(NSString *)key;
+ (void)setValue:(nullable id)value forDefaultsKey:(NSString *)key;

/// Set a C++ settings_t value scoped to a specific context (e.g. "attr.untitled").
+ (void)setValue:(NSString *)value forSettingsKey:(NSString *)key scope:(NSString *)scope;

/// Read a raw C++ settings_t value scoped to a specific context.
+ (nullable NSString *)rawValueForSettingsKey:(NSString *)key scope:(NSString *)scope;

@end

NS_ASSUME_NONNULL_END
