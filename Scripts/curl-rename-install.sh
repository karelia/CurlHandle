# First parameter should be "i386" or "x86_64"
MODE=$1

# glibtoolize (and maybe other tools) are not supplied with OS X.
# Add default macports & homebrew paths in attempt to find them.
export PATH=${PATH}:/opt/local/bin:/usr/local/bin

# Correct the load commands of the dylibs.
cd "${OBJROOT}/curl-$MODE/lib/.libs"
# Get the full filenames of the dylibs from the symlinks.
# E.g.: dylib:"libcrypto.1.0.0.dylib" symlink:"libcrypto.dylib"
LONG_DYLIB=`readlink -n libcurl.dylib`
# Fix ID.
install_name_tool -id @rpath/libcurl.dylib ${LONG_DYLIB}
# Correct load path of libs that we load (libssh2).
# [already correct] install_name_tool -change /usr/local/lib/${LONG_DYLIB} @rpath/libcurl.dylib ${LONG_DYLIB}
# Add rpath search paths.
install_name_tool -add_rpath @loader_path/../Frameworks ${LONG_DYLIB}

# Copy dylibs to have arch in name.
cp -f ${LONG_DYLIB} libcurl-$MODE.dylib
