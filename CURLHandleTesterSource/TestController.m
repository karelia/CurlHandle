//  Created by Dan Wood <dwood@karelia.com> on Mon Oct 01 2001.
//  This is in the public domain, but please report any improvements back to the author.

#import "TestController.h"

@interface TestController ( private )

- (void) setURLHandle:(CURLHandle *)inURLHandle;
- (void) updateStatus;
- (NSDictionary *)dictionaryfromCookieArray:(NSArray *)inArray;

@end

@implementation TestController

/*"	Canonical setter: retain the new guy; release the old guy; set.
"*/

- (void) setURLHandle:(CURLHandle *)inURLHandle
{
	[inURLHandle retain];
	[mURLHandle release];
	mURLHandle = inURLHandle;
}

- (void) awakeFromNib
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[oFollow setState:[defaults boolForKey:@"followCheckbox"]];
	[oPostCheckbox setState:[defaults boolForKey:@"postCheckbox"]];
	[oHeaderParseCheckbox setState:[defaults boolForKey:@"headerParseCheckbox"]];
	[oCookieParseCheckbox setState:[defaults boolForKey:@"cookieParseCheckbox"]];
	[oBackground setState:[defaults boolForKey:@"backgroundCheckbox"]];
	[oRenderHTMLCheckbox setState:[defaults boolForKey:@"renderHTMLCheckbox"]];
	
	[oCookieFileString setObjectValue:[defaults objectForKey:@"cookieFile"]];
	[oCookieDictionary setObjectValue:[defaults objectForKey:@"cookieDictionary"]];
	[oUserID setObjectValue:[defaults objectForKey:@"userid"]];
	[oPassword setObjectValue:[defaults objectForKey:@"password"]];
	[oPostDictionary setObjectValue:[defaults stringForKey:@"postDictionary"]];
	[oURL setObjectValue:[defaults stringForKey:@"urlstring"]];

	[oGoButton setEnabled:YES];
	[oStopButton setEnabled:NO];
	[oProgress setIndeterminate:YES];
	[self updateStatus];
}

/*"	Show the CURLHandle's status immediately.
"*/

- (void) updateStatus
{
	NSString *status = nil;
	if (nil == mURLHandle)
	{
		status = @"(no CURLHandle)";
		[oResultReason setStringValue: @""];
		[oResultLocation setStringValue: @""];
		[oResultVers setStringValue: @""];
	}
	else
	{
		NSArray *descriptions
			= [NSArray arrayWithObjects:@"Not Loaded", @"Succeeded", @"In Progress", @"Failed", nil];

		NSURLHandleStatus theStatus = [mURLHandle status];
		status = [descriptions objectAtIndex:theStatus];
	}
	[oStatus setObjectValue:status];
	[oStatus display];
}

/*"	_______
"*/

- (void)dealloc
{
	[self stop:nil];
	[mURLHandle release];
	
	[super dealloc];
}


- (void) applicationDidFinishLaunching:(NSNotification *) notif
{
	[CURLHandle curlHelloSignature:@"XxXx" acceptAll:YES];	// to get CURLHandle registered for handling URLs
}

- (void) applicationWillTerminate:(NSNotification *) notif
{
	[CURLHandle curlGoodbye];	// to clean up
}

- (IBAction) useSnoop:(id)sender
{
	[oURL setObjectValue:@"http://www.entropy.ch/software/MacOSX/php/test.php?happy=yes"];
}

- (IBAction) useBigFile:(id)sender
{
	[oURL setObjectValue:@"http://www.karelia.com/files/Sandvox.dmg"];
}

- (IBAction) useSSLTest:(id)sender
{
	[oURL setObjectValue:@"https://www.fortify.net/cgi/ssl_3.pl"];
}



#warning # can't assume any encoding for body.  Perhaps we could look for the encoding value in the header, and try again if it doesn't match?

- (IBAction)go:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSURL *url;
	NSString *urlString = [oURL stringValue];
	
	// Add "http://" if missing
	if (![urlString hasPrefix:@"http://"] && ![urlString hasPrefix:@"https://"] && ![urlString hasPrefix:@"ftp://"])
	{
		urlString = [NSString stringWithFormat:@"http://%@",urlString];
	}
	
	urlString = (NSString *) CFURLCreateStringByAddingPercentEscapes(
		NULL, (CFStringRef) urlString, NULL, NULL,
		CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));

	[oURL setStringValue:urlString];	// fix the input for future calls, to show real format
	
	url = [NSURL URLWithString:urlString];

	if (nil != url)	// ignore if no URL
	{
		// Clear out the results (of any previous load)
		[oResultCode setStringValue:@"loading..."];
		[[oCookieResult textStorage] replaceCharactersInRange:
			NSMakeRange(0,[[[oCookieResult textStorage] string] length])
												withString:@""];
		[[oBody textStorage] replaceCharactersInRange:
				NSMakeRange(0,[[[oBody textStorage] string] length])
				withString:@""];
		[[oHeader textStorage] replaceCharactersInRange:
			NSMakeRange(0,[[[oHeader textStorage] string] length])
			withString:@""];
		[oResultCode display];
		[oBody display];
		[oHeader display];

		// Store away defaults for later
		[defaults setBool:[oFollow state] forKey:@"followCheckbox"];
		[defaults setBool:[oPostCheckbox state] forKey:@"postCheckbox"];
		[defaults setBool:[oHeaderParseCheckbox state] forKey:@"headerParseCheckbox"];
		[defaults setBool:[oCookieParseCheckbox state] forKey:@"cookieParseCheckbox"];
		[defaults setBool:[oBackground state] forKey:@"backgroundCheckbox"];
		[defaults setBool:[oRenderHTMLCheckbox state] forKey:@"renderHTMLCheckbox"];
		[defaults setObject:[oCookieFileString stringValue] forKey:@"cookieFile"];
		[defaults setObject:[oCookieDictionary stringValue] forKey:@"cookieDictionary"];		
		[defaults setObject:[oUserID stringValue] forKey:@"userid"];
		[defaults setObject:[oPassword stringValue] forKey:@"password"];
		[defaults setObject:[oPostDictionary stringValue] forKey:@"postDictionary"];
		[defaults setObject:urlString forKey:@"urlstring"];
		// Store the defaults away before we load
		[defaults synchronize];

		// set some options based on user input
		[self setURLHandle:(CURLHandle *)[url URLHandleUsingCache:NO]];
		[self updateStatus];
		[mURLHandle setFailsOnError:NO];		// don't fail on >= 300 code; I want to see real results.
		[mURLHandle setFollowsRedirects:[oFollow state]];
		[mURLHandle setCookieFile:[[oCookieFileString stringValue] stringByExpandingTildeInPath]];
		[mURLHandle setUserName:[oUserID stringValue] password:[oPassword stringValue]];

		// Set the user-agent (for Yahoo, to get the ads) to something Mozilla-compatible
		[mURLHandle setUserAgent:
				@"Mozilla/4.5 (compatible; OmniWeb/4.0.5; Mac_PowerPC)"];

		// Handle Cookie dictionary
		if ([[oCookieDictionary stringValue] length] > 0)
		{
			NSString *dictString = [oCookieDictionary stringValue];
			NSData *dictData = [dictString dataUsingEncoding:NSUTF8StringEncoding];
			NSDictionary *dict = [dictData propertyListFromXML];
			if (nil == dict && ![dictString isEqualToString:@""])
			{
				NSRunCriticalAlertPanel(@"Unparseable Dictionary",
					@"The 'Cookie Dict' field needs to be parseable,\ne.g. \n{\n   Key1 = Value1;\n}",
					nil, nil, nil );
				return;
			}
			[mURLHandle setRequestCookies:dict];
		}
		
		// Handle "POST"
		if ([oPostCheckbox state])
		{
			NSString *dictString = [oPostDictionary stringValue];
			NSData *dictData = [dictString dataUsingEncoding:NSUTF8StringEncoding];
			NSDictionary *dict = [dictData propertyListFromXML];
			if (nil == dict && ![dictString isEqualToString:@""])
			{
				NSRunCriticalAlertPanel(@"Unparseable Dictionary",
					@"The 'Post Dict' field needs to be parseable,\ne.g. \n{\n   Key1 = Value1;\n}",
					nil, nil, nil );
				return;
			}
			[mURLHandle setPostDictionary:dict];
		}

		// And load, either in foreground or background...
		if ([oBackground state])
		{
			mBytesRetrievedSoFar = 0;
			
			[oGoButton setEnabled:NO];
			[oStopButton setEnabled:YES];
			[mURLHandle addClient:self];

			[self updateStatus];

			[mURLHandle loadInBackground];

			[self updateStatus];
		}
		else
		{
			[self updateStatus];
			[mURLHandle setConnectionTimeout:4];
			[mURLHandle setProgressIndicator:oProgress];
			[oProgress startAnimation:self];
			// directly call up the results
			[self URLHandleResourceDidFinishLoading:mURLHandle];
			if (NSURLHandleLoadFailed == [mURLHandle status])
			{
				[oResultCode setStringValue:[mURLHandle failureReason]];
			}
			[self updateStatus];
		}
	}
	else
	{
		NSRunInformationalAlertPanel(NSLocalizedString(@"Couldn't Build Valid URL",@""),
			urlString,nil,nil,nil);
	}
}

/*"	Action: _______
"*/

- (IBAction)stop:(id)sender
{
	[mURLHandle cancelLoadInBackground];
	[self updateStatus];
}


/*"	Notification that data is available.  Set the progress bar if progress is known.
"*/

- (void)URLHandle:(NSURLHandle *)sender resourceDataDidBecomeAvailable:(NSData *)newBytes
{
	[self updateStatus];

	if (nil != oProgress)
	{
		id contentLength = [sender propertyForKeyIfAvailable:@"content-length"];
	
		mBytesRetrievedSoFar += [newBytes length];
	
		if (nil != contentLength)
		{
			double total = [contentLength doubleValue];
			[oProgress setIndeterminate:NO];
			[oProgress setMaxValue:total];
			[oProgress setDoubleValue:mBytesRetrievedSoFar];
		}
	}
}

/*"	_______
"*/

- (void)URLHandleResourceDidBeginLoading:(NSURLHandle *)sender
{
	if (nil != oProgress)
	{
		[oProgress startAnimation:self];
	}
	[self updateStatus];
}

/*"	_______
"*/

- (void)URLHandleResourceDidFinishLoading:(NSURLHandle *)sender
{
	NSData *data = [mURLHandle resourceData];	// if foreground, this will block 'til loaded.
	NSString *contentType = [mURLHandle propertyForKeyIfAvailable:@"content-type"];

	if (nil != oProgress)
	{
		[oProgress stopAnimation:self];
	}
	[self updateStatus];

	[oGoButton setEnabled:YES];
	[oStopButton setEnabled:NO];
	[oProgress setIndeterminate:YES];

	[mURLHandle removeClient:self];	// disconnect this from the URL handle

	
	// Process Header & status & Cookies
	{
		id cookies;
		id headers = [mURLHandle propertyForKey:@"HEADER"];
		id httpCode = [mURLHandle propertyForKeyIfAvailable:NSHTTPPropertyStatusCodeKey];

		if ([oHeaderParseCheckbox state])
		{
			headers = [headers allHTTPHeaderFields];
		}
		[[oHeader textStorage] replaceCharactersInRange:
			NSMakeRange(0,[[[oHeader textStorage] string] length])
			withString:[headers description]];
		
		[oResultCode setObjectValue:httpCode];
		[oResultCode setNeedsDisplay:YES];
		
		[oResultReason setObjectValue: [mURLHandle propertyForKey: NSHTTPPropertyStatusReasonKey]];
		[oResultReason setNeedsDisplay:YES];
		[oResultLocation setObjectValue: [mURLHandle propertyForKey: NSHTTPPropertyRedirectionHeadersKey]];
		[oResultLocation setNeedsDisplay:YES];
		[oResultVers setObjectValue: [mURLHandle propertyForKey: NSHTTPPropertyServerHTTPVersionKey]];
		[oResultVers setNeedsDisplay:YES];

		[oHeader setNeedsDisplay:YES];

		if ([oCookieParseCheckbox state])
		{
			// convert the array of strings into a dictionary
            cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:[headers allHTTPHeaderFields] forURL:[mURLHandle url]];
			cookies = [cookies valueForKey:@"properties"];
		}
		
		[[oCookieResult textStorage] replaceCharactersInRange:
			NSMakeRange(0,[[[oCookieResult textStorage] string] length])
			withString:[cookies description]];
	}
	
	// Process Body
	if (nil != data)	// it might be nil if failed in the foreground thread, for instance
	{
		NSString *bodyString = nil;
		NSAttributedString *bodyAttrString = nil;
		
		if ([contentType hasPrefix:@"text/"])
		{
			// Render HTML if we have HTML and the checkbox is checked to allow this
			if ([oRenderHTMLCheckbox state] && [contentType hasPrefix:@"text/html"])
			{
				bodyAttrString = [[[NSAttributedString alloc] initWithHTML:data documentAttributes:nil] autorelease];
			}
			else
			{
				bodyString
					= [[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] autorelease];
			}
		}
		else
		{
			bodyString = [NSString stringWithFormat:@"There were %d bytes of type %@",
				[data length], contentType];
		}
		if (nil != bodyAttrString)
		{
			[[oBody textStorage] replaceCharactersInRange:
				NSMakeRange(0,[[[oBody textStorage] string] length])
				withAttributedString:bodyAttrString];
		}
		else	// plain text
		{
			[[oBody textStorage] replaceCharactersInRange:
				NSMakeRange(0,[[[oBody textStorage] string] length])
				withString:bodyString];
		}
		[oBody setNeedsDisplay:YES];
	}
}

/*"	_______
"*/

- (void)URLHandleResourceDidCancelLoading:(NSURLHandle *)sender
{
	[oGoButton setEnabled:YES];
	[oStopButton setEnabled:NO];
	[oProgress setIndeterminate:YES];
	[self updateStatus];

	[mURLHandle removeClient:self];	// disconnect this from the URL handle
	if (nil != oProgress)
	{
		[oProgress stopAnimation:self];
	}
	[oResultCode setStringValue:@"You cancelled it"];
}

/*"	_______
"*/

- (void)URLHandle:(NSURLHandle *)sender resourceDidFailLoadingWithReason:(NSString *)reason
{
	[oGoButton setEnabled:YES];
	[oStopButton setEnabled:NO];
	[oProgress setIndeterminate:YES];
	[self updateStatus];

	[mURLHandle removeClient:self];	// disconnect this from the URL handle
	if (nil != oProgress)
	{
		[oProgress stopAnimation:self];
	}
	[oResultCode setStringValue:reason];
}

@end
