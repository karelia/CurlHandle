build() {

	echo "Building $2"

	obj="$HOME/Library/Caches/CurlHandle/obj"
	sym="$HOME/Library/Caches/CurlHandle/sym"
	xcodebuild -project $1.xcodeproj -target $2 -configuration Debug OBJROOT="$obj" SYMROOT="$sym" #> /tmp/build.log 
	res=$?

#	if [ $res -ne 0 ];
#	then
#		cat /tmp/build.log
#		echo "$1 build failed"
#		exit $res
#	fi

}


# build the libcurl test target
# this should build the 64 bit libcares and libcurl (without doing a clean first, so it should be fast
# if they're already built), then it copies them and the SSH libraries into a place where the tests
# can find them, before running 'make test' to launch the tests

cd CURLHandleSource
build CURLHandle libcurl-tests-x86_64

echo "Done"
open "built"