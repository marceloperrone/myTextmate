#import "include/SettingsBridge.h"

// When integrated with the TextMate build, uncomment these:
// #import <settings/settings.h>
// #import <OakFoundation/NSString Additions.h>
// #import <ns/ns.h>

@implementation SettingsBridge

+ (nullable id)valueForSettingsKey:(NSString *)key
{
    // Bridge to C++ settings_t::raw_get()
    // return [NSString stringWithCxxString:settings_t::raw_get(to_s(key))];
    return nil; // Stub — replace with C++ call when linked
}

+ (void)setValue:(nullable id)value forSettingsKey:(NSString *)key
{
    // Bridge to C++ settings_t::set()
    // if ([value isKindOfClass:[NSString class]])
    //     settings_t::set(to_s(key), to_s((NSString *)value));
}

+ (nullable id)valueForDefaultsKey:(NSString *)key
{
    return [NSUserDefaults.standardUserDefaults objectForKey:key];
}

+ (void)setValue:(nullable id)value forDefaultsKey:(NSString *)key
{
    if (value)
        [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
    else
        [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

+ (void)setValue:(NSString *)value forSettingsKey:(NSString *)key scope:(NSString *)scope
{
    // Bridge to C++ settings_t::set(key, value, scope)
    // settings_t::set(to_s(key), to_s(value), to_s(scope));
}

+ (nullable NSString *)rawValueForSettingsKey:(NSString *)key scope:(NSString *)scope
{
    // Bridge to C++ settings_t::raw_get(key, scope)
    // return [NSString stringWithCxxString:settings_t::raw_get(to_s(key), to_s(scope))];
    return nil; // Stub
}

@end
