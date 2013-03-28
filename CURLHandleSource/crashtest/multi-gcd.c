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
//#define log_detail(...) fprintf(stderr, __VA_ARGS__)
#define log_detail(...)

dispatch_queue_t queue;
int remaining = 0;
CURLM *curl_handle;
dispatch_source_t timeout;

typedef struct curl_handle_context_s {
    CURL *handle;
    char sentinal1;
    char error_buffer[CURL_ERROR_SIZE];
    char sentinal2;
    struct curl_slist* post_commands;
} curl_handle_context_s;

typedef struct curl_socket_context_s {
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

#pragma mark - socket action support

void curl_perform_action(int socket, int actions)
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
                assert(context->sentinal1 == 0xC);
                assert(context->sentinal2 == 0xD);
                CURLcode code = message->data.result;
                printf("%s DONE\ncode:%d - %s\nerror:%s\n", done_url, code, curl_easy_strerror(code), context->error_buffer);
                curl_slist_free_all(context->post_commands);
                free(context);

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

#pragma mark - GCD utilities


dispatch_source_t create_source(dispatch_source_type_t type, int socket, int action)
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

void create_timeout()
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


#pragma mark - EASY callbacks

size_t write_func(void *ptr, size_t size, size_t nmemb, void *userp)
{
    char* string = strndup(ptr, size * nmemb);
    log_normal("%s", string);
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

int socket_func(curl_handle_context_s *context, curl_socket_t curlfd, curlsocktype purpose)
{
    if (purpose == CURLSOCKTYPE_IPCXN)
    {
        char* url = NULL;
        curl_easy_getinfo(context->handle, CURLINFO_EFFECTIVE_URL, &url);

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


#pragma mark - MULTI callbacks

void timeout_func(CURLM *multi, long timeout_ms, void *userp)
{
    if (timeout_ms <= 0)
        timeout_ms = 1; /* 0 means directly call socket_action, but we'll do it in
                         a bit */

    int64_t timeout_ns = timeout_ms * NSEC_PER_MSEC;
    dispatch_source_set_timer(timeout, DISPATCH_TIME_NOW, timeout_ns, timeout_ns / 100);
}

int multi_socket_func(CURL *easy, curl_socket_t s, int action, void *userp, void *socketp)
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

void add_download(const char *url, int num)
{
    CURL *handle;

    handle = curl_easy_init();

    curl_handle_context_s* context = malloc(sizeof *context);
    context->handle = handle;
    context->sentinal1 = 0xC;
    context->sentinal2 = 0xD;
    context->post_commands = NULL;
    curl_easy_setopt(handle, CURLOPT_PRIVATE, context);

    long timeout = 60;
    curl_easy_setopt(handle, CURLOPT_NOSIGNAL, timeout != 0);
    curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT, timeout);

    curl_easy_setopt(handle, CURLOPT_ERRORBUFFER, context->error_buffer);
    curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, 1);
    curl_easy_setopt(handle, CURLOPT_FAILONERROR, 1);
    curl_easy_setopt(handle, CURLOPT_FTP_CREATE_MISSING_DIRS, 2);

    curl_easy_setopt(handle, CURLOPT_READFUNCTION, read_func);
    curl_easy_setopt(handle, CURLOPT_HEADERFUNCTION, header_func);
    curl_easy_setopt(handle, CURLOPT_DEBUGFUNCTION, debug_func);
    curl_easy_setopt(handle, CURLOPT_VERBOSE, 1);
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, write_func);

    bool is_sftp = strncmp(url, "sftp:", 5) == 0;

    char randomname[CURL_ERROR_SIZE];
    char makecmd[CURL_ERROR_SIZE];
    char chmodcmd[CURL_ERROR_SIZE];
    char delcmd[CURL_ERROR_SIZE];
    char delfile1cmd[CURL_ERROR_SIZE];
    char delfile2cmd[CURL_ERROR_SIZE];

    sprintf(randomname, "test-%d", rand());

    char *user = NULL;
    char *pass = NULL;
    char *path = strstr(url, "//") + 2;
    char *at = strstr(path, "@");
    char *newurl = NULL;
    if (at)
    {
        pass = strstr(path, ":") + 1;
        size_t passsize =  (at - pass);
        size_t usersize = (pass - path) - 1;
        pass = strndup(path, passsize);
        user = strndup(path, usersize);
        size_t schemesize = (path - url);
        path = strstr(at, "/");
        if (!path) path = "";
        newurl = strdup(url);
        strcpy(newurl + schemesize, at + 1);
        url = newurl;
    }

    curl_easy_setopt(handle, CURLOPT_URL, url);

    if (is_sftp)
    {

        sprintf(makecmd, "*mkdir %s%s", path, randomname);
        sprintf(chmodcmd, "chmod 0744 %s%s", path, randomname);
        sprintf(delfile1cmd, "*rm %sfile1.txt", path);
        sprintf(delfile2cmd, "*rm %sile2.txt", path);
        sprintf(delcmd, "*rmdir %s%s", path, randomname);
    }
    else
    {
        sprintf(makecmd, "*MKD %s", randomname);
        sprintf(chmodcmd, "SITE CHMOD 0744 %s", randomname);
        sprintf(delfile1cmd, "*DELE file1.txt");
        sprintf(delfile2cmd, "*DELE file2.txt");
        sprintf(delcmd, "DELE %s", randomname);
    }

    context->post_commands = curl_slist_append(context->post_commands, makecmd);
    context->post_commands = curl_slist_append(context->post_commands, chmodcmd);
    context->post_commands = curl_slist_append(context->post_commands, delfile1cmd);
    context->post_commands = curl_slist_append(context->post_commands, delfile2cmd);
    context->post_commands = curl_slist_append(context->post_commands, delcmd);

    curl_easy_setopt(handle, CURLOPT_POSTQUOTE, context->post_commands);

    // send all data to the C function
    curl_easy_setopt(handle, CURLOPT_SOCKOPTFUNCTION, socket_func);
    curl_easy_setopt(handle, CURLOPT_SOCKOPTDATA, handle);
    curl_easy_setopt(handle, CURLOPT_SSH_KNOWNHOSTS, NULL);
    curl_easy_setopt(handle, CURLOPT_SSH_KEYFUNCTION, known_hosts_func);


    curl_easy_setopt(handle, CURLOPT_USERNAME, user);
    curl_easy_setopt(handle, CURLOPT_PASSWORD, pass);
    curl_easy_setopt(handle, CURLOPT_SSH_PUBLIC_KEYFILE, NULL);
    curl_easy_setopt(handle, CURLOPT_SSH_PUBLIC_KEYFILE, NULL);
    curl_easy_setopt(handle, CURLOPT_SSH_AUTH_TYPES, CURLSSH_AUTH_PASSWORD|CURLSSH_AUTH_KEYBOARD);


        curl_easy_setopt(handle, CURLOPT_HTTPGET, 1);
    //    curl_easy_setopt(handle, CURLOPT_NOBODY, 1);
    //        curl_easy_setopt(handle, CURLOPT_POST, 1);

    //        curl_easy_setopt(handle, CURLOPT_INFILESIZE, [uploadData length]);
    curl_easy_setopt(handle, CURLOPT_UPLOAD, 0);

    curl_easy_setopt(handle, CURLOPT_USE_SSL, 0);
    curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, 0);


    curl_easy_setopt(handle, CURLOPT_NEW_FILE_PERMS, 0744);
    curl_easy_setopt(handle, CURLOPT_NEW_DIRECTORY_PERMS, 0744);


    curl_easy_setopt(handle, CURLOPT_FTP_USE_EPSV, 0);

    dispatch_async(queue, ^{
        curl_multi_add_handle(curl_handle, handle);
        log_normal("Added download %s\n", url);
        ++remaining;

        if (user) free(user);
        if (pass) free(pass);
        if (newurl) free(newurl);
    });
}


int main(int argc, char **argv)
{
    log_normal("%s\n\n", curl_version());
    
    queue = dispatch_queue_create("curl queue", 0);

    if (argc <= 1)
        return 0;

    if (curl_global_init(CURL_GLOBAL_ALL)) {
        log_error("Could not init cURL\n");
        return 1;
    }

    create_timeout();

    curl_handle = curl_multi_init();
    curl_multi_setopt(curl_handle, CURLMOPT_SOCKETFUNCTION, multi_socket_func);
    curl_multi_setopt(curl_handle, CURLMOPT_TIMERFUNCTION, timeout_func);
    
    while (argc-- > 1) {
        for (int n = 0; n < 100; ++n)
            add_download(argv[argc], argc);
    }

    dispatch_main();

    return 0;
}