//  Created by Dan Wood <dwood@karelia.com> on Mon Oct 01 2001.
//  This is in the public domain, but please report any improvements back to the author.

#import <Cocoa/Cocoa.h>
#import <CURLHandle/CURLHandle.h>
#import <CURLHandle/CURLHandle+extras.h>
#import "NSData+plist.h"

@class CURLHandle;

@interface TestController : NSObject <CURLHandleDelegate>
{
    IBOutlet id oBackground;
    IBOutlet id oFollow;
    IBOutlet id oPassword;
    IBOutlet id oPostCheckbox;
	IBOutlet id oHeaderParseCheckbox;
	IBOutlet id oCookieParseCheckbox;
	IBOutlet NSProgressIndicator *oProgress;
    IBOutlet id oSSL;
    IBOutlet id oURL;
    IBOutlet id oUserID;
	IBOutlet id oCookieFileString;
	IBOutlet id oCookieDictionary;
	IBOutlet id oPostDictionary;
	IBOutlet id oCookieResult;

    IBOutlet id oResultCode;
	IBOutlet id oResultReason;
	IBOutlet id oResultLocation;
	IBOutlet id oResultVers;
    IBOutlet id oHeader;
    IBOutlet id oBody;

    IBOutlet id oGoButton;
    IBOutlet id oStopButton;

    IBOutlet id oRenderHTMLCheckbox;
	IBOutlet id oStatus;

	CURLHandle *mURLHandle;
    
	NSMutableData       *_dataReceived;
	NSURLHandleStatus   _theStatus;
}

- (IBAction)go:(id)sender;
- (IBAction)stop:(id)sender;
- (IBAction)useSnoop:(id)sender;
- (IBAction) useBigFile:(id)sender;
- (IBAction) useSSLTest:(id)sender;

@end
