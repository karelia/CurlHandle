//
//  CURLHandle.m
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.
//
//	The current version of CURLHandle is 2.0
//

#import "CURLHandle.h"
#define NSS(s) (NSString *)(s)
#include <SystemConfiguration/SystemConfiguration.h>



// Un-comment these to do some debugging things
//#define DEBUGCURL 1
//#define DEBUGCURL_SLOW


BOOL				sAllowsProxy = YES;		// by default, allow proxy to be used./
SCDynamicStoreRef	sSCDSRef = NULL;
NSString			*sProxyUserIDAndPassword = nil;


@interface CURLResponse : NSHTTPURLResponse
{
@private
    NSInteger       _statusCode;
    NSDictionary    *_headerFields;
}

- (id)initWithURL:(NSURL *)URL statusCode:(NSInteger)statusCode headerString:(NSString *)headerString;

@end

@interface NSString ( CurlHTTPExtensions )

- (NSString *) headerStatus;
- (NSString *) headerHTTPVersion;
- (NSString *) headerMatchingKey:(NSString *)inKey;
- (NSArray *) headersMatchingKey:(NSString *)inKey;
- (NSDictionary *) allHTTPHeaderFields;
- (NSString *) headerKey;
- (NSString *) headerValue;
- (NSArray *) componentsSeparatedByLineSeparators;

@end


/*"	Callback from reading a chunk of data.  Since we pass "self" in as the "data pointer",
	we can use that to get back into Objective C and do the work with the class.
"*/

size_t curlBodyFunction(void *ptr, size_t size, size_t nmemb, void *inSelf)
{
	return [(CURLHandle *)inSelf curlWritePtr:ptr size:size number:nmemb isHeader:NO];
}

/*"	Callback from reading a chunk of data.  Since we pass "self" in as the "data pointer",
	we can use that to get back into Objective C and do the work with the class.
"*/

size_t curlHeaderFunction(void *ptr, size_t size, size_t nmemb, void *inSelf)
{
	return [(CURLHandle *)inSelf curlWritePtr:ptr size:size number:nmemb isHeader:YES];
}

@implementation CURLHandle

/*"	CURLHandle is a wrapper around a CURL.
	This is in the public domain, but please report any improvements back to the author
	(dwood_karelia_com).
	Be sure to be familiar with CURL and how it works; see http://curl.haxx.se/

	The idea is to have it handle http and possibly other schemes too.  At this time
	we don't support writing data (via HTTP PUT) and special situations such as HTTPS and
	firewall proxies haven't been tried out yet.
	
	This class maintains only basic functionality, any "bells and whistles" should be
	defined in a category to keep this file as simple as possible.

	Each instance is created to be associated with a URL.  But we can change the URL and
	use the previous connection, as the CURL documentation says.

	%{#Note: Comments in methods with this formatting indicate quotes from the headers and
	documentation for #NSURLHandle and are provided to help prove "correctness."  Some
	come from an another document -- perhaps an earlier version of the documentation or release notes,
	but I can't find the original source. These are marked "(?source)"}

"*/

// -----------------------------------------------------------------------------
#pragma mark ----- ADDITIONAL CURLHANDLE INTERFACES
// -----------------------------------------------------------------------------
/*" You must call #curlGoodbye at end of program, for example in #{[NSApplication applicationWillTerminate:]}.
"*/

+ (void) curlGoodbye
{
	curl_global_cleanup();
}

/*" Initialize CURLHandle and the underlying CURL.  This can be invoked when the program is launched or before any loading is needed.
"*/

+ (void)curlHelloSignature:(NSString *)inSignature;
{
	CURLcode rc;
	rc = curl_global_init(CURL_GLOBAL_ALL);
	if (0 != rc)
	{
		NSLog(@"Didn't curl_global_init, result = %d",rc);
	}
	
	// Now initialize System Config.
	sSCDSRef = SCDynamicStoreCreate(NULL,(CFStringRef)inSignature,NULL, NULL);
	if ( sSCDSRef == NULL )
	{
		NSLog(@"Didn't get SCDynamicStoreRef");
	}
}

/*"	Set a proxy user id and password, used by all CURLHandle. This should be done before any transfers are made."*/

+ (void) setProxyUserIDAndPassword:(NSString *)inString
{
	[inString retain];
	[sProxyUserIDAndPassword release];
	sProxyUserIDAndPassword = inString;
}

/*"	Set whether proxies are allowed or not.  Default value is YES.  If no, the proxy settings
	are ignored.
"*/
+ (void) setAllowsProxy:(BOOL) inBool
{
	sAllowsProxy = inBool;
}


/*"	Return the CURL object assocated with this, so categories can have other methods
	that do curl-specific stuff like #curl_easy_getinfo
"*/

- (CURL *) curl
{
	return mCURL;
}

/*"	Set the URL request related to this CURLHandle.  This can actually be changed so the same CURL is used
	for different URLs, though they must be done sequentially.  (See libcurl documentation.)
"*/

- (void)setRequest:(NSURLRequest *)request;
{
    if (request == _request) return;
    [_request release]; _request = [request copy];
}

- (void) setString:(NSString *)inString forKey:(CURLoption) inCurlOption
{
	[mStringOptions setObject:inString forKey:[NSNumber numberWithInt:inCurlOption]];
}

/*"	Set an option given a !{CURLoption} key.  Before transfer, the object, which  must be an NSString or an integer NSNumber will be used to invoke %curl_easy_setopt.  Categories with convenient APIs can make use of this.
"*/

- (void) setStringOrNumberObject:(id)inObject forKey:(CURLoption) inCurlOption
{
	[mStringOptions setObject:inObject forKey:[NSNumber numberWithInt:inCurlOption]];
}

/*"	Set the file to be PUT
"*/
- (void) setPutFile:(NSString *)path
{
	mPutFile = fopen([path fileSystemRepresentation], "r");
	if (NULL == mPutFile) {
		NSLog(@"CURLHandle: setPutFile couldn't find file at %@", path);
		return;
	}
	fseek(mPutFile, 0, SEEK_END);
	curl_easy_setopt([self curl], CURLOPT_PUT, 1L);
	curl_easy_setopt([self curl], CURLOPT_UPLOAD, 1L);
	curl_easy_setopt([self curl], CURLOPT_INFILE, mPutFile);
	curl_easy_setopt([self curl], CURLOPT_INFILESIZE, ftell(mPutFile));
	rewind(mPutFile);
}

/*"	Set the file offset for performing the PUT.
"*/

- (void) setPutFileOffset:(int)offset
{
	if (NULL != mPutFile) {
		fseek(mPutFile, offset, SEEK_SET);
	}
}

- (void) setPutFile:(NSString *)path resumeUploadFromOffset:(off_t)offset_ {
	mPutFile = fopen([path fileSystemRepresentation], "r");
	if (NULL == mPutFile) {
		NSLog(@"CURLHandle: setPutFile:resumeUploadFromOffset: couldn't find file at %@", path);
		return;
	}
	
	fseek(mPutFile, 0, SEEK_END);
	off_t fileSize = ftello(mPutFile);
	rewind(mPutFile);
	
	curl_easy_setopt([self curl], CURLOPT_PUT, 1L);
	curl_easy_setopt([self curl], CURLOPT_UPLOAD, 1L);
	curl_easy_setopt([self curl], CURLOPT_INFILE, mPutFile);
	curl_easy_setopt([self curl], CURLOPT_INFILESIZE_LARGE, fileSize);
	curl_easy_setopt([self curl], CURLOPT_RESUME_FROM_LARGE, offset_);
}

+ (NSString *) curlVersion
{
	return [NSString stringWithCString: curl_version() encoding:NSASCIIStringEncoding];
}


// -----------------------------------------------------------------------------
#pragma mark ----- NSURLHANDLE OVERRIDES
// -----------------------------------------------------------------------------

- (void) dealloc
{
	curl_easy_cleanup(mCURL);
	mCURL = nil;
	[_request release];
	[mHeaderBuffer release];			mHeaderBuffer = 0;
	[_response release];
	[mStringOptions release];
	[mProxies release];
	[super dealloc];
}

/*" %{Initializes a newly created URL handle with the request.}

	#{TODO: initWithRequest ought to clean up better if init failed; release what was allocated.}
"*/

- (id)initWithRequest:(NSURLRequest *)request;
{
#ifdef DEBUGCURL
	NSLog(@"...initWithURL: %@",[request URL]);
#endif
	if (self = [self init])
	{
		mCURL = curl_easy_init();
		if (nil == mCURL)
		{
			return nil;
		}
        
        [self setRequest:request];
		
		mErrorBuffer[0] = 0;	// initialize the error buffer to empty
		mHeaderBuffer = [[NSMutableData alloc] init];
		mStringOptions = [[NSMutableDictionary alloc] init];
				
		// SET OPTIONS -- NOTE THAT WE DON'T SET ANY STRINGS DIRECTLY AT THIS STAGE.
		// Put error messages here
		mResult = curl_easy_setopt(mCURL, CURLOPT_ERRORBUFFER, &mErrorBuffer);
			if(mResult) return nil;

		mResult = curl_easy_setopt(mCURL, CURLOPT_FOLLOWLOCATION, YES);
			if(mResult) return nil;
		mResult = curl_easy_setopt(mCURL, CURLOPT_FAILONERROR, YES);
			if(mResult) return nil;

		// send all data to the C function
		mResult = curl_easy_setopt(mCURL, CURLOPT_WRITEFUNCTION, curlBodyFunction);
			if(mResult) return nil;
		mResult = curl_easy_setopt(mCURL, CURLOPT_HEADERFUNCTION, curlHeaderFunction);
			if(mResult) return nil;
		// pass self to the callback
		mResult = curl_easy_setopt(mCURL, CURLOPT_WRITEHEADER, self);
			if(mResult) return nil;
		mResult = curl_easy_setopt(mCURL, CURLOPT_FILE, self);
			if(mResult) return nil;
	}
	return self;
}

/*" %{Returns the property for key propertyKey; returns nil if there is no such key. Subclasses of NSURLHandle must override this method.}
	
	#{DO NOT INVOKE SUPERCLASS}.
"*/

- (id)propertyForKey:(NSString *)propertyKey
{
	id result = [self propertyForKeyIfAvailable:propertyKey];
	if (nil == result)
	{
		// get some more expensive things...
	}
	return result;
}

/*" %{Returns the property for key propertyKey only if the value is already available, i.e., the client doesn't need to do any work.}

	#{DO NOT INVOKE SUPERCLASS}.
	
	#{TODO: We can't assume any encoding for header.  Perhaps we could look for the encoding value in the header, and try again if it doesn't match?}

	#{TODO: Apple defines some keys, but what the heck are they?  "Description Forthcoming"....}

This first attempts to handle the Apple-defined NSHTTPProperty... keys.  Then if it's HEADER we just return the whole header string.  If it's COOKIES, we return the cookie as an array; this can be further parsed with #parsedCookies:.

Otherwise, we try to get it by just getting a header with that property name (case-insensitive).
"*/

- (id)propertyForKeyIfAvailable:(NSString *)propertyKey
{
	return nil;
}


// -----------------------------------------------------------------------------
#pragma mark ----- CURL DATA LOADING SUPPORT
// -----------------------------------------------------------------------------

/*" %{Loads the receiver's data in the synchronously.}
 
 "*/

- (BOOL)loadInForeground;
{
	BOOL result = NO;
	_cancelled = NO;
    
	[self prepareAndPerformCurl];
	
	if (0 == mResult) result = YES;
	
	return result;
}

/*"	Actually set up for loading and do the perform.  This happens in either
	the foreground or background thread.  Before doing the perform, we collect up
	all the saved-up string-valued options, and set them right before the perform.
	This is because we create temporary (autoreleased) c-strings.
"*/

- (void) prepareAndPerformCurl
{
	struct curl_slist *httpHeaders = nil;
	// Set the options
	NSEnumerator *theEnum = [mStringOptions keyEnumerator];
	NSString *theKey;
	while (nil != (theKey = [theEnum nextObject]) )
	{
		id theObject = [mStringOptions objectForKey:theKey];

		if ([theObject isKindOfClass:[NSNumber class]])
		{
			mResult = curl_easy_setopt(mCURL, [theKey intValue], [theObject intValue]);
		}
		else if ([theObject respondsToSelector:@selector(cString)])
		{
			mResult = curl_easy_setopt(mCURL, [theKey intValue], [theObject cString]);
		}
		else
		{
			NSLog(@"Ignoring CURL option of type %@ for key %@", [theObject class], theKey);
			mResult = 0;	// ignore the option, so don't have an error.
		}
		if (0 != mResult)
		{
			return;
		}
	}

	// Set the proxy info.  Ignore errors -- just don't do proxy if errors.
	if (sAllowsProxy)	// normally this is YES.
	{
		NSString *proxyHost = nil;
		NSNumber *proxyPort = nil;
		NSString *scheme = [[[_request URL] scheme] lowercaseString];

		// Allocate and keep the proxy dictionary
		if (nil == mProxies)
		{
			mProxies = (NSDictionary *) SCDynamicStoreCopyProxies(sSCDSRef);
		}


		if (mProxies
			&& [scheme isEqualToString:@"http"]
			&& [[mProxies objectForKey:NSS(kSCPropNetProxiesHTTPEnable)] boolValue] )
		{
			proxyHost = (NSString *) [mProxies objectForKey:NSS(kSCPropNetProxiesHTTPProxy)];
			proxyPort = (NSNumber *)[mProxies objectForKey:NSS(kSCPropNetProxiesHTTPPort)];
		}
		if (mProxies
			&& [scheme isEqualToString:@"https"]
			&& [[mProxies objectForKey:NSS(kSCPropNetProxiesHTTPSEnable)] boolValue] )
		{
			proxyHost = (NSString *) [mProxies objectForKey:NSS(kSCPropNetProxiesHTTPSProxy)];
			proxyPort = (NSNumber *)[mProxies objectForKey:NSS(kSCPropNetProxiesHTTPSPort)];
		}

		if (mProxies
			&& [scheme isEqualToString:@"ftp"]
			&& [[mProxies objectForKey:NSS(kSCPropNetProxiesFTPEnable)] boolValue] )
		{
			proxyHost = (NSString *) [mProxies objectForKey:NSS(kSCPropNetProxiesFTPProxy)];
			proxyPort = (NSNumber *)[mProxies objectForKey:NSS(kSCPropNetProxiesFTPPort)];
		}
		
		if (proxyHost && proxyPort)
		{
			mResult = curl_easy_setopt(mCURL, CURLOPT_PROXY, [proxyHost UTF8String]);
			mResult = curl_easy_setopt(mCURL, CURLOPT_PROXYPORT, [proxyPort longValue]);

			// Now, provide a user/password if one is globally set.
			if (nil != sProxyUserIDAndPassword)
			{
				mResult = curl_easy_setopt(mCURL, CURLOPT_PROXYUSERPWD, [sProxyUserIDAndPassword UTF8String] );
			}
		}
	}
	
	// Set the HTTP Headers.  (These will override options set with above)
	{
        for (NSString *theKey in [_request allHTTPHeaderFields])
        {
            NSString *theValue = [_request valueForHTTPHeaderField:theKey];
			NSString *pair = [NSString stringWithFormat:@"%@: %@",theKey,theValue];
			httpHeaders = curl_slist_append( httpHeaders, [pair UTF8String] );
        }
		curl_easy_setopt(mCURL, CURLOPT_HTTPHEADER, httpHeaders);
	}

	// Set the URL
	mResult = curl_easy_setopt(mCURL, CURLOPT_URL, [[[_request URL] absoluteString] UTF8String]);
	if (0 != mResult)
	{
		return;
	}
	// clear the buffers
	[mHeaderBuffer setLength:0];	// empty out header buffer
	[_response release]; _response = nil;		// release and invalidate any cached string of header
	
	// Do the transfer
	mResult = curl_easy_perform(mCURL);

	if (nil != mPutFile)
	{
		fclose(mPutFile);
		mPutFile = nil;
	}

	if (nil != httpHeaders)
	{
		curl_slist_free_all(httpHeaders);
	}
}

/*"	Continue the writing callback in Objective C; now we have our instance variables.
"*/

- (size_t) curlWritePtr:(void *)inPtr size:(size_t)inSize number:(size_t)inNumber isHeader:(BOOL)header;
{
	size_t written = inSize*inNumber;
	NSData *data = [NSData dataWithBytes:inPtr length:written];

	if (_cancelled)
	{
		written = -1;		// signify to Curl that we are stopping
							// Do NOT send message; see "cancelLoadInBackground" comments
	}
	else	// Foreground, just write the bytes
	{
		if (header)
		{
			[mHeaderBuffer appendData:data];
		}
		else	// notify delegate of new bytes
		{
			[[self delegate] handle:self didReceiveData:data];
		}
	}
	return written;
}

/*"	Convert curl's error buffer into an NSString if possible, or return the result code number as a string.
"*/

- (NSString *)curlError
{
	NSString *result = [NSString stringWithUTF8String:mErrorBuffer];
	if (nil == result)
	{
		result = [NSString stringWithFormat:@"(curl result code # %d)", mResult];
	}
	return result;
}

/*" Return the current header, as a string. This is meant to be invoked after all
the headers are read; the entire header is cached into a string after converting from raw data. "*/

- (NSHTTPURLResponse *)response
{
#warning We can't really assume a header encoding, trying 7-bit ASCII only.  Maybe there is some way to know?

	if (!_response)		// Has it not been initialized yet?
	{
        NSInteger resultLong;
        mResult = curl_easy_getinfo(mCURL, CURLINFO_HTTP_CODE, &resultLong );
        
		NSString *headerString = [[NSString alloc] initWithData:mHeaderBuffer encoding:NSASCIIStringEncoding];
        _response = [[CURLResponse alloc] initWithURL:[_request URL] statusCode:resultLong headerString:headerString];
        [headerString release];
	}
	return _response;
}

@synthesize delegate = _delegate;

@end

// -----------------------------------------------------------------------------
#pragma mark ----- CATEGORIES
// -----------------------------------------------------------------------------

@implementation NSDictionary ( CurlHTTPExtensions )

/*"	This category adds methods for dealing with HTTP input and output to an #NSDictionary.
"*/

/*"	Convert a dictionary to an HTTP-formatted string with 7-bit ASCII encoding;
	see #formatForHTTPUsingEncoding.
"*/

- (NSString *) formatForHTTP
{
	return [self formatForHTTPUsingEncoding:NSASCIIStringEncoding];
		// default to dumb ASCII only
}

/*"	Convert a dictionary to an HTTP-formatted string with the given encoding.
	Spaces are turned into !{+}; other special characters are escaped with !{%};
	keys and values are output as %{key}=%{value}; in between arguments is !{&}.
"*/

- (NSString *) formatForHTTPUsingEncoding:(NSStringEncoding)inEncoding
{
	return [self formatForHTTPUsingEncoding:inEncoding ordering:nil];
}

/*"	Convert a dictionary to an HTTP-formatted string with the given encoding, as above.  The inOrdering parameter specifies the order to place the inputs, for servers that care about this.  (Note that keys in the dictionary that aren't in inOrdering will not be included.)  If inOrdering is nil, all keys and values will be output in an unspecified order.
"*/

- (NSString *) formatForHTTPUsingEncoding:(NSStringEncoding)inEncoding ordering:(NSArray *)inOrdering
{
	NSMutableString *s = [NSMutableString stringWithCapacity:256];
	NSEnumerator *e = (nil == inOrdering) ? [self keyEnumerator] : [inOrdering objectEnumerator];
	id key;
	CFStringEncoding cfStrEnc = CFStringConvertNSStringEncodingToEncoding(inEncoding);

	while ((key = [e nextObject]))
	{
        id keyObject = [self objectForKey: key];
		// conform with rfc 1738 3.3, also escape URL-like characters that might be in the parameters
		NSString *escapedKey
		= (NSString *) CFURLCreateStringByAddingPercentEscapes(
														 NULL, (CFStringRef) key, NULL, (CFStringRef) @";:@&=/+", cfStrEnc);
        if ([keyObject respondsToSelector: @selector(objectEnumerator)])
        {
            NSEnumerator	*multipleValueEnum = [keyObject objectEnumerator];
            id				aValue;

            while ((aValue = [multipleValueEnum nextObject]))
            {
                NSString *escapedObject
                = (NSString *) CFURLCreateStringByAddingPercentEscapes(
                                                                       NULL, (CFStringRef) [aValue description], NULL, (CFStringRef) @";:@&=/+", cfStrEnc);
                [s appendFormat:@"%@=%@&", escapedKey, escapedObject];
            }
        }
        else
        {
            NSString *escapedObject
            = (NSString *) CFURLCreateStringByAddingPercentEscapes(
                                                                   NULL, (CFStringRef) [keyObject description], NULL, (CFStringRef) @";:@&=/+", cfStrEnc);
            [s appendFormat:@"%@=%@&", escapedKey, escapedObject];
        }
	}
	// Delete final & from the string
	if (![s isEqualToString:@""])
	{
		[s deleteCharactersInRange:NSMakeRange([s length]-1, 1)];
	}
	return s;	
}

@end

@implementation NSString ( CurlHeaderExtensions )

- (NSString *) headerStatus
{
	// Get the first line of the headers
	NSArray *components = [self componentsSeparatedByLineSeparators];
	NSString *theFirstLine = [components objectAtIndex:0];
	// Pull out from the second "word"
	NSArray *theLineComponents = [theFirstLine componentsSeparatedByString: @" "];
	NSRange theRange = NSMakeRange(2, [theLineComponents count] - 2);
	NSString *theResult = [[theLineComponents subarrayWithRange: theRange] componentsJoinedByString: @" "];
	return theResult;
}

- (NSString *) headerHTTPVersion
{
	NSString *result = nil;
	// Get the first "word" of the first line of the headers
	NSRange whereSpace = [self rangeOfString:@" "];
	if (NSNotFound != whereSpace.location)
	{
		result = [self substringToIndex:whereSpace.location];
	}
	return result;
}

/*"	Create an array of values from the HTTP headers string that match the given header key.
"*/

- (NSArray *) headersMatchingKey:(NSString *)inKey
{
	NSMutableArray *result = [NSMutableArray array];
	NSArray *components = [self componentsSeparatedByLineSeparators];
	NSEnumerator *theEnum = [components objectEnumerator];
	NSString *theLine = [theEnum nextObject];		// result code -- ignore
	while (nil != (theLine = [theEnum nextObject]) )
	{
		if ([[theLine headerKey] isEqualToString:inKey])
		{
			// Add it to the resulting array
			[result addObject:[theLine headerValue]];
		}
	}
	return result;
}


/*" Return a the single (first) value of a header.  Returns NULL if not found. "*/

- (NSString *)headerMatchingKey:(NSString *)inKey
{
	NSString *result = nil;
	NSArray *headerArray = [self headersMatchingKey:inKey];
	if ([headerArray count] > 0)
	{
		result = [headerArray objectAtIndex:0];
	}
	return result;
}


/*"	Create a dictionary from the HTTP headers. "*/

- (NSDictionary *) allHTTPHeaderFields;
{
	NSArray *components = [self componentsSeparatedByLineSeparators];
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[components count] - 1];
	
	NSEnumerator *theEnum = [components objectEnumerator];
	NSString *theLine = [theEnum nextObject];		// result code -- ignore
	while (nil != (theLine = [theEnum nextObject]) )
	{
		NSString *key = [theLine headerKey];
		NSString *value = [theLine headerValue];
		if (nil != key && nil != value)
		{
			// Add a single dictionary for this header name/value
			[result setObject:value forKey:key];
		}
	}
	return result;
}

/*" Given a line of a header, e.g. "Foo: Bar" "*/

- (NSString *) headerKey
{
	NSString *result = nil;
	NSRange whereColon = [self rangeOfString:@": "];
	if (NSNotFound != whereColon.location)
	{
		result = [self substringToIndex:whereColon.location];
	}
	return result;
}

/*" Given a line of a header, e.g. "Foo: Bar", return the value in lowercase form, e.g. "bar". "*/

- (NSString *) headerValue
{
	NSString *result = nil;
	NSRange whereColon = [self rangeOfString:@": "];
	if (NSNotFound != whereColon.location)
	{
		result = [self substringFromIndex:whereColon.location + 2];
	}
	return result;
}


/*"	Split a string into lines separated by any of the various newline characters.  Equivalent to componentsSeparatedByString:@"\n" but it works with the different line separators: \r, \n, \r\n, 0x2028, 0x2029 "*/

- (NSArray *) componentsSeparatedByLineSeparators
{
	NSMutableArray *result	= [NSMutableArray array];
	NSRange range = NSMakeRange(0,0);
	unsigned start, end;
	unsigned contentsEnd = 0;
	
	while (contentsEnd < [self length])
	{
		[self getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:range];
		[result addObject:[self substringWithRange:NSMakeRange(start,contentsEnd-start)]];
		range.location = end;
		range.length = 0;
	}
	return result;
}
@end


@implementation CURLResponse

- (id)initWithURL:(NSURL *)URL statusCode:(NSInteger)statusCode headerString:(NSString *)headerString;
{
    NSDictionary *fields = [headerString allHTTPHeaderFields];
    
    if (self = [self initWithURL:URL
                        MIMEType:[fields objectForKey:@"Content-Type"]
           expectedContentLength:[[fields objectForKey:@"Content-Length"] integerValue]
                textEncodingName:[fields objectForKey:@"Content-Encoding"]])
    {
        _statusCode = statusCode;
        _headerFields = [fields copy];
    }
    return self;
}

- (NSInteger)statusCode; { return _statusCode; }
- (NSDictionary *)allHeaderFields; { return _headerFields; }

@end
