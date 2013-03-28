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
 curl_multi_wait, which uses select(), we use gcd.

 Written by Sam Deane, based on the multi-uv.c example.

 Requires gcd and (of course) libcurl.

 See http://en.wikipedia.org/wiki/Grand_Central_Dispatch for more information on gcd.
 */

#include <stdio.h>
#include <stdlib.h>
#include <curl/curl.h>
#include <string.h>
#include <assert.h>

#include <dispatch/dispatch.h>

#define log_normal(...) fprintf(stderr, __VA_ARGS__)
#define log_error(...) fprintf(stderr, "ERROR: " __VA_ARGS__)
#define log_detail(...) fprintf(stderr, __VA_ARGS__)
//#define log_detail(...)

dispatch_queue_t queue;
int remaining = 0;
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

    log_detail("created context %p\n", context);
    
    return context;
}

void destroy_curl_context(curl_context_t *context)
{
    if (context->read_source)
        dispatch_source_cancel(context->read_source);

    if (context->write_source)
        dispatch_source_cancel(context->write_source);

    log_detail("destroyed context %p\n", context);
    
    free(context);
}

size_t write_func(void *ptr, size_t size, size_t nmemb, void *userp)
{
    char* string = strndup(ptr, size * nmemb);
    log_detail("received bytes\n%s\nend bytes\n", string);
    free(string);
    return size * nmemb;
}

size_t read_func(void *ptr, size_t size, size_t nmemb, void *userp)
{
    log_detail("read");
    return 0;
}

size_t header_func(void *ptr, size_t size, size_t nmemb, void *userp)
{
    char* string = strndup(ptr, size * nmemb);
    log_detail("header bytes\n%s\nend bytes\n", string);
    free(string);
    return size * nmemb;
}


int debug_func(CURL *curl, curl_infotype infoType, char *info, size_t infoLength, void *userp)
{
    char* string = strndup(info, infoLength);
    log_detail("debug %d: %s", infoType, string);
    free(string);
    return 0;
}

int socket_func(void *easy, curl_socket_t curlfd, curlsocktype purpose)
{
    if (purpose == CURLSOCKTYPE_IPCXN)
    {
        char* url = NULL;
        curl_easy_getinfo(easy, CURLINFO_EFFECTIVE_URL, &url);

        if (strncmp(url, "ftp:", 4) == 0)
        {
            int keepAlive = 1;
            socklen_t keepAliveLen = sizeof(keepAlive);
            int result = setsockopt(curlfd, SOL_SOCKET, SO_KEEPALIVE, &keepAlive, keepAliveLen);
            if (result)
            {
                log_error("Unable to set FTP control connection keepalive with error:%i", result);
            }
        }
    }

    return 0;
}

int known_hosts_func(CURL *easy,     /* easy handle */
                           const struct curl_khkey *knownkey, /* known */
                           const struct curl_khkey *foundkey, /* found */
                           enum curl_khmatch match, /* libcurl's view on the keys */
                           void *userp) /* custom pointer passed from app */
{
    return 0;
}

void add_download(const char *url, int num)
{
    char filename[50];
    FILE *file;
    CURL *handle;

    sprintf(filename, "%d.download", num);

    file = fopen(filename, "w");
    if (file == NULL) {
        log_error("Error opening %s\n", filename);
        return;
    }

    handle = curl_easy_init();

    long timeout = 60;
    curl_easy_setopt(handle, CURLOPT_NOSIGNAL, timeout != 0);
    curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT, timeout);

    char * error_buffer = malloc(CURL_ERROR_SIZE + 2);
    error_buffer[0] = 255;
    error_buffer[CURL_ERROR_SIZE + 1] = 255;
    curl_easy_setopt(handle, CURLOPT_ERRORBUFFER, error_buffer + 1);
    curl_easy_setopt(handle, CURLOPT_PRIVATE, error_buffer);
    curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, 1);
    curl_easy_setopt(handle, CURLOPT_FAILONERROR, 1);
    curl_easy_setopt(handle, CURLOPT_FTP_CREATE_MISSING_DIRS, 2);

    curl_easy_setopt(handle, CURLOPT_READFUNCTION, read_func);
    curl_easy_setopt(handle, CURLOPT_HEADERFUNCTION, header_func);
    curl_easy_setopt(handle, CURLOPT_DEBUGFUNCTION, debug_func);
    curl_easy_setopt(handle, CURLOPT_VERBOSE, 1);
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, write_func);
    curl_easy_setopt(handle, CURLOPT_URL, url);
    struct curl_slist* list = curl_slist_append(NULL, "*MKD test");
    list = curl_slist_append(list, "*MKD test2");
    list = curl_slist_append(list, "SITE CHMOD 0744 test2");
    list = curl_slist_append(list, "DELE test");
    list = curl_slist_append(list, "DELE test2");
    list = curl_slist_append(list, "DELE file1.txt");
    list = curl_slist_append(list, "DELE file2.txt");
    curl_easy_setopt(handle, CURLOPT_POSTQUOTE, list);

    curl_multi_add_handle(curl_handle, handle);
    log_normal("Added download %s -> %s\n", url, filename);
    ++remaining;

    //curl_slist_free_all(list);

    // send all data to the C function
    curl_easy_setopt(handle, CURLOPT_SOCKOPTFUNCTION, socket_func);
    curl_easy_setopt(handle, CURLOPT_SOCKOPTDATA, handle);
    curl_easy_setopt(handle, CURLOPT_SSH_KNOWNHOSTS, NULL);
    curl_easy_setopt(handle, CURLOPT_SSH_KEYFUNCTION, known_hosts_func);


    //        curl_easy_setopt(handle, CURLOPT_USERNAME, [username UTF8String]);
    //      curl_easy_setopt(handle, CURLOPT_PASSWORD, [password UTF8String]);
        curl_easy_setopt(handle, CURLOPT_SSH_PUBLIC_KEYFILE, NULL);
        curl_easy_setopt(handle, CURLOPT_SSH_PUBLIC_KEYFILE, NULL);
        curl_easy_setopt(handle, CURLOPT_SSH_AUTH_TYPES, CURLSSH_AUTH_PASSWORD|CURLSSH_AUTH_KEYBOARD);


    //    curl_easy_setopt(handle, CURLOPT_HTTPGET, 1);
    curl_easy_setopt(handle, CURLOPT_NOBODY, 1);
    //        curl_easy_setopt(handle, CURLOPT_POST, 1);

    //        curl_easy_setopt(handle, CURLOPT_INFILESIZE, [uploadData length]);
    curl_easy_setopt(handle, CURLOPT_UPLOAD, 0);

    curl_easy_setopt(handle, CURLOPT_USE_SSL, 0);
    curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, 0);


    curl_easy_setopt(handle, CURLOPT_NEW_FILE_PERMS, 0744);
    curl_easy_setopt(handle, CURLOPT_NEW_DIRECTORY_PERMS, 0744);


    curl_easy_setopt(handle, CURLOPT_FTP_USE_EPSV, 0);

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
            {
                CURL* easy = message->easy_handle;
                curl_easy_getinfo(easy, CURLINFO_EFFECTIVE_URL, &done_url);
                unsigned char* error = NULL;
                curl_easy_getinfo(easy, CURLINFO_PRIVATE, &error);
                assert(error[0] == 255);
                assert(error[CURL_ERROR_SIZE + 1] == 255);
                CURLcode code = message->data.result;
                printf("%s DONE\ncode:%d - %s\nerror:%s\n", done_url, code, curl_easy_strerror(code), error + 1);
                free(error);

                curl_multi_remove_handle(curl_handle, message->easy_handle);
                curl_easy_cleanup(message->easy_handle);
                --remaining;

                break;
            }
            default:
                log_error("CURLMSG default\n");
                abort();
        }
    }
}

const char* action_name(int action)
{
    return action == CURL_CSELECT_IN ? "read" : "write";
}

dispatch_source_t make_source(dispatch_source_type_t type, int socket, int action)
{
    log_detail("make source socket %d action %s\n", socket, action_name(action));
    dispatch_source_t source = dispatch_source_create(type, socket, 0, queue);
    dispatch_source_set_event_handler(source, ^{
        log_detail("source event socket %d action %s\n", socket, action_name(action));
        curl_perform(socket, action);
    });
    dispatch_source_set_cancel_handler(source, ^{
        log_detail("source cancelled socket %d action %s\n", socket, action_name(action));
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
        if (remaining == 0)
        {
            curl_multi_cleanup(curl_handle);
            exit(0);
        }
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
        log_error("Could not init cURL\n");
        return 1;
    }

    create_timeout();

    curl_handle = curl_multi_init();
    curl_multi_setopt(curl_handle, CURLMOPT_SOCKETFUNCTION, handle_socket);
    curl_multi_setopt(curl_handle, CURLMOPT_TIMERFUNCTION, start_timeout);
    
    while (argc-- > 1) {
        for (int n = 0; n < 10; ++n)
            add_download(argv[argc], argc);
    }

    dispatch_main();

    return 0;
}