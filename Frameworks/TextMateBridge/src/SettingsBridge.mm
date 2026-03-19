#import "SettingsBridge.h"
#import <OakFoundation/NSString Additions.h>
#import <settings/settings.h>
#import <ns/ns.h>

@implementation SettingsBridge

+ (nullable id)valueForSettingsKey:(NSString *)key
{
	std::string value = settings_t::raw_get(to_s(key));
	if(value == NULL_STR)
		return nil;
	return [NSString stringWithCxxString:value];
}

+ (void)setValue:(nullable id)value forSettingsKey:(NSString *)key
{
	NSString *stringValue = value ?: @"";
	if([stringValue isKindOfClass:[NSString class]])
		settings_t::set(to_s(key), to_s(stringValue));
}

+ (nullable id)valueForDefaultsKey:(NSString *)key
{
	return [NSUserDefaults.standardUserDefaults objectForKey:key];
}

+ (void)setValue:(nullable id)value forDefaultsKey:(NSString *)key
{
	if(value)
		[NSUserDefaults.standardUserDefaults setObject:value forKey:key];
	else
		[NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

+ (void)setValue:(NSString *)value forSettingsKey:(NSString *)key scope:(NSString *)scope
{
	settings_t::set(to_s(key), to_s(value), to_s(scope));
}

+ (nullable NSString *)rawValueForSettingsKey:(NSString *)key scope:(NSString *)scope
{
	std::string value = settings_t::raw_get(to_s(key), to_s(scope));
	if(value == NULL_STR)
		return nil;
	return [NSString stringWithCxxString:value];
}

@end
