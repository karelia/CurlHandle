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

		status = [descriptions objectAtIndex:_theStatus];
	}
	[oStatus setObjectValue:status];
	[oStatus display];
}

/*"	_______
"*/

- (id)init;
{
    [super init];
    _dataReceived = [[NSMutableData alloc] init];
    return self;
}

- (void)dealloc
{
	[self stop:nil];
	[mURLHandle release];
	
	[super dealloc];
}


- (void) applicationDidFinishLaunching:(NSNotification *) notif
{
	[CURLHandle curlHelloSignature:@"XxXx"];	// to get CURLHandle registered for handling URLs
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



/*"	Notification that data is available.  Set the progress bar if progress is known.
 "*/

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data
{
    [_dataReceived appendData:data];
    
	[self updateStatus];
    
	if (nil != oProgress)
	{
		long long contentLength = [[handle response] expectedContentLength];
        
		if (contentLength > 0)
		{
			[oProgress setIndeterminate:NO];
			[oProgress setMaxValue:contentLength];
			[oProgress setDoubleValue:[_dataReceived length]];
		}
	}
}

/*"	_______
 "*/

- (void)URLHandleResourceDidBeginLoading:(CURLHandle *)sender
{
	if (nil != oProgress)
	{
		[oProgress startAnimation:self];
	}
    _theStatus = NSURLHandleLoadInProgress;
	[self updateStatus];
}

/*"	_______
 "*/

- (void)URLHandleResourceDidFinishLoading:(CURLHandle *)sender
{
    _theStatus = NSURLHandleLoadSucceeded;
	NSString *contentType = [mURLHandle propertyForKeyIfAvailable:@"content-type"];
    
	if (nil != oProgress)
	{
		[oProgress stopAnimation:self];
	}
	[self updateStatus];
    
	[oGoButton setEnabled:YES];
	[oStopButton setEnabled:NO];
	[oProgress setIndeterminate:YES];
    
	[mURLHandle setDelegate:nil];
    
	
	// Process Header & status & Cookies
	{
		id cookies;
		NSHTTPURLResponse *response = [mURLHandle response];
        NSDictionary *headers = [response allHeaderFields];
        NSInteger statusCode = [response statusCode];
        
		[[oHeader textStorage] replaceCharactersInRange:
         NSMakeRange(0,[[[oHeader textStorage] string] length])
                                             withString:[headers description]];
		
		[oResultCode setIntegerValue:statusCode];
		[oResultCode setNeedsDisplay:YES];
		
		[oResultReason setObjectValue: [NSHTTPURLResponse localizedStringForStatusCode:statusCode]];
		[oResultReason setNeedsDisplay:YES];
		[oResultLocation setObjectValue: [mURLHandle propertyForKey: NSHTTPPropertyRedirectionHeadersKey]];
		[oResultLocation setNeedsDisplay:YES];
		[oResultVers setObjectValue: [mURLHandle propertyForKey: NSHTTPPropertyServerHTTPVersionKey]];
		[oResultVers setNeedsDisplay:YES];
        
		[oHeader setNeedsDisplay:YES];
        
		if ([oCookieParseCheckbox state])
		{
			// convert the array of strings into a dictionary
            cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:headers forURL:[response URL]];
			cookies = [cookies valueForKey:@"properties"];
		}
		
		[[oCookieResult textStorage] replaceCharactersInRange:
         NSMakeRange(0,[[[oCookieResult textStorage] string] length])
                                                   withString:[cookies description]];
	}
	
	// Process Body
	if (_dataReceived)	// it might be nil if failed in the foreground thread, for instance
	{
		NSString *bodyString = nil;
		NSAttributedString *bodyAttrString = nil;
		
		if ([contentType hasPrefix:@"text/"])
		{
			// Render HTML if we have HTML and the checkbox is checked to allow this
			if ([oRenderHTMLCheckbox state] && [contentType hasPrefix:@"text/html"])
			{
				bodyAttrString = [[[NSAttributedString alloc] initWithHTML:_dataReceived documentAttributes:nil] autorelease];
			}
			else
			{
				bodyString
                = [[[NSString alloc] initWithData:_dataReceived encoding:NSASCIIStringEncoding] autorelease];
			}
		}
		else
		{
			bodyString = [NSString stringWithFormat:@"There were %d bytes of type %@",
                          [_dataReceived length], contentType];
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

- (void)URLHandleResourceDidCancelLoading:(CURLHandle *)sender
{
    _theStatus = NSURLHandleLoadFailed;
	[oGoButton setEnabled:YES];
	[oStopButton setEnabled:NO];
	[oProgress setIndeterminate:YES];
	[self updateStatus];
    
	[mURLHandle setDelegate:nil];
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
    _theStatus = NSURLHandleLoadFailed;
	[oGoButton setEnabled:YES];
	[oStopButton setEnabled:NO];
	[oProgress setIndeterminate:YES];
	[self updateStatus];
    
	[mURLHandle setDelegate:nil];
	if (nil != oProgress)
	{
		[oProgress stopAnimation:self];
	}
	[oResultCode setStringValue:reason];
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
		[self setURLHandle:[[[CURLHandle alloc] init] autorelease]];
        
        _theStatus = NSURLHandleLoadInProgress;
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
        [_dataReceived setLength:0];
        
		if ([oBackground state])
		{
			[oGoButton setEnabled:NO];
			[oStopButton setEnabled:YES];
			[mURLHandle setDelegate:self];

			[self updateStatus];

			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                
                NSError *error;
                BOOL result = [mURLHandle loadRequest:[NSURLRequest requestWithURL:url] error:&error];
                
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    if (result)
                    {
                        [self URLHandleResourceDidFinishLoading:mURLHandle];
                    }
                }];
            });

			[self updateStatus];
		}
		else
		{
			[self updateStatus];
			[mURLHandle setConnectionTimeout:4];

			[oProgress startAnimation:self];
			// directly call up the results
            NSError *error;
            BOOL result = [mURLHandle loadRequest:[NSURLRequest requestWithURL:url] error:&error];
			
            [self URLHandleResourceDidFinishLoading:mURLHandle];
			if (!result)
			{
				[oResultCode setStringValue:[error localizedDescription]];
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


@end
