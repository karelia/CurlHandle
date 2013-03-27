/***************************************************************************
 *                                  _   _ ____  _
 *  Project                     ___| | | |  _ \| |
 *                             / __| | | | |_) | |
 *                            | (__| |_| |  _ <| |___
 *                             \___|\___/|_| \_\_____|
 *
 * Copyright (C) 1998 - 2013, Daniel Stenberg, <daniel@haxx.se>, et al.
 *
 * This software is licensed as described in the file COPYING, which
 * you should have received as part of this distribution. The terms
 * are also available at http://curl.haxx.se/docs/copyright.html.
 *
 * You may opt to use, copy, modify, merge, publish, distribute and/or sell
 * copies of the Software, and permit persons to whom the Software is
 * furnished to do so, under the terms of the COPYING file.
 *
 * This software is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY
 * KIND, either express or implied.
 *
 ***************************************************************************/

/* Example application code using the multi socket interface to download
 multiple files at once, but instead of using curl_multi_perform and
 curl_multi_wait, which uses select(), we use libuv.
 It supports epoll, kqueue, etc. on unixes and fast IO completion ports on
 Windows, which means, it should be very fast on all platforms..

 Written by Clemens Gruber, based on an outdated example from uvbook and
 some tests from libuv.

 Requires libuv and (of course) libcurl.

 See http://nikhilm.github.com/uvbook/ for more information on libuv.
 */

#include <stdio.h>
#include <stdlib.h>
#include <curl/curl.h>
#include <string.h>

#include <dispatch/dispatch.h>

dispatch_queue_t queue;

CURLM *curl_handle;
dispatch_source_t timeout;

typedef struct curl_context_s {
    dispatch_source_t read_source;
    dispatch_source_t write_source;
} curl_context_t;

curl_context_t* create_curl_context()
{
    curl_context_t *context = (curl_context_t *) malloc(sizeof *context);
    memset(context, 0, sizeof(curl_context_t));

    fprintf(stderr, "created context %p\n", context);
    
    return context;
}

void destroy_curl_context(curl_context_t *context)
{
    if (context->read_source)
        dispatch_source_cancel(context->read_source);

    if (context->write_source)
        dispatch_source_cancel(context->write_source);

    fprintf(stderr, "destroyed context %p\n", context);
    free(context);
}

void add_download(const char *url, int num)
{
    char filename[50];
    FILE *file;
    CURL *handle;

    sprintf(filename, "%d.download", num);

    file = fopen(filename, "w");
    if (file == NULL) {
        fprintf(stderr, "Error opening %s\n", filename);
        return;
    }

    handle = curl_easy_init();
    curl_easy_setopt(handle, CURLOPT_WRITEDATA, file);
    curl_easy_setopt(handle, CURLOPT_URL, url);
    curl_multi_add_handle(curl_handle, handle);
    fprintf(stderr, "Added download %s -> %s\n", url, filename);
}

void curl_perform(int socket, int actions)
{
    int running_handles;
    char *done_url;
    CURLMsg *message;
    int pending;

    curl_multi_socket_action(curl_handle, socket, actions, &running_handles);

    while ((message = curl_multi_info_read(curl_handle, &pending))) {
        switch (message->msg) {
            case CURLMSG_DONE:
                curl_easy_getinfo(message->easy_handle, CURLINFO_EFFECTIVE_URL,
                                  &done_url);
                printf("%s DONE\n", done_url);

                curl_multi_remove_handle(curl_handle, message->easy_handle);
                curl_easy_cleanup(message->easy_handle);

                break;
            default:
                fprintf(stderr, "CURLMSG default\n");
                abort();
        }
    }
}

dispatch_source_t make_source(dispatch_source_type_t type, int socket, int action)
{
    dispatch_source_t source = dispatch_source_create(type, socket, 0, queue);
    dispatch_source_set_event_handler(source, ^{
        fprintf(stderr, "source event socket %d action %d\n", socket, action);
        curl_perform(socket, action);
    });
    dispatch_source_set_cancel_handler(source, ^{
        fprintf(stderr, "source cancelled socket %d action %d\n", socket, action);
        dispatch_release(source);
    });

    dispatch_resume(source);
    return source;
}


void create_timeout()
{
    timeout = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_event_handler(timeout, ^{
        curl_perform(CURL_SOCKET_TIMEOUT, 0);
    });

    dispatch_resume(timeout);
}

void start_timeout(CURLM *multi, long timeout_ms, void *userp)
{
    if (timeout_ms <= 0)
        timeout_ms = 1; /* 0 means directly call socket_action, but we'll do it in
                         a bit */

    int64_t timeout_ns = timeout_ms * NSEC_PER_MSEC;
    dispatch_source_set_timer(timeout, DISPATCH_TIME_NOW, timeout_ns, timeout_ns / 100);
}

int handle_socket(CURL *easy, curl_socket_t s, int action, void *userp,
                  void *socketp)
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
            curl_context->read_source = make_source(DISPATCH_SOURCE_TYPE_READ, s, CURL_CSELECT_IN);
            break;

        case CURL_POLL_OUT:
            curl_context->write_source = make_source(DISPATCH_SOURCE_TYPE_WRITE, s, CURL_CSELECT_OUT);
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

int main(int argc, char **argv)
{
    queue = dispatch_queue_create("curl queue", 0);

    if (argc <= 1)
        return 0;

    if (curl_global_init(CURL_GLOBAL_ALL)) {
        fprintf(stderr, "Could not init cURL\n");
        return 1;
    }

    create_timeout();

    curl_handle = curl_multi_init();
    curl_multi_setopt(curl_handle, CURLMOPT_SOCKETFUNCTION, handle_socket);
    curl_multi_setopt(curl_handle, CURLMOPT_TIMERFUNCTION, start_timeout);
    
    while (argc-- > 1) {
        add_download(argv[argc], argc);
    }



    dispatch_main();

    curl_multi_cleanup(curl_handle);
    return 0;
}