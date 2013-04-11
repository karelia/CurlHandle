# glibtoolize (and maybe other tools) are not supplied with OS X.
# Add default macports & homebrew paths in attempt to find them.
export PATH=${PATH}:/opt/local/bin:/usr/local/bin

# Create final dylibs.
cd "${OBJROOT}"
lipo -create -arch i386 cares-i386/.libs/libcares-i386.dylib  -arch x86_64 cares-x86_64/.libs/libcares-x86_64.dylib  -output libcares.dylib

# Create dSYMs
dsymutil libcares.dylib

# Strip dylibs
strip -x libcares.dylib

# Final output to project dir, not build dir.
OUTDIR="${SRCROOT}/built"
mkdir -p "${OUTDIR}/include/cares-i386"
mkdir -p "${OUTDIR}/include/cares-x86_64"
cp -f  libcares.dylib      "${OUTDIR}"
cp -Rf libcares.dylib.dSYM "${OUTDIR}"
cp -f cares-i386/ares_build.h "${OUTDIR}/include/cares-i386"
cp -f cares-x86_64/ares_build.h "${OUTDIR}/include/cares-x86_64"

# Display results.
lipo -detailed_info "${OUTDIR}/libcares.dylib"
exit 0
