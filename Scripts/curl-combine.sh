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
mkdir -p "${OUTDIR}/include/curl-i386/curl"
mkdir -p "${OUTDIR}/include/curl-x86_64/curl"
cp -f  libcurl.dylib      "${OUTDIR}"
cp -Rf libcurl.dylib.dSYM "${OUTDIR}"
cp -Rf curl-i386/include/curl/*.h "${OUTDIR}/include/curl-i386/curl/"
cp -Rf curl-x86_64/include/curl/*.h "${OUTDIR}/include/curl-x86_64/curl/"

# Display results.
lipo -detailed_info "${OUTDIR}/libcurl.dylib"
exit 0
