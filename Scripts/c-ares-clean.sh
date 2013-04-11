# glibtoolize (and maybe other tools) are not supplied with OS X.
# Add default macports & homebrew paths in attempt to find them.
export PATH=${PATH}:/opt/local/bin:/usr/local/bin

# Clean original source dir, just in case.
cd "${SRCROOT}/../c-ares"
echo "Please ignore any messages about \"No rule to make target distclean.\" That just means the build dir is already clean."
make distclean

# Remove final output files from previous run.
cd "${SRCROOT}"
rm -f  "libcares.dylib"
rm -Rf "libcares.dylib.dSYM"

# Remove intermediate output files from previous run.
rm -f  "${OBJROOT}/libcares.dylib"
rm -Rf "${OBJROOT}/libcares.dylib.dSYM"

# Remove build dirs from previous run.
rm -Rf "${OBJROOT}/libcares-i386"
rm -Rf "${OBJROOT}/libcares-x86_64"
