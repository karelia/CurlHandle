libcares is a git submodule - be sure to update it via git

How to build libcares:
1. Update the source to a new version if desired.
2. Select the target "libcares" in the Scheme popup (32- or 64-bit doesn't matter).
3. Build. Just a regular Cmd-B build. No archiving or anything.
    Because the builds are controlled by scripts, not Xcode, they always build for "release", but also with debug info.
    Note also that the build outputs are:
    	libcares.dylib  &  libcares.dylib.dSYM
4. Make a new git commit in CurlHandle if needed. Git is tracking the built dylib & dSYM as well as the source.

After updating/rebuilding libcares, you should update/rebuild any libraries, frameworks, or apps that depend on it, such as libcurl & CURLHandle.framework.

NOTE: Building libcurl will automatically build libcares, too.