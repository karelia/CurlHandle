#include <stdio.h>
#include <string.h>

#include <curl/curl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#ifdef WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

/*
 * This example shows an FTP upload to an absolute path at the root of the server.
 * The file is incorrectly uploaded to the home directory instead.
 */

/* NOTE: if you want this example to work on Windows with libcurl as a
 DLL, you MUST also provide a read callback with CURLOPT_READFUNCTION.
 Failing to do so will give you a crash since a DLL may not use the
 variable's memory when passed in to it from an app like this. */
static size_t read_callback(void *ptr, size_t size, size_t nmemb, void *stream)
{
    curl_off_t nread;
    /* in real-world cases, this would probably get this data differently
     as this fread() stuff is exactly what the library already would do
     by default internally */
    size_t retcode = fread(ptr, size, nmemb, stream);

    nread = (curl_off_t)retcode;

    fprintf(stderr, "*** We read %" CURL_FORMAT_CURL_OFF_T
            " bytes from file\n", nread);
    return retcode;
}

extern int upload_root(const char* url)
{
    CURL *curl;
    CURLcode res;
    FILE *hd_src;
    struct stat file_info;
    curl_off_t fsize;

    /* make test content */
    char* temp_path = tmpnam(NULL);
    FILE* f = fopen(temp_path, "w");
    fprintf(f, "some test content");
    fclose(f);

    /* get the file size of the local file */
    if(stat(temp_path, &file_info)) {
        printf("Couldnt open '%s': %s\n", temp_path, strerror(errno));
        return 1;
    }
    fsize = (curl_off_t)file_info.st_size;

    printf("Local file size: %" CURL_FORMAT_CURL_OFF_T " bytes.\n", fsize);

    /* get a FILE * of the same file */
    hd_src = fopen(temp_path, "rb");

    /* In windows, this will init the winsock stuff */
    curl_global_init(CURL_GLOBAL_ALL);

    /* get a curl handle */
    curl = curl_easy_init();
    if(curl) {
        /* we want to use our own read function */
        curl_easy_setopt(curl, CURLOPT_READFUNCTION, read_callback);

        /* enable uploading */
        curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);

        /* specify target */
        curl_easy_setopt(curl,CURLOPT_URL, url);

        /* now specify which file to upload */
        curl_easy_setopt(curl, CURLOPT_READDATA, hd_src);

        /* Set the size of the file to upload (optional).  If you give a *_LARGE
         option you MUST make sure that the type of the passed-in argument is a
         curl_off_t. If you use CURLOPT_INFILESIZE (without _LARGE) you must
         make sure that to pass in a type 'long' argument. */
        curl_easy_setopt(curl, CURLOPT_INFILESIZE_LARGE,
                         (curl_off_t)fsize);

        /* Now run off and do what you've been told! */
        res = curl_easy_perform(curl);
        /* Check for errors */
        if(res != CURLE_OK)
            fprintf(stderr, "curl_easy_perform() failed: %s\n",
                    curl_easy_strerror(res));

        /* always cleanup */
        curl_easy_cleanup(curl);
    }
    fclose(hd_src); /* close the local file */ 

    curl_global_cleanup();

    unlink(temp_path);
    
    return 0;
}

#ifndef SUPPRESS_MAIN
int main(int argc, char **argv)
{
    /* this should upload to the server root, but doesn't */
    upload_root("ftp://ftptest:ftptest@10.0.1.32//libcurl_upload_test1.txt");

    /* this does */
    upload_root("ftp://ftptest:ftptest@10.0.1.32/%2Flibcurl_upload_test2.txt");
}
#endif