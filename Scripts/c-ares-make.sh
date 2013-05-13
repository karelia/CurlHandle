# First parameter should be "i386" or "x86_64"
MODE=$1

# glibtoolize (and maybe other tools) are not supplied with OS X.
# Add default macports & homebrew paths in attempt to find them.
export PATH=${PATH}:/opt/local/bin:/usr/local/bin

cd "${OBJROOT}/cares-$MODE"
make
