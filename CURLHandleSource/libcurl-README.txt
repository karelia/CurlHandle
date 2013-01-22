libcurl is a git submodule - be sure to update it via git

How to build libcurl:
1. Update the source to a new version if desired.
2. Select the target "libcurl" in the Scheme popup (32- or 64-bit doesn't matter).
3. Build. Just a regular Cmd-B build. No archiving or anything.
    Because the builds are controlled by scripts, not Xcode, they always build for "release", but also with debug info.
    Note also that the build outputs are:
    	libcurl.dylib  &  libcurl.dylib.dSYM
4. Make a new git commit if needed. Git is tracking the built dylib & dSYM as well as the source.

After updating/rebuilding libcurl, you should update/rebuild any libraries, frameworks, or apps that depend on it, such as CURLHandle.framework.

Building CURLHandle.framework (the CURLHandle target) uses the current build of libcurl.dylib -- it does not rebuild it. That's a decision we made for performance during CURLHandle builds.

Dependencies:
libcurl depends on 
    libcares
    libssh2

libcares is built automatically by building the libcurl target,
libssh2 is buit separately in another project.

