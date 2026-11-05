#import "DisnetIOS.h"

#include "disnet_ios_api.h"

#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>

// While the app is not active GameMaker stops running, so no position updates reach the
// server and it kicks the player as AFK after ~4 seconds. When the app is about to go
// inactive we ask iOS for extra running time (about 30 seconds; Apple does not guarantee
// the exact figure) and let a native thread keep the connection alive meanwhile.
// Everything below runs on the main thread.
static UIBackgroundTaskIdentifier g_disnetTask = UIBackgroundTaskInvalid;

static void disnet_keepalive_end(void)
{
	dnios_background_end();

	if (g_disnetTask != UIBackgroundTaskInvalid)
	{
		UIBackgroundTaskIdentifier task = g_disnetTask;
		g_disnetTask = UIBackgroundTaskInvalid;
		[[UIApplication sharedApplication] endBackgroundTask:task];
	}
}

static void disnet_keepalive_begin(void)
{
	if (g_disnetTask != UIBackgroundTaskInvalid)
		return;

	g_disnetTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"disnet-keepalive"
		expirationHandler:^{
			// iOS is about to suspend the app: stop our thread and give the time back.
			disnet_keepalive_end();
		}];

	if (g_disnetTask != UIBackgroundTaskInvalid)
		dnios_background_begin();
}
#endif

@implementation DisnetIOS

#if TARGET_OS_IOS
// Runs once when the app launches, before GameMaker creates the extension object.
+(void) load
{
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	NSOperationQueue *main = [NSOperationQueue mainQueue];

	[nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:main
		usingBlock:^(NSNotification *note) { disnet_keepalive_begin(); }];

	[nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:main
		usingBlock:^(NSNotification *note) { disnet_keepalive_end(); }];
}
#endif

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
