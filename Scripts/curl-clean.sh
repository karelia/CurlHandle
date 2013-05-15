# glibtoolize (and maybe other tools) are not supplied with OS X.
# Add default macports & homebrew paths in attempt to find them.
export PATH=${PATH}:/opt/local/bin:/usr/local/bin

# Remove final output files from previous run.
OUTDIR="${SRCROOT}/built"
rm -f  "${OUTDIR}/libcurl.dylib"
rm -Rf "${OUTDIR}/libcurl.dylib.dSYM"

# Remove intermediate output files from previous run.
rm -f  "${OBJROOT}/libcurl.dylib"
rm -Rf "${OBJROOT}/libcurl.dylib.dSYM"

# Remove build dirs from previous run.
rm -Rf "${OBJROOT}/curl-i386"
rm -Rf "${OBJROOT}/curl-x86_64"
rm -Rf "${OBJROOT}/libssh2"
rm -Rf "${OBJROOT}/c-ares-i386"
rm -Rf "${OBJROOT}/c-ares-x86_64"
