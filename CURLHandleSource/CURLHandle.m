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


NSString * const CURLcodeErrorDomain = @"se.haxx.curl.libcurl.CURLcode";
NSString * const CURLMcodeErrorDomain = @"se.haxx.curl.libcurl.CURLMcode";
NSString * const CURLSHcodeErrorDomain = @"se.haxx.curl.libcurl.CURLSHcode";

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


int curlSocketOptFunction(NSURL *URL, curl_socket_t curlfd, curlsocktype purpose)
{
    if (purpose == CURLSOCKTYPE_IPCXN)
    {
        // FTP control connections should be kept alive. However, I'm fairly sure this is unlikely to have a real effect in practice since OS X's default time before it starts sending keep alive packets is 2 hours :(
        if ([[URL scheme] isEqualToString:@"ftp"])
        {
            int keepAlive = 1;
            socklen_t keepAliveLen = sizeof(keepAlive);
            int result = setsockopt(curlfd, SOL_SOCKET, SO_KEEPALIVE, &keepAlive, keepAliveLen);
            
            if (result)
            {
                NSLog(@"Unable to set FTP control connection keepalive with error:%i", result);
                return 1;
            }
        }
    }
    
    return 0;
}

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

/*"	Callback to provide a chunk of data for sending.  Since we pass "self" in as the "data pointer",
 we can use that to get back into Objective C and do the work with the class.
 "*/

size_t curlReadFunction( void *ptr, size_t size, size_t nmemb, CURLHandle *self)
{
    return [self curlReadPtr:ptr size:size number:nmemb];
}

int curlDebugFunction(CURL *mCURL, curl_infotype infoType, char *info, size_t infoLength, CURLHandle *self)
{
    if (infoType != CURLINFO_HEADER_IN && infoType != CURLINFO_HEADER_OUT) return 0;
    if (![[self delegate] respondsToSelector:@selector(handle:didReceiveDebugInformation:ofType:)]) return 0;
    
    
    NSString *string = [[NSString alloc] initWithBytes:info length:infoLength encoding:NSUTF8StringEncoding];
    if (!string)
    {
        // FTP servers are fairly free to use whatever encoding they like. We've run into one that appears to be Hungarian; as far as I can tell ISO Latin 2 is the best compromise for that
        string = [[NSString alloc] initWithBytes:info length:infoLength encoding:NSISOLatin2StringEncoding];
    }
    
    if (!string)
    {
        // I don't yet know what causes this, but it does happen from time to time. If so, insist that something useful go in the log
        if (infoLength == 0)
        {
            string = [@"<NULL> debug info" retain];
        }
        else
        {
            string = [[NSString alloc] initWithFormat:@"Invalid debug info: %@", [NSData dataWithBytes:info length:infoLength]];
        }
    }
    
    [[self delegate] handle:self didReceiveDebugInformation:string ofType:infoType];
    [string release];
    
    return 0;
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

/*" Initialize CURLHandle and the underlying CURL.  This can be invoked when the program is launched or before any loading is needed.
"*/

+ (void)initialize
{
	CURLcode rc = curl_global_init(CURL_GLOBAL_ALL);
	if (rc != CURLE_OK)
	{
		NSLog(@"Didn't curl_global_init, result = %d",rc);
	}
	
	// Now initialize System Config. I have no idea why this signature; it's just what was in tester app
	sSCDSRef = SCDynamicStoreCreate(NULL,CFSTR("XxXx"),NULL, NULL);
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

- (void) setString:(NSString *)inString forKey:(CURLoption) inCurlOption
{
	[mStringOptions setObject:inString forKey:[NSNumber numberWithInt:inCurlOption]];
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
	[_headerBuffer release];
	[mStringOptions release];
	[mProxies release];
	[super dealloc];
}

/*" %{Initializes a newly created URL handle with the request.}

	#{TODO: initWithRequest ought to clean up better if init failed; release what was allocated.}
"*/

- (id)init
{
#ifdef DEBUGCURL
	NSLog(@"...initWithURL: %@",[request URL]);
#endif
	if (self = [super init])
	{
		mCURL = curl_easy_init();
		if (nil == mCURL)
		{
			return nil;
		}
        
        mErrorBuffer[0] = 0;	// initialize the error buffer to empty
		_headerBuffer = [[NSMutableData alloc] init];
		mStringOptions = [[NSMutableDictionary alloc] init];
	}
	return self;
}


// -----------------------------------------------------------------------------
#pragma mark ----- CURL DATA LOADING SUPPORT
// -----------------------------------------------------------------------------

/*""*/

- (NSError *)errorWithDomain:(NSString *)domain code:(NSInteger)code underlyingError:(NSError *)underlyingError;
{
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] initWithDictionary:[underlyingError userInfo]];
    [userInfo setObject:underlyingError forKey:NSUnderlyingErrorKey];
    
    NSError *result = [NSError errorWithDomain:domain code:code userInfo:userInfo];
    [userInfo release];
    return result;
}

/*" %{Loads the receiver's data in the synchronously.}
 
 	Actually set up for loading and do the perform.  This happens in either
	the foreground or background thread.  Before doing the perform, we collect up
	all the saved-up string-valued options, and set them right before the perform.
	This is because we create temporary (autoreleased) c-strings.
"*/

- (BOOL)loadRequest:(NSURLRequest *)request error:(NSError **)error;
{
    NSAssert(_executing == NO, @"CURLHandle instances may not be accessed on multiple threads at once, or re-entrantly");
    _executing = YES;
    
    [self retain];  // so can't be accidentally deallocated mid-operation
	_cancelled = NO;
    
    CURLcode code = CURLE_OK;
    struct curl_slist *httpHeaders = NULL;
    struct curl_slist *postQuoteCommands = NULL;
    
    @try
    {
        curl_easy_reset([self curl]);
        
#define LOAD_REQUEST_SET_OPTION(option, parameter) if ((code = curl_easy_setopt(mCURL, option, parameter))) return NO;

		// SET OPTIONS -- NOTE THAT WE DON'T SET ANY STRINGS DIRECTLY AT THIS STAGE.
		// Put error messages here
        LOAD_REQUEST_SET_OPTION(CURLOPT_ERRORBUFFER, &mErrorBuffer);
                
		LOAD_REQUEST_SET_OPTION(CURLOPT_FOLLOWLOCATION, YES);
		LOAD_REQUEST_SET_OPTION(CURLOPT_FAILONERROR, YES);
        
		// send all data to the C function
        LOAD_REQUEST_SET_OPTION(CURLOPT_SOCKOPTFUNCTION, curlSocketOptFunction);
        LOAD_REQUEST_SET_OPTION(CURLOPT_SOCKOPTDATA, [request URL]);
        
		LOAD_REQUEST_SET_OPTION(CURLOPT_WRITEFUNCTION, curlBodyFunction);
		LOAD_REQUEST_SET_OPTION(CURLOPT_HEADERFUNCTION, curlHeaderFunction);
		LOAD_REQUEST_SET_OPTION(CURLOPT_READFUNCTION, curlReadFunction);
		// pass self to the callback
		LOAD_REQUEST_SET_OPTION(CURLOPT_WRITEHEADER, self);
		LOAD_REQUEST_SET_OPTION(CURLOPT_FILE, self);
		LOAD_REQUEST_SET_OPTION(CURLOPT_READDATA, self);
        
		LOAD_REQUEST_SET_OPTION(CURLOPT_VERBOSE, 1);
		LOAD_REQUEST_SET_OPTION(CURLOPT_DEBUGFUNCTION, curlDebugFunction);
		LOAD_REQUEST_SET_OPTION(CURLOPT_DEBUGDATA, self);
        
        
        /*"	Zero disables connection timeout (it
         will then only timeout on the system's internal
         timeouts).
         
            According to man 3 curl_easy_setopt, CURLOPT_CONNECTTIMEOUT uses signals and thus isn't thread-safe. However, in the same man page it's stated that if you TURN OFF SIGNALLING, you can still use CURLOPT_CONNECTTIMEOUT! This will DISABLE any features that use signals, so beware! (But turning off the connection timeout by setting to zero will turn it back on.)
         
            CURLOPT_TIMEOUT is for how long the entire transfer takes, which doesn't match up to -timeoutInterval's definition. I'm leaving it out for now. Perhaps a progress callback, or minimum transfer speed requirement could manage the eventuality of a transfer hanging mid-way.
         
         "*/
        
        long timeout = (long)[request timeoutInterval];
        LOAD_REQUEST_SET_OPTION(CURLOPT_NOSIGNAL, timeout != 0);
        LOAD_REQUEST_SET_OPTION(CURLOPT_CONNECTTIMEOUT, timeout);
        //LOAD_REQUEST_SET_OPTION(CURLOPT_TIMEOUT, timeout);
        
        // Make FTP response time shorter so that when faced with a server which turns out not to receive EPSV connections, can fall back to PASV in time
        // It seems that on OS X 10.6, this behaves as the maximum time a transfer can take, likely killing the connection for large files, so don't want it. Not supporting EPSV at present anyhow
        //LOAD_REQUEST_SET_OPTION(CURLOPT_FTP_RESPONSE_TIMEOUT, 0.5 * timeout);
        

        
        // Set the options
        NSEnumerator *theEnum = [mStringOptions keyEnumerator];
        NSString *theKey;
        while (nil != (theKey = [theEnum nextObject]) )
        {
            id theObject = [mStringOptions objectForKey:theKey];
            
            if ([theObject isKindOfClass:[NSNumber class]])
            {
                LOAD_REQUEST_SET_OPTION([theKey intValue], [theObject intValue]);
            }
            else if ([theObject respondsToSelector:@selector(cString)])
            {
                LOAD_REQUEST_SET_OPTION([theKey intValue], [theObject UTF8String]);
            }
            else
            {
                NSLog(@"Ignoring CURL option of type %@ for key %@", [theObject class], theKey);
            }
        }
        
        // Set the proxy info.  Ignore errors -- just don't do proxy if errors.
        if (sAllowsProxy)	// normally this is YES.
        {
            NSString *proxyHost = nil;
            NSNumber *proxyPort = nil;
            NSString *scheme = [[[request URL] scheme] lowercaseString];
            
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
                LOAD_REQUEST_SET_OPTION(CURLOPT_PROXY, [proxyHost UTF8String]);
                LOAD_REQUEST_SET_OPTION(CURLOPT_PROXYPORT, [proxyPort longValue]);
                
                // Now, provide a user/password if one is globally set.
                if (nil != sProxyUserIDAndPassword)
                {
                    LOAD_REQUEST_SET_OPTION(CURLOPT_PROXYUSERPWD, [sProxyUserIDAndPassword UTF8String]);
                }
            }
        }
        
        // HTTP method
        NSString *method = [request HTTPMethod];
        if ([method isEqualToString:@"GET"])
        {
            LOAD_REQUEST_SET_OPTION(CURLOPT_HTTPGET, 1);
        }
        else if ([method isEqualToString:@"HEAD"])
        {
            LOAD_REQUEST_SET_OPTION(CURLOPT_NOBODY, 1);
        }
        else if ([method isEqualToString:@"PUT"])
        {
            LOAD_REQUEST_SET_OPTION(CURLOPT_UPLOAD, 1L);
        }
        else if ([method isEqualToString:@"POST"])
        {
            LOAD_REQUEST_SET_OPTION(CURLOPT_POST, 1);
        }
        else
        {
            LOAD_REQUEST_SET_OPTION(CURLOPT_CUSTOMREQUEST, [method UTF8String]);
        }
        
        // Set the HTTP Headers.  (These will override options set with above)
        {
            for (NSString *aHeaderField in [request allHTTPHeaderFields])
            {
                NSString *theValue = [request valueForHTTPHeaderField:aHeaderField];
                
                // Range requests are a special case that should inform Curl directly
#define HTTP_RANGE_PREFIX @"bytes="
                if ([aHeaderField caseInsensitiveCompare:@"Range"] == NSOrderedSame &&
                    [theValue hasPrefix:HTTP_RANGE_PREFIX])
                {
                    LOAD_REQUEST_SET_OPTION(CURLOPT_RANGE, [[theValue substringFromIndex:[HTTP_RANGE_PREFIX length]] UTF8String]);
                }
                
                // Accept-Encoding requests are also special
                else if ([aHeaderField caseInsensitiveCompare:@"Accept-Encoding"] == NSOrderedSame)
                {
                    LOAD_REQUEST_SET_OPTION(CURLOPT_ENCODING, [theValue UTF8String]);
                }
                
                else
                {
                    NSString *pair = [NSString stringWithFormat:@"%@: %@",aHeaderField,theValue];
                    httpHeaders = curl_slist_append( httpHeaders, [pair UTF8String] );
                }
            }
            LOAD_REQUEST_SET_OPTION(CURLOPT_HTTPHEADER, httpHeaders);
        }
        
        // Set the upload data
        NSData *uploadData = [request HTTPBody];
        if (uploadData)
        {
            _uploadStream = [[[NSInputStream alloc] initWithData:uploadData] autorelease];
            LOAD_REQUEST_SET_OPTION(CURLOPT_INFILESIZE, [uploadData length]);
        }
        else
        {
            _uploadStream = [request HTTPBodyStream];
        }
        
        if (_uploadStream)
        {
            [_uploadStream open];
            LOAD_REQUEST_SET_OPTION(CURLOPT_UPLOAD, 1L);
        }
        else
        {
            LOAD_REQUEST_SET_OPTION(CURLOPT_UPLOAD, 0);
        }
        
        // SSL
        LOAD_REQUEST_SET_OPTION(CURLOPT_USE_SSL, (long)[request curl_desiredSSLLevel]);
        LOAD_REQUEST_SET_OPTION(CURLOPT_CERTINFO, 1L);
        LOAD_REQUEST_SET_OPTION(CURLOPT_SSL_VERIFYPEER, (long)[request curl_shouldVerifySSLCertificate]);
        
        // Intermediate directories
        LOAD_REQUEST_SET_OPTION(CURLOPT_FTP_CREATE_MISSING_DIRS, [request curl_createIntermediateDirectories]);
        
        
        // Post-quote
        for (NSString *aCommand in [request curl_postTransferCommands])
        {
            postQuoteCommands = curl_slist_append(postQuoteCommands, [aCommand UTF8String]);
        }
        if (postQuoteCommands)
        {
            LOAD_REQUEST_SET_OPTION(CURLOPT_POSTQUOTE, postQuoteCommands);
        }
        
        // Disable EPSV for FTP transfers. I've found that some servers claim to support EPSV but take a very long time to respond to it, if at all, often causing the overall connection to fail. Note IPv6 connections will ignore this and use EPSV anyway
        LOAD_REQUEST_SET_OPTION(CURLOPT_FTP_USE_EPSV, 0);
        
        // Set the URL
        LOAD_REQUEST_SET_OPTION(CURLOPT_URL, [[[request URL] absoluteString] UTF8String]);
        
        // clear the buffers
        [_headerBuffer setLength:0];	// empty out header buffer
        
        // Do the transfer
        code = curl_easy_perform(mCURL);
    }
    @finally
    {
        // Cleanup
        [_uploadStream close];
        if (httpHeaders) curl_slist_free_all(httpHeaders);
        if (postQuoteCommands) curl_slist_free_all(postQuoteCommands);
        
        _executing = NO;
        
        if (code != CURLE_OK)
        {
            if (error)
            {
                NSURL *url = [request URL];
                NSString *description = [NSString stringWithUTF8String:mErrorBuffer];
                
                NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                                 url, NSURLErrorFailingURLErrorKey,
                                                 [url absoluteString], NSURLErrorFailingURLStringErrorKey,
                                                 description, NSLocalizedDescriptionKey,
                                                 nil];
                
                long responseCode;
                if (curl_easy_getinfo(mCURL, CURLINFO_RESPONSE_CODE, &responseCode) == CURLE_OK && responseCode)
                {
                    [userInfo setObject:[NSNumber numberWithLong:responseCode] forKey:[NSNumber numberWithInt:CURLINFO_RESPONSE_CODE]];
                }
                
                long osErrorNumber = 0;
                if (curl_easy_getinfo(mCURL, CURLINFO_OS_ERRNO, &osErrorNumber) == CURLE_OK && osErrorNumber)
                {
                    [userInfo setObject:[NSError errorWithDomain:NSPOSIXErrorDomain code:osErrorNumber userInfo:nil]
                                 forKey:NSUnderlyingErrorKey];
                }
                
                *error = [NSError errorWithDomain:CURLcodeErrorDomain
                                             code:code
                                         userInfo:userInfo];
                [userInfo release];
                
                
                // Try to generate a Cocoa-friendly error on top of the raw libCurl one
                switch (code)
                {
                    case CURLE_UNSUPPORTED_PROTOCOL:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL underlyingError:*error];
                        break;
                        
                    case CURLE_URL_MALFORMAT:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL underlyingError:*error];
                        break;
                        
                    case CURLE_COULDNT_RESOLVE_HOST:
                    case CURLE_FTP_CANT_GET_HOST:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost underlyingError:*error];
                        break;
                        
                    case CURLE_COULDNT_CONNECT:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost underlyingError:*error];
                        break;
                        
                    case CURLE_WRITE_ERROR:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotWriteToFile underlyingError:*error];
                        break;
                        
                    //case CURLE_FTP_ACCEPT_TIMEOUT:    seems to have been added in a newer version of Curl than ours
                    case CURLE_OPERATION_TIMEDOUT:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut underlyingError:*error];
                        break;
                        
                    case CURLE_SSL_CONNECT_ERROR:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorSecureConnectionFailed underlyingError:*error];
                        break;
                        
                    case CURLE_TOO_MANY_REDIRECTS:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorHTTPTooManyRedirects underlyingError:*error];
                        break;
                        
                    case CURLE_BAD_CONTENT_ENCODING:
                        *error = [self errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInapplicableStringEncodingError underlyingError:*error];
                        break;
                        
#if MAC_OS_X_VERSION_10_5 <= MAC_OS_X_VERSION_MAX_ALLOWED || __IPHONE_2_0 <= __IPHONE_OS_VERSION_MAX_ALLOWED
                    case CURLE_FILESIZE_EXCEEDED:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum underlyingError:*error];
                        break;
#endif
                        
#if !defined (MAC_OS_X_VERSION_10_7)
#define MAC_OS_X_VERSION_10_7 (MAC_OS_X_VERSION_MAX_ALLOWED + 1)
#endif
                        
#if MAC_OS_X_VERSION_10_7 <= MAC_OS_X_VERSION_MAX_ALLOWED
                    case CURLE_SEND_FAIL_REWIND:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorRequestBodyStreamExhausted underlyingError:*error];
                        break;
#endif
                        
                    case CURLE_LOGIN_DENIED:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorUserAuthenticationRequired underlyingError:*error];
                        break;
                        
                    case CURLE_REMOTE_DISK_FULL:
                        *error = [self errorWithDomain:NSCocoaErrorDomain code:NSFileWriteOutOfSpaceError underlyingError:*error];
                        break;
                        
#if !defined (__IPHONE_5_0)
#define __IPHONE_5_0 (__IPHONE_OS_VERSION_MAX_ALLOWED + 1)
#endif
                        
#if MAC_OS_X_VERSION_10_7 <= MAC_OS_X_VERSION_MAX_ALLOWED || __IPHONE_5_0 <= __IPHONE_OS_VERSION_MAX_ALLOWED
                    case CURLE_REMOTE_FILE_EXISTS:
                        *error = [self errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError underlyingError:*error];
                        break;
#endif
                        
                    case CURLE_REMOTE_FILE_NOT_FOUND:
                        *error = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorResourceUnavailable underlyingError:*error];
                        break;
                        
                    case CURLE_SSL_CACERT:
                    {
                        struct curl_certinfo *certInfo = NULL;
                        if (curl_easy_getinfo(mCURL, CURLINFO_CERTINFO, &certInfo) == CURLE_OK)
                        {
                            // TODO: Extract something interesting from the certificate info. Unfortunately I seem to get back no info!
                        }
                        
                        break;
                    }
                    default:
                        break;
                }
            }
            
            [self release]; // was retained at start
            return NO;
        }
    }
    
    [self release]; // was retained at start
    return YES;
}

- (void)cancel;
{
    _cancelled = YES;
}

- (NSString *)initialFTPPath;
{
    char *entryPath;
    if (curl_easy_getinfo(mCURL, CURLINFO_FTP_ENTRY_PATH, &entryPath) != CURLE_OK) return nil;
    
    return (entryPath ? [NSString stringWithUTF8String:entryPath] : nil);
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
            // Delegate might not care about the response
            if ([[self delegate] respondsToSelector:@selector(handle:didReceiveResponse:)])
            {
                [_headerBuffer appendData:data];
            }
		}
		else
		{
            // Once the body starts arriving, we know we have the full header, so can report that
            if ([_headerBuffer length])
            {
                NSString *headerString = [[NSString alloc] initWithData:_headerBuffer encoding:NSASCIIStringEncoding];
                [_headerBuffer setLength:0];
                
                long code;
                if (curl_easy_getinfo(mCURL, CURLINFO_HTTP_CODE, &code) == CURLE_OK)
                {
                    char *urlBuffer;
                    if (curl_easy_getinfo(mCURL, CURLINFO_EFFECTIVE_URL, &urlBuffer) == CURLE_OK)
                    {
                        NSString *urlString = [[NSString alloc] initWithUTF8String:urlBuffer];
                        if (urlString)
                        {
                            NSURL *url = [[NSURL alloc] initWithString:urlString];
                            if (url)
                            {
                                NSURLResponse *response = [[CURLResponse alloc] initWithURL:url
                                                                                 statusCode:code
                                                                               headerString:headerString];
                                
                                [[self delegate] handle:self didReceiveResponse:response];
                                [response release];
                                [url release];
                            }
                            
                            [urlString release];
                        }
                        
                    }
                }
				[headerString release];
            }
            
            
            // Report regular body data
			[[self delegate] handle:self didReceiveData:data];
		}
	}
	return written;
}

- (size_t) curlReadPtr:(void *)inPtr size:(size_t)inSize number:(size_t)inNumber;
{
    if (_cancelled) return CURL_READFUNC_ABORT;
    
    NSInteger result = [_uploadStream read:inPtr maxLength:inSize * inNumber];
    if (result < 0)
    {
        if ([[self delegate] respondsToSelector:@selector(handle:didReceiveDebugInformation:ofType:)])
        {
            NSError *error = [_uploadStream streamError];
            
            [[self delegate] handle:self
         didReceiveDebugInformation:[NSString stringWithFormat:@"Read failed: %@", [error debugDescription]]
                             ofType:CURLINFO_HEADER_IN];
        }
        
        return CURL_READFUNC_ABORT;
    }
    
    if (result >= 0 && [[self delegate] respondsToSelector:@selector(handle:willSendBodyDataOfLength:)])
    {
        [[self delegate] handle:self willSendBodyDataOfLength:result];
    }
    
    return result;
}

@synthesize delegate = _delegate;

@end

// -----------------------------------------------------------------------------
#pragma mark ----- CATEGORIES
// -----------------------------------------------------------------------------

#pragma mark -


@implementation NSURLRequest (CURLOptionsFTP)

- (curl_usessl)curl_desiredSSLLevel;
{
    return [[NSURLProtocol propertyForKey:@"curl_desiredSSLLevel" inRequest:self] longValue];
}

- (BOOL)curl_shouldVerifySSLCertificate;
{
    NSNumber *result = [NSURLProtocol propertyForKey:@"curl_shouldVerifySSLCertificate" inRequest:self];
    return (result ? [result boolValue] : YES);
}

- (NSArray *)curl_postTransferCommands;
{
    return [NSURLProtocol propertyForKey:@"curl_postTransferCommands" inRequest:self];
}

- (NSUInteger)curl_createIntermediateDirectories;
{
    return [[NSURLProtocol propertyForKey:@"curl_createIntermediateDirectories" inRequest:self] unsignedIntegerValue];
}

@end

@implementation NSMutableURLRequest (CURLOptionsFTP)

- (void)curl_setDesiredSSLLevel:(curl_usessl)level;
{
    [NSURLProtocol setProperty:[NSNumber numberWithLong:level] forKey:@"curl_desiredSSLLevel" inRequest:self];
}

- (void)curl_setShouldVerifySSLCertificate:(BOOL)verify;
{
    [NSURLProtocol setProperty:[NSNumber numberWithBool:verify] forKey:@"curl_shouldVerifySSLCertificate" inRequest:self];
}

- (void)curl_setPostTransferCommands:(NSArray *)commands;
{
    if (commands)
    {
        commands = [commands copy];
        [NSURLProtocol setProperty:commands forKey:@"curl_postTransferCommands" inRequest:self];
        [commands release];
    }
    else
    {
        [NSURLProtocol removePropertyForKey:@"curl_postTransferCommands" inRequest:self];
    }
}

- (void)curl_setCreateIntermediateDirectories:(NSUInteger)value;
{
    [NSURLProtocol setProperty:[NSNumber numberWithUnsignedInteger:value] forKey:@"curl_createIntermediateDirectories" inRequest:self];
}

@end


#pragma mark -


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
				[escapedObject release];
            }
        }
        else
        {
            NSString *escapedObject
            = (NSString *) CFURLCreateStringByAddingPercentEscapes(
                                                                   NULL, (CFStringRef) [keyObject description], NULL, (CFStringRef) @";:@&=/+", cfStrEnc);
            [s appendFormat:@"%@=%@&", escapedKey, escapedObject];
			[escapedObject release];
        }
		[escapedKey release];
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
	(void)theLine;
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
	(void)theLine;
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
	NSUInteger start, end;
	NSUInteger contentsEnd = 0;
	
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
