//
//  CURLHandle.m
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.
//

#import "CURLHandle.h"
#import "CURLMulti.h"
#import "CURLResponse.h"

#import "NSString+CURLHandle.h"
#import "NSURLRequest+CURLHandle.h"
#import "CK2SSHCredential.h"

#define NSS(s) (NSString *)(s)
#include <SystemConfiguration/SystemConfiguration.h>


// Un-comment these to do some debugging things
//#define DEBUGCURL 1
//#define DEBUGCURL_SLOW

#pragma mark - Constants

NSString * const CURLcodeErrorDomain = @"se.haxx.curl.libcurl.CURLcode";
NSString * const CURLMcodeErrorDomain = @"se.haxx.curl.libcurl.CURLMcode";
NSString * const CURLSHcodeErrorDomain = @"se.haxx.curl.libcurl.CURLSHcode";

#pragma mark - Globals

BOOL				sAllowsProxy = YES;		// by default, allow proxy to be used./
SCDynamicStoreRef	sSCDSRef = NULL;
NSString			*sProxyUserIDAndPassword = nil;

#pragma mark - Callback Prototypes

int curlSocketOptFunction(CURLHandle *self, curl_socket_t curlfd, curlsocktype purpose);
static size_t curlBodyFunction(void *ptr, size_t size, size_t nmemb, CURLHandle *self);
static size_t curlHeaderFunction(void *ptr, size_t size, size_t nmemb, CURLHandle *self);
static size_t curlReadFunction(void *ptr, size_t size, size_t nmemb, CURLHandle *handle);
static int curlDebugFunction(CURL *mCURL, curl_infotype infoType, char *info, size_t infoLength, CURLHandle *handle);

static int curlKnownHostsFunction(CURL *easy,     /* easy handle */
                                  const struct curl_khkey *knownkey, /* known */
                                  const struct curl_khkey *foundkey, /* found */
                                  enum curl_khmatch, /* libcurl's view on the keys */
                                  CURLHandle *self); /* custom pointer passed from app */

@interface CURLHandle()

#pragma mark - Private Methods

- (size_t) curlWritePtr:(void *)inPtr size:(size_t)inSize number:(size_t)inNumber isHeader:(BOOL)header;
- (size_t) curlReadPtr:(void *)inPtr size:(size_t)inSize number:(size_t)inNumber;

#pragma mark - Private Properties

// TODO: Might be worth splitting out a class to manage curl_slists
@property (readonly, nonatomic) struct curl_slist* httpHeaders;
- (void)addHttpHeader:(NSString *)header;
@property (readonly, nonatomic) struct curl_slist* preQuoteCommands;
- (void)addPreQuoteCommand:(NSString *)command;
@property (readonly, nonatomic) struct curl_slist* postQuoteCommands;
- (void)addPostQuoteCommand:(NSString *)command;

@property(nonatomic, readonly) id <CURLHandleDelegate> delegate;

@end


@implementation CURLHandle

#pragma mark curl_slist Accessor Methods

@synthesize httpHeaders = _httpHeaders;
- (void)addHttpHeader:(NSString *)header;
{
    _httpHeaders = curl_slist_append(_httpHeaders, [header UTF8String]);
}

@synthesize preQuoteCommands = _preQuoteCommands;
- (void)addPreQuoteCommand:(NSString *)command;
{
    _preQuoteCommands = curl_slist_append(_preQuoteCommands, [command UTF8String]);
}

@synthesize postQuoteCommands = _postQuoteCommands;
- (void)addPostQuoteCommand:(NSString *)command;
{
    _postQuoteCommands = curl_slist_append(_postQuoteCommands, [command UTF8String]);
}


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
	return _curl;
}

+ (NSString *) curlVersion
{
	return [NSString stringWithCString: curl_version() encoding:NSASCIIStringEncoding];
}


// -----------------------------------------------------------------------------
#pragma mark ----- NSURLHANDLE OVERRIDES
// -----------------------------------------------------------------------------

- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential delegate:(id <CURLHandleDelegate>)delegate multi:(CURLMulti*)multi
{
    if (self = [self init])
    {
        _URL = [[request URL] copy];
        
        _delegate = delegate;
        
        // Turn automatic redirects off by default, so can properly report them to delegate
        curl_easy_setopt([self curl], CURLOPT_FOLLOWLOCATION, NO);
                
        CURLcode code = [self setupRequest:request credential:credential];
        if (code == CURLE_OK)
        {
            [multi manageHandle:self];
        }
        else
        {
            [self failWithCode:code isMulti:NO];
        }
    }
    
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential delegate:(id <CURLHandleDelegate>)delegate;
{
    return [self initWithRequest:request credential:credential delegate:delegate multi:[CURLMulti sharedInstance]];
}


- (void) dealloc
{
    CURLHandleLog(@"dealloced handle %@ curl %p", self, _curl);

    [self cleanup];

    // NB this is a workaround to fix a bug where an easy handle that was attached to a multi
    // can get accessed when calling curl_multi_cleanup, even though the easy handle has been removed from the multi, and cleaned up itself!
    // see http://curl.haxx.se/mail/lib-2009-10/0222.html
    curl_easy_reset(_curl);

    curl_easy_cleanup(_curl);
    _curl = nil;

    [_URL release];
	[_headerBuffer release];
	[_proxies release];
    [_uploadStream release];

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
		_curl = curl_easy_init();
		if (nil == _curl)
		{
			return nil;
		}
        
        _errorBuffer[0] = 0;	// initialize the error buffer to empty
		_headerBuffer = [[NSMutableData alloc] init];
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

#define LOAD_REQUEST_SET_OPTION(option, parameter) if ((code = curl_easy_setopt(_curl, option, parameter)) != CURLE_OK) return code;

- (CURLcode)setupRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential
{
    NSAssert(_executing == NO, @"CURLHandle instances may not be accessed on multiple threads at once, or re-entrantly");
    _executing = YES;

    _cancelled = NO;

    curl_easy_reset([self curl]);

    CURLcode code = CURLE_OK;

    // SET OPTIONS -- NOTE THAT WE DON'T SET ANY STRINGS DIRECTLY AT THIS STAGE.
    // Put error messages here
    LOAD_REQUEST_SET_OPTION(CURLOPT_ERRORBUFFER, &_errorBuffer);

    LOAD_REQUEST_SET_OPTION(CURLOPT_FOLLOWLOCATION, YES);
    LOAD_REQUEST_SET_OPTION(CURLOPT_FAILONERROR, YES);

    // send all data to the C function
    LOAD_REQUEST_SET_OPTION(CURLOPT_SOCKOPTFUNCTION, curlSocketOptFunction);
    LOAD_REQUEST_SET_OPTION(CURLOPT_SOCKOPTDATA, self);

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

    // store self in the private data, so that we can turn an easy handle back into a CURLHandle object
    LOAD_REQUEST_SET_OPTION(CURLOPT_PRIVATE, self);

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

    
    // SSH Known Hosts
    LOAD_REQUEST_SET_OPTION(CURLOPT_SSH_KNOWNHOSTS, [[[request curl_SSHKnownHostsFileURL] path] UTF8String]);
    LOAD_REQUEST_SET_OPTION(CURLOPT_SSH_KEYDATA, self);
    LOAD_REQUEST_SET_OPTION(CURLOPT_SSH_KEYFUNCTION, curlKnownHostsFunction);
    

    // Set the credential
    if (credential)
    {
        NSString *username = [credential user];
        LOAD_REQUEST_SET_OPTION(CURLOPT_USERNAME, [username UTF8String]);
        
        NSURL *privateKey = [credential ck2_privateKeyURL];
        LOAD_REQUEST_SET_OPTION(CURLOPT_SSH_PUBLIC_KEYFILE, [[privateKey path] UTF8String]);
        
        NSURL *publicKey = [credential ck2_publicKeyURL];
        LOAD_REQUEST_SET_OPTION(CURLOPT_SSH_PUBLIC_KEYFILE, [[publicKey path] UTF8String]);
        
        NSString *password = [credential password];
        if (privateKey)
        {
            LOAD_REQUEST_SET_OPTION(CURLOPT_SSH_AUTH_TYPES, CURLSSH_AUTH_PUBLICKEY);
            LOAD_REQUEST_SET_OPTION(CURLOPT_KEYPASSWD, [password UTF8String]);
        }
        else
        {
            LOAD_REQUEST_SET_OPTION(CURLOPT_SSH_AUTH_TYPES, CURLSSH_AUTH_PASSWORD|CURLSSH_AUTH_KEYBOARD);
            LOAD_REQUEST_SET_OPTION(CURLOPT_PASSWORD, [password UTF8String]);
        }
    }
    

    // Set the proxy info.  Ignore errors -- just don't do proxy if errors.
    if (sAllowsProxy)	// normally this is YES.
    {
        NSString *proxyHost = nil;
        NSNumber *proxyPort = nil;
        NSString *scheme = [[[request URL] scheme] lowercaseString];

        // Allocate and keep the proxy dictionary
        if (nil == _proxies)
        {
            _proxies = (NSDictionary *) SCDynamicStoreCopyProxies(sSCDSRef);
        }


        if (_proxies
            && [scheme isEqualToString:@"http"]
            && [[_proxies objectForKey:NSS(kSCPropNetProxiesHTTPEnable)] boolValue] )
        {
            proxyHost = (NSString *) [_proxies objectForKey:NSS(kSCPropNetProxiesHTTPProxy)];
            proxyPort = (NSNumber *)[_proxies objectForKey:NSS(kSCPropNetProxiesHTTPPort)];
        }
        if (_proxies
            && [scheme isEqualToString:@"https"]
            && [[_proxies objectForKey:NSS(kSCPropNetProxiesHTTPSEnable)] boolValue] )
        {
            proxyHost = (NSString *) [_proxies objectForKey:NSS(kSCPropNetProxiesHTTPSProxy)];
            proxyPort = (NSNumber *)[_proxies objectForKey:NSS(kSCPropNetProxiesHTTPSPort)];
        }

        if (_proxies
            && [scheme isEqualToString:@"ftp"]
            && [[_proxies objectForKey:NSS(kSCPropNetProxiesFTPEnable)] boolValue] )
        {
            proxyHost = (NSString *) [_proxies objectForKey:NSS(kSCPropNetProxiesFTPProxy)];
            proxyPort = (NSNumber *)[_proxies objectForKey:NSS(kSCPropNetProxiesFTPPort)];
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
                [self addHttpHeader:pair];
            }
        }
        LOAD_REQUEST_SET_OPTION(CURLOPT_HTTPHEADER, self.httpHeaders);
    }

    // Set the upload data
    NSData *uploadData = [request HTTPBody];
    if (uploadData)
    {
        _uploadStream = [[NSInputStream alloc] initWithData:uploadData];
        LOAD_REQUEST_SET_OPTION(CURLOPT_INFILESIZE, [uploadData length]);
    }
    else
    {
        _uploadStream = [[request HTTPBodyStream] retain];
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
    //LOAD_REQUEST_SET_OPTION(CURLOPT_CERTINFO, 1L);    // isn't supported by Darwin-SSL backend yet
    LOAD_REQUEST_SET_OPTION(CURLOPT_SSL_VERIFYPEER, (long)[request curl_shouldVerifySSLCertificate]);

    // Intermediate directories
    LOAD_REQUEST_SET_OPTION(CURLOPT_FTP_CREATE_MISSING_DIRS, [request curl_createIntermediateDirectories]);
    
    
    // Permissions
    NSNumber *permissions = [request curl_newFilePermissions];
    if (permissions) LOAD_REQUEST_SET_OPTION(CURLOPT_NEW_FILE_PERMS, [permissions longValue]);
    
    permissions = [request curl_newDirectoryPermissions];
    if (permissions) LOAD_REQUEST_SET_OPTION(CURLOPT_NEW_DIRECTORY_PERMS, [permissions longValue]);
    

    // Pre-quote
    for (NSString *aCommand in [request curl_preTransferCommands])
    {
        [self addPreQuoteCommand:aCommand];
    }
    if (self.preQuoteCommands)
    {
        LOAD_REQUEST_SET_OPTION(CURLOPT_PREQUOTE, self.preQuoteCommands);
    }

    // Post-quote
    for (NSString *aCommand in [request curl_postTransferCommands])
    {
        [self addPostQuoteCommand:aCommand];
    }
    if (self.postQuoteCommands)
    {
        LOAD_REQUEST_SET_OPTION(CURLOPT_POSTQUOTE, self.postQuoteCommands);
    }
    
    
    // Disable EPSV for FTP transfers. I've found that some servers claim to support EPSV but take a very long time to respond to it, if at all, often causing the overall connection to fail. Note IPv6 connections will ignore this and use EPSV anyway
    LOAD_REQUEST_SET_OPTION(CURLOPT_FTP_USE_EPSV, 0);

    // Set the URL
    LOAD_REQUEST_SET_OPTION(CURLOPT_URL, [[[request URL] absoluteString] UTF8String]);

    // clear the buffers
    [_headerBuffer setLength:0];	// empty out header buffer

    return CURLE_OK;
}

- (NSError*)errorForURL:(NSURL*)url code:(CURLcode)code
{
    NSString *description = [NSString stringWithUTF8String:_errorBuffer];

    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                     url, NSURLErrorFailingURLErrorKey,
                                     [url absoluteString], NSURLErrorFailingURLStringErrorKey,
                                     description, NSLocalizedDescriptionKey,
                                     nil];

    long responseCode;
    if (curl_easy_getinfo(_curl, CURLINFO_RESPONSE_CODE, &responseCode) == CURLE_OK && responseCode)
    {
        [userInfo setObject:[NSNumber numberWithLong:responseCode] forKey:[NSNumber numberWithInt:CURLINFO_RESPONSE_CODE]];
    }

    long osErrorNumber = 0;
    if (curl_easy_getinfo(_curl, CURLINFO_OS_ERRNO, &osErrorNumber) == CURLE_OK && osErrorNumber)
    {
        [userInfo setObject:[NSError errorWithDomain:NSPOSIXErrorDomain code:osErrorNumber userInfo:nil]
                     forKey:NSUnderlyingErrorKey];
    }

    NSError* result = [NSError errorWithDomain:CURLcodeErrorDomain code:code userInfo:userInfo];
    [userInfo release];


    // Try to generate a Cocoa-friendly error on top of the raw libCurl one
    switch (code)
    {
        case CURLE_UNSUPPORTED_PROTOCOL:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL underlyingError:result];
            break;

        case CURLE_URL_MALFORMAT:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL underlyingError:result];
            break;

        case CURLE_COULDNT_RESOLVE_HOST:
        case CURLE_FTP_CANT_GET_HOST:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost underlyingError:result];
            break;

        case CURLE_COULDNT_CONNECT:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost underlyingError:result];
            break;
            
        case CURLE_REMOTE_ACCESS_DENIED:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorNoPermissionsToReadFile underlyingError:result];
            break;

        case CURLE_WRITE_ERROR:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotWriteToFile underlyingError:result];
            break;

            //case CURLE_FTP_ACCEPT_TIMEOUT:    seems to have been added in a newer version of Curl than ours
        case CURLE_OPERATION_TIMEDOUT:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut underlyingError:result];
            break;

        case CURLE_SSL_CONNECT_ERROR:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorSecureConnectionFailed underlyingError:result];
            break;

        case CURLE_TOO_MANY_REDIRECTS:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorHTTPTooManyRedirects underlyingError:result];
            break;

        case CURLE_BAD_CONTENT_ENCODING:
            result = [self errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInapplicableStringEncodingError underlyingError:result];
            break;

#if MAC_OS_X_VERSION_10_5 <= MAC_OS_X_VERSION_MAX_ALLOWED || __IPHONE_2_0 <= __IPHONE_OS_VERSION_MAX_ALLOWED
        case CURLE_FILESIZE_EXCEEDED:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum underlyingError:result];
            break;
#endif

#if !defined (MAC_OS_X_VERSION_10_7)
#define MAC_OS_X_VERSION_10_7 (MAC_OS_X_VERSION_MAX_ALLOWED + 1)
#endif

#if MAC_OS_X_VERSION_10_7 <= MAC_OS_X_VERSION_MAX_ALLOWED
        case CURLE_SEND_FAIL_REWIND:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorRequestBodyStreamExhausted underlyingError:result];
            break;
#endif

        case CURLE_LOGIN_DENIED:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorUserAuthenticationRequired underlyingError:result];
            break;

        case CURLE_REMOTE_DISK_FULL:
            result = [self errorWithDomain:NSCocoaErrorDomain code:NSFileWriteOutOfSpaceError underlyingError:result];
            break;

#if !defined (__IPHONE_5_0)
#define __IPHONE_5_0 (__IPHONE_OS_VERSION_MAX_ALLOWED + 1)
#endif

#if MAC_OS_X_VERSION_10_7 <= MAC_OS_X_VERSION_MAX_ALLOWED || __IPHONE_5_0 <= __IPHONE_OS_VERSION_MAX_ALLOWED
        case CURLE_REMOTE_FILE_EXISTS:
            result = [self errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError underlyingError:result];
            break;
#endif

        case CURLE_REMOTE_FILE_NOT_FOUND:
            result = [self errorWithDomain:NSURLErrorDomain code:NSURLErrorResourceUnavailable underlyingError:result];
            break;

        case CURLE_SSL_CACERT:
        {
            struct curl_certinfo *certInfo = NULL;
            if (curl_easy_getinfo(_curl, CURLINFO_CERTINFO, &certInfo) == CURLE_OK)
            {
                // TODO: Extract something interesting from the certificate info. Unfortunately I seem to get back no info!
            }

            break;
        }
        default:
            break;
    }

    return result;
}

- (void)cleanup
{
    if (_uploadStream)
    {
        [_uploadStream close];
    }

    if (_httpHeaders)
    {
        curl_slist_free_all(_httpHeaders);
        _httpHeaders = NULL;
    }
    
    if (_preQuoteCommands)
    {
        curl_slist_free_all(_preQuoteCommands);
        _preQuoteCommands = NULL;
    }

    if (_postQuoteCommands)
    {
        curl_slist_free_all(_postQuoteCommands);
        _postQuoteCommands = NULL;
    }

    _executing = NO;
}

- (BOOL)hasCompleted
{
    return _executing == NO;
}

- (void)completeWithMultiCode:(CURLMcode)code;
{
    if (code == CURLM_OK)
    {
        [self finish];
    }
    else if (code == CURLM_CANCELLED)
    {
        if ([[self delegate] respondsToSelector:@selector(handleWasCancelled:)])
        {
            CURLHandleLog(@"handle %@ cancelled", self);
            [self.delegate handleWasCancelled:self];
        }
    }
    else
    {
        [self failWithCode:code isMulti:YES];
    }

    [self cleanup];
    _delegate = nil;
}

- (void)completeWithCode:(CURLcode)code;
{
    if (code == CURLE_OK)
    {
        [self finish];
    }
    else
    {
        [self failWithCode:code isMulti:NO];
    }

    [self cleanup];
    _delegate = nil;
}

- (void)finish;
{
    [self notifyDelegateOfResponseIfNeeded];
    
    if ([[self delegate] respondsToSelector:@selector(handleDidFinish:)])
    {
        CURLHandleLog(@"handle %@ finished", self);
        [self.delegate handleDidFinish:self];
    }
}

- (void)failWithCode:(int)code isMulti:(BOOL)isMultiCode;
{
    NSError* error = (isMultiCode ?
                      [NSError errorWithDomain:CURLMcodeErrorDomain code:code userInfo:nil] :
                      [self errorForURL:_URL code:code]);
    CURLHandleLog(@"handle %@ failed with error %@", self, error);

    if ([self.delegate respondsToSelector:@selector(handle:didFailWithError:)])
    {
        [self.delegate handle:self didFailWithError:error];
    }
}

- (void)cancel;
{
    CURLHandleLog(@"handle %@ cancelled", self);
    _cancelled = YES;
}

- (NSString *)initialFTPPath;
{
    char *entryPath;
    if (curl_easy_getinfo(_curl, CURLINFO_FTP_ENTRY_PATH, &entryPath) != CURLE_OK) return nil;
    
    return (entryPath ? [NSString stringWithUTF8String:entryPath] : nil);
}

/*"	Continue the writing callback in Objective C; now we have our instance variables.
"*/

- (size_t) curlWritePtr:(void *)inPtr size:(size_t)inSize number:(size_t)inNumber isHeader:(BOOL)header;
{
	size_t written = inSize*inNumber;
    CURLHandleLog(@"handle %@ write %ld at %p", self, written, inPtr);
	NSData *data = [NSData dataWithBytes:inPtr length:written];

	if (_cancelled)
	{
		written = -1;		// signify to Curl that we are stopping
							// Do NOT send message; see "cancelLoadInBackground" comments
	}
	else	// Foreground, just write the bytes
	{
        NSString *dataString = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        NSLog(@"data: %@", dataString);
        [dataString release];

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
            [self notifyDelegateOfResponseIfNeeded];
            
            // Report regular body data
			[[self delegate] handle:self didReceiveData:data];
		}
	}
	return written;
}

// If a response has been buffered, send that off
- (void)notifyDelegateOfResponseIfNeeded;
{
    if ([_headerBuffer length])
    {
        NSString *headerString = [[NSString alloc] initWithData:_headerBuffer encoding:NSASCIIStringEncoding];
        [_headerBuffer setLength:0];
        
        long code;
        if (curl_easy_getinfo(_curl, CURLINFO_RESPONSE_CODE, &code) == CURLE_OK)
        {
            char *urlBuffer;
            if (curl_easy_getinfo(_curl, CURLINFO_EFFECTIVE_URL, &urlBuffer) == CURLE_OK)
            {
                NSString *urlString = [[NSString alloc] initWithUTF8String:urlBuffer];
                if (urlString)
                {
                    NSURL *url = [[NSURL alloc] initWithString:urlString];
                    if (url)
                    {
                        Class responseClass = ([NSHTTPURLResponse instancesRespondToSelector:@selector(initWithURL:statusCode:HTTPVersion:headerFields:)] ? [NSHTTPURLResponse class] : [CURLResponse class]);
                        
                        NSURLResponse *response = [[responseClass alloc] initWithURL:url
                                                                          statusCode:code
                                                                         HTTPVersion:[headerString headerHTTPVersion]
                                                                        headerFields:[headerString allHTTPHeaderFields]];
                        
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
}

- (size_t) curlReadPtr:(void *)inPtr size:(size_t)inSize number:(size_t)inNumber;
{
    CURLHandleLog(@"handle %@ read up to %ld into %p", self, inSize * inNumber, inPtr);
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
        if (_uploadStream.streamStatus == NSStreamStatusAtEnd)
        {
            [[self delegate] handle:self willSendBodyDataOfLength:0];
        }
    }
    
    return result;
}

- (enum curl_khstat)didFindHostFingerprint:(const struct curl_khkey *)foundKey knownFingerprint:(const struct curl_khkey *)knownkey match:(enum curl_khmatch)match;
{
    if ([_delegate respondsToSelector:@selector(handle:didFindHostFingerprint:knownFingerprint:match:)])
    {
        return [_delegate handle:self didFindHostFingerprint:foundKey knownFingerprint:knownkey match:match];
    }
    else
    {
        return (match == CURLKHMATCH_OK ? CURLKHSTAT_FINE : CURLKHSTAT_REJECT);
    }
}

@synthesize delegate = _delegate;

@end

#pragma mark - Callbacks



int curlSocketOptFunction(CURLHandle *self, curl_socket_t curlfd, curlsocktype purpose)
{
    if (purpose == CURLSOCKTYPE_IPCXN)
    {
        // FTP control connections should be kept alive. However, I'm fairly sure this is unlikely to have a real effect in practice since OS X's default time before it starts sending keep alive packets is 2 hours :(
        if ([[[self valueForKey:@"_URL"] scheme] isEqualToString:@"ftp"])
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

size_t curlBodyFunction(void *ptr, size_t size, size_t nmemb, CURLHandle *self)
{
    CURLHandleLog(@"handle %@ got body", self);
	return [self curlWritePtr:ptr size:size number:nmemb isHeader:NO];
}

/*"	Callback from reading a chunk of data.  Since we pass "self" in as the "data pointer",
 we can use that to get back into Objective C and do the work with the class.
 "*/

size_t curlHeaderFunction(void *ptr, size_t size, size_t nmemb, CURLHandle *self)
{
    CURLHandleLog(@"handle %@ got header", self);
	return [self curlWritePtr:ptr size:size number:nmemb isHeader:YES];
}

/*"	Callback to provide a chunk of data for sending.  Since we pass "self" in as the "data pointer",
 we can use that to get back into Objective C and do the work with the class.
 "*/

size_t curlReadFunction( void *ptr, size_t size, size_t nmemb, CURLHandle *self)
{
    return [self curlReadPtr:ptr size:size number:nmemb];
}

// We always log out the debug info in DEBUG builds. We also send everything to the delegate.
// In release builds, we just send header related stuff to the delegate.

#if defined(DEBUG) || defined(_DEBUG)
    #define LOG_DEBUG 1
#else
    #define LOG_DEBUG 0
#endif

int curlDebugFunction(CURL *curl, curl_infotype infoType, char *info, size_t infoLength, CURLHandle *self)
{
    BOOL delegateResponds = [[self delegate] respondsToSelector:@selector(handle:didReceiveDebugInformation:ofType:)];
    if (LOG_DEBUG || delegateResponds)
    {
        BOOL shouldProcess = LOG_DEBUG || (infoType == CURLINFO_HEADER_IN) || (infoType == CURLINFO_HEADER_OUT);
        if (shouldProcess)
        {
            // the length we're passed seems to be unreliable; we use strnlen to ensure that we never go past the infoLength we were given,
            // but often it seems that the string is *much* shorter
            NSUInteger actualLength = strnlen(info, infoLength);

            NSString *string = [[NSString alloc] initWithBytes:info length:actualLength encoding:NSUTF8StringEncoding];
            if (!string)
            {
                // FTP servers are fairly free to use whatever encoding they like. We've run into one that appears to be Hungarian; as far as I can tell ISO Latin 2 is the best compromise for that
                string = [[NSString alloc] initWithBytes:info length:actualLength encoding:NSISOLatin2StringEncoding];
            }

            if (!string)
            {
                // I don't yet know what causes this, but it does happen from time to time. If so, insist that something useful go in the log
                if (infoLength == 0)
                {
                    string = [@"<NULL> debug info" retain];
                }
                else if (infoLength < 100000)
                {
                    string = [[NSString alloc] initWithFormat:@"Invalid debug info: %@", [NSData dataWithBytes:info length:infoLength]];
                }
                else
                {
                    string = [[NSString alloc] initWithFormat:@"Invalid debug info - info length seems to be too big: %ld", infoLength];
                }
            }

            CURLHandleLog(@"CURLHandle %d:  %@", infoType, string);

            if (delegateResponds)
            {
                [[self delegate] handle:self didReceiveDebugInformation:string ofType:infoType];
            }
            
            [string release];
        }
    }

    return 0;
}

int curlKnownHostsFunction(CURL *easy,     /* easy handle */
                           const struct curl_khkey *knownkey, /* known */
                           const struct curl_khkey *foundkey, /* found */
                           enum curl_khmatch match, /* libcurl's view on the keys */
                           CURLHandle *self) /* custom pointer passed from app */
{
    return [self didFindHostFingerprint:foundkey knownFingerprint:knownkey match:match];
}
