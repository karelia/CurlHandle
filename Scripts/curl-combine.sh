# glibtoolize (and maybe other tools) are not supplied with OS X.
# Add default macports & homebrew paths in attempt to find them.
export PATH=${PATH}:/opt/local/bin:/usr/local/bin

# Create final dylibs.
cd "${OBJROOT}"
lipo -create -arch i386 curl-i386/lib/.libs/libcurl-i386.dylib  -arch x86_64 curl-x86_64/lib/.libs/libcurl-x86_64.dylib  -output libcurl.dylib

# Create dSYMs
dsymutil libcurl.dylib

# Strip dylibs
strip -x libcurl.dylib

# Final output to project dir, not source/build dir.
OUTDIR="${SRCROOT}/built"
mkdir -p "${OUTDIR}"
mkdir -p "${OUTDIR}/include"
cp -f  libcurl.dylib      "${OUTDIR}"
cp -Rf libcurl.dylib.dSYM "${OUTDIR}"
cp -Rf curl-i386/include "${OUTDIR}/include/curl-i386"
cp -Rf curl-x86_64/include "${OUTDIR}/include/curl-x86_64"

# Remove build dirs.
#rm -Rf "${OBJROOT}/curl-i386"
#rm -Rf "${OBJROOT}/curl-x86_64"
#rm -Rf "${OBJROOT}/libssh2"
#rm -Rf "${OBJROOT}/c-ares-i386"
#rm -Rf "${OBJROOT}/c-ares-x86_64"

# Display results.
lipo -detailed_info "${OUTDIR}/libcurl.dylib"
exit 0
