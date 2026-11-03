#import <Foundation/Foundation.h>

// Extension class for GameMaker's iOS runner. Each method is one extension
// function (see README.md for how to declare them in the extension editor).
// Every method takes at most one argument so the selector shape is unambiguous.
//
//   disnet_ios_connect("host:port")   -> 1 when the attempt started
//   disnet_ios_poll()                 -> "" | "1" | "2:<code>" | "3:<base64>" | "4:<base64>"
//   disnet_ios_send("<1|0>:<base64>") -> 1 when accepted
//   disnet_ios_reset()                -> 0
//   disnet_ios_status()               -> diagnostic text (never empty if this class is reached)
@interface DisnetIOS : NSObject

-(double) disnet_ios_connect:(NSString*)hostport;
-(NSString*) disnet_ios_poll;
-(double) disnet_ios_send:(NSString*)message;
-(double) disnet_ios_reset;
-(NSString*) disnet_ios_status;

@end
