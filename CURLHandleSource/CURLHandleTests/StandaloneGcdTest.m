//
//  CURLMultiTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLHandleBasedTest.h"

#include <stdio.h>
#include <stdlib.h>
#include <curl/curl.h>
#include <string.h>

#include <dispatch/dispatch.h>

@interface StandaloneGCDTest : CURLHandleBasedTest

@end

@implementation StandaloneGCDTest


#define log_normal(...) fprintf(stderr, __VA_ARGS__)
#define log_error(...) fprintf(stderr, "ERROR: " __VA_ARGS__)
//#define log_detail(...) fprintf(stderr, __VA_ARGS__)
#define log_detail(...)

static void add_download(const char *url);

static dispatch_queue_t queue;
static int remaining = 0;
static int repeats = 20;
static CURLM *curl_handle;
static dispatch_source_t timeout;

typedef struct curl_handle_context_s {
    CURL *handle;
    struct curl_slist* post_commands;
    const char *full_url;
} curl_handle_context_s;

typedef struct curl_socket_context_s {
    dispatch_source_t read_source;
    dispatch_source_t write_source;
} curl_context_t;

static curl_context_t* create_curl_context()
{
    curl_context_t *context = (curl_context_t *) malloc(sizeof *context);
    memset(context, 0, sizeof(curl_context_t));

    log_detail("created context %p\n", context);

    return context;
}

static void destroy_curl_context(curl_context_t *context)
{
    if (context->read_source)
        dispatch_source_cancel(context->read_source);

    if (context->write_source)
        dispatch_source_cancel(context->write_source);

    log_detail("destroyed context %p\n", context);

    free(context);
}

#pragma mark - socket action support

static void curl_perform_action(int socket, int actions)
{
    int running_handles;
    char *done_url;
    CURLMsg *message;
    int pending;

    curl_multi_socket_action(curl_handle, socket, actions, &running_handles);

    while ((message = curl_multi_info_read(curl_handle, &pending))) {
        switch (message->msg) {
            case CURLMSG_DONE:
            {
                CURL* easy = message->easy_handle;
                curl_easy_getinfo(easy, CURLINFO_EFFECTIVE_URL, &done_url);
                curl_handle_context_s* context = NULL;
                curl_easy_getinfo(easy, CURLINFO_PRIVATE, &context);
                CURLcode code = message->data.result;
                printf("%s DONE\ncode:%d - %s\nremaining:%d\n", done_url, code, curl_easy_strerror(code), --remaining);
                curl_slist_free_all(context->post_commands);

                if (--repeats)
                {
                    const char* full_url = context->full_url;
                    add_download(full_url);
                }

                free(context);


                curl_multi_remove_handle(curl_handle, message->easy_handle);
                curl_easy_cleanup(message->easy_handle);

                break;
            }
            default:
                log_error("CURLMSG default\n");
                abort();
        }
    }
}

static const char* action_name(int action)
{
    return action == CURL_CSELECT_IN ? "read" : "write";
}

#pragma mark - GCD utilities


static dispatch_source_t create_source(dispatch_source_type_t type, int socket, int action)
{
    log_detail("make source socket %d action %s\n", socket, action_name(action));
    dispatch_source_t source = dispatch_source_create(type, socket, 0, queue);
    dispatch_source_set_event_handler(source, ^{
        log_detail("source event socket %d action %s\n", socket, action_name(action));
        curl_perform_action(socket, action);
    });
    dispatch_source_set_cancel_handler(source, ^{
        log_detail("source cancelled socket %d action %s\n", socket, action_name(action));
        dispatch_release(source);
    });

    dispatch_resume(source);
    return source;
}

static void create_timeout()
{
    timeout = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_event_handler(timeout, ^{
        curl_perform_action(CURL_SOCKET_TIMEOUT, 0);
        if (remaining == 0)
        {
            curl_multi_cleanup(curl_handle);
            exit(0);
        }
    });

    dispatch_resume(timeout);
}

#pragma mark - MULTI callbacks

static void timeout_func(CURLM *multi, long timeout_ms, void *userp)
{
    if (timeout_ms <= 0)
        timeout_ms = 1; /* 0 means directly call socket_action, but we'll do it in
                         a bit */

    int64_t timeout_ns = timeout_ms * NSEC_PER_MSEC;
    dispatch_source_set_timer(timeout, DISPATCH_TIME_NOW, timeout_ns, timeout_ns / 100);
}

static int multi_socket_func(CURL *easy, curl_socket_t s, int action, void *userp, void *socketp)
{
    curl_context_t *curl_context = (curl_context_t*) socketp;

    if (action == CURL_POLL_IN || action == CURL_POLL_OUT) {
        if (!curl_context) {
            curl_context = create_curl_context();
            curl_multi_assign(curl_handle, s, (void *) curl_context);
        }
    }

    switch (action) {
        case CURL_POLL_IN:
            curl_context->read_source = create_source(DISPATCH_SOURCE_TYPE_READ, s, CURL_CSELECT_IN);
            break;

        case CURL_POLL_OUT:
            curl_context->write_source = create_source(DISPATCH_SOURCE_TYPE_WRITE, s, CURL_CSELECT_OUT);
            break;

        case CURL_POLL_REMOVE:
            if (curl_context) {
                destroy_curl_context(curl_context);
                curl_multi_assign(curl_handle, s, NULL);
            }
            break;
        default:
            abort();
    }

    return 0;
}

#pragma mark - Top Level

static void add_download(const char *url)
{
    CURL *handle;

    handle = curl_easy_init();

    curl_handle_context_s* context = malloc(sizeof *context);
    memset(context, 0, sizeof *context);
    context->handle = handle;
    context->post_commands = NULL;
    context->full_url = strdup(url);
    curl_easy_setopt(handle, CURLOPT_PRIVATE, context);
    curl_easy_setopt(handle, CURLOPT_URL, url);


    char randomname[CURL_ERROR_SIZE];
    char makecmd[CURL_ERROR_SIZE];
    char chmodcmd[CURL_ERROR_SIZE];
    char delcmd[CURL_ERROR_SIZE];

    sprintf(randomname, "test-%d", rand());


    sprintf(makecmd, "*MKD %s", randomname);
    sprintf(chmodcmd, "SITE CHMOD 0744 %s", randomname);
    sprintf(delcmd, "DELE %s", randomname);

    context->post_commands = curl_slist_append(context->post_commands, makecmd);
    context->post_commands = curl_slist_append(context->post_commands, chmodcmd);
    context->post_commands = curl_slist_append(context->post_commands, "*DELE file1.txt");
    context->post_commands = curl_slist_append(context->post_commands, "*DELE file2.txt");
    context->post_commands = curl_slist_append(context->post_commands, delcmd);

    curl_easy_setopt(handle, CURLOPT_POSTQUOTE, context->post_commands);

    long timeout = 60;
    curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT, timeout);

    curl_easy_setopt(handle, CURLOPT_NOBODY, 1);
    
    dispatch_async(queue, ^{
        curl_multi_add_handle(curl_handle, handle);
        log_normal("Added download %s\n", url);
        ++remaining;
    });
}

- (void)test_multi_gcd
{
    queue = dispatch_queue_create("curl gcd test queue", 0);

    create_timeout(self);

    curl_handle = curl_multi_init();
    curl_multi_setopt(curl_handle, CURLMOPT_SOCKETFUNCTION, multi_socket_func);
    curl_multi_setopt(curl_handle, CURLMOPT_TIMERFUNCTION, timeout_func);

    NSURL* url = [[self ftpTestServer] URLByAppendingPathComponent:@"multigcd"];
    add_download([[url absoluteString] UTF8String]);
    
    [self runUntilPaused];
}

@end
