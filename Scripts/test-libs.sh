build() {

	echo "Building $2"

	obj="$HOME/Library/Caches/CurlHandle/obj"
	sym="$HOME/Library/Caches/CurlHandle/sym"
	xcodebuild -project $1.xcodeproj -target $2 -configuration Debug OBJROOT="$obj" SYMROOT="$sym" > /tmp/build.log 
	res=$?

	if [ $res -ne 0 ];
	then
		cat /tmp/build.log
		echo "$1 build failed"
		exit $res
	fi

}



cd CURLHandleSource

# if necessary, build everything first
# this will leave the various object files knocking around that the tests will need
# in theory we only require this step if we've not already built on this machine
# (of if something has changed since then, of course)
# since building is quite slow, it's helpful to be able to skip it

if [ "$1" == "--build-and-test" ];
then
	build CURLHandle libcurl

elif [ "$1" == "--test-only" ];
then
    echo "Skipping rebuilding libraries"
	
else
	echo "Usage: test-libs.sh { --build-and-test | --test-only }"
	exit 0
fi

# buidling this target attempts to copy the 64 bit versions of the build libraries into
# the right places, then invokes 'make test' to build and run the tests

build CURLHandle libcurl-tests-x86_64

echo "Tests done"

cat /tmp/build.log
