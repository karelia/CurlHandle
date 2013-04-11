# glibtoolize (and maybe other tools) are not supplied with OS X.
# Add default macports & homebrew paths in attempt to find them.
export PATH=${PATH}:/opt/local/bin:/usr/local/bin

# Clean original source dir, just in case.
cd "${SRCROOT}/../curl"
echo "Please ignore any messages about \"No rule to make target distclean.\" That just means the build dir is already clean."
make distclean

# Remove final output files from previous run.
cd "${SRCROOT}"
rm -f  "libcurl.dylib"
rm -Rf "libcurl.dylib.dSYM"

# Remove intermediate output files from previous run.
rm -f  "${OBJROOT}/libcurl.dylib"
rm -Rf "${OBJROOT}/libcurl.dylib.dSYM"

# Remove build dirs from previous run.
rm -Rf "${OBJROOT}/curl-i386"
rm -Rf "${OBJROOT}/curl-x86_64"
rm -Rf "${OBJROOT}/libssh2"
rm -Rf "${OBJROOT}/c-ares-i386"
rm -Rf "${OBJROOT}/c-ares-x86_64"
