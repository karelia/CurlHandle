//
//  CURLMultiTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import "CURLHandleBasedTest.h"

#include <stdio.h>
#include <stdlib.h>
#include <curl/curl.h>
#include <string.h>

#include <dispatch/dispatch.h>

@interface StandaloneNoGCDTest : CURLHandleBasedTest

@end

@implementation StandaloneNoGCDTest

#define log_message(...) fprintf(stderr, __VA_ARGS__)
#define log_error(...) fprintf(stderr, "ERROR: " __VA_ARGS__)

static void add_download(const char *url);


static int remaining = 0;
static int repeats = 20;
static CURLM *curl_handle;

static void curl_perform_wait()
{
    long timeout_ms = -1;
    CURLMcode result = curl_multi_timeout(curl_handle, &timeout_ms);
    if (result != CURLM_OK) log_error("curl_multi_timeout error %d", result);

    if (timeout_ms < 1) timeout_ms = 1;
    if (timeout_ms > 100) timeout_ms = 100; // for the purposes of the test, keep the timeout time to a minimum
    
    int numfds = 0;
    result = curl_multi_wait(curl_handle, NULL, 0, (int)timeout_ms, &numfds);
    if (result != CURLM_OK) log_error("curl_multi_wait error %d", result);

    int numrunning = 0;
    result = curl_multi_perform(curl_handle, &numrunning);
    if (result != CURLM_OK) log_error("curl_multi_perform error %d", result);

    int pending = 0;
    CURLMsg *message;
    while ((message = curl_multi_info_read(curl_handle, &pending))) {
        switch (message->msg) {
            case CURLMSG_DONE:
            {
                const char* done_url;
                CURL* easy = message->easy_handle;
                curl_easy_getinfo(easy, CURLINFO_EFFECTIVE_URL, &done_url);
                CURLcode code = message->data.result;
                printf("%s DONE\ncode:%d - %s\n", done_url, code,
                       curl_easy_strerror(code));

                struct curl_slist* list;
                curl_easy_getinfo(easy, CURLINFO_PRIVATE, &list);

                --remaining;

                if (--repeats)
                {
                    add_download(done_url);
                }

                curl_multi_remove_handle(curl_handle, easy);
                curl_easy_cleanup(easy);
                curl_slist_free_all(list);

                break;
            }
            default:
                log_error("CURLMSG default\n");
                abort();
        }
    }
}


static int debug_func(CURL *curl, curl_infotype infoType, char *info, size_t infoLength, void *userp)
{
    char* string = strndup(info, infoLength);
    fprintf(stderr, "debug %d: %s", infoType, string);
    free(string);
    return 0;
}

static void add_download(const char *url)
{
    CURL *handle = curl_easy_init();
    curl_easy_setopt(handle, CURLOPT_URL, url);
    curl_easy_setopt(handle, CURLOPT_DEBUGFUNCTION, debug_func);
    curl_easy_setopt(handle, CURLOPT_VERBOSE, 1);

    curl_easy_setopt(handle, CURLOPT_URL, url);


    char randomname[CURL_ERROR_SIZE];
    char makecmd[CURL_ERROR_SIZE];
    char chmodcmd[CURL_ERROR_SIZE];
    char delcmd[CURL_ERROR_SIZE];

    sprintf(randomname, "test-%d", rand());


    sprintf(makecmd, "*MKD %s", randomname);
    sprintf(chmodcmd, "SITE CHMOD 0744 %s", randomname);
    sprintf(delcmd, "DELE %s", randomname);

    struct curl_slist* list = curl_slist_append(NULL, makecmd);
    list = curl_slist_append(list, chmodcmd);
    list = curl_slist_append(list, "*DELE file1.txt");
    list = curl_slist_append(list, "*DELE file2.txt");
    list = curl_slist_append(list, delcmd);
    curl_easy_setopt(handle, CURLOPT_PRIVATE, list);
    curl_easy_setopt(handle, CURLOPT_POSTQUOTE, list);

    long timeout = 60;
    curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT, timeout);

    curl_easy_setopt(handle, CURLOPT_NOBODY, 1);

    ++remaining;
    curl_multi_add_handle(curl_handle, handle);
    log_message("Added download %s\n", url);
}

- (void)test_multi_no_gcd
{
    if (!self.usingMockServer)
    {
        // can't run this test with MockServer. It will deadlock, since everything is happening on the main loop.
        if ([self setupServerWithResponseFileNamed:@"ftp"])
        {
            curl_handle = curl_multi_init();

            NSURL* url = [[self ftpTestServer] URLByAppendingPathComponent:@"multinogcd"];
            add_download([[url absoluteString] UTF8String]);

            while(remaining > 0)
            {
                curl_perform_wait(self);
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
            }

            log_message("cleaning up");
            curl_multi_cleanup(curl_handle);
        }
    }
}

@end
