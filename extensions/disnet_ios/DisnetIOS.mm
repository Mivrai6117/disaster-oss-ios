#import "DisnetIOS.h"

#include "disnet_ios_api.h"

@implementation DisnetIOS

-(double) disnet_ios_connect:(NSString*)hostport
{
	if (hostport == nil)
		return 0.0;

	return dnios_connect([hostport UTF8String]);
}

-(NSString*) disnet_ios_poll
{
	const char *msg = dnios_poll();
	NSString *result = [NSString stringWithUTF8String:(msg ? msg : "")];
	return result ? result : @"";
}

-(double) disnet_ios_send:(NSString*)message
{
	if (message == nil)
		return 0.0;

	return dnios_send([message UTF8String]);
}

-(double) disnet_ios_reset
{
	return dnios_reset();
}

-(NSString*) disnet_ios_status
{
	const char *msg = dnios_status();
	NSString *result = [NSString stringWithUTF8String:(msg ? msg : "")];
	return result ? result : @"";
}

@end
