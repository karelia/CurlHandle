build() {

	echo "Building $2"

	obj="$HOME/Library/Caches/CurlHandle/$2/obj"
	sym="$HOME/Library/Caches/CurlHandle/$2/sym"
    rm -rf "$obj"
    rm -rf "$sym"
	xcodebuild -project $1.xcodeproj -target $2 -configuration Debug OBJROOT="$obj" SYMROOT="$sym" > /tmp/build.log
	res=$?

	if [ $res -ne 0 ];
	then
		cat /tmp/build.log
		echo "$1 build failed"
		exit $res
	fi

}

# remove old versions
rm -rf CURLHandleSource/built

# build SFTP libraries too?

if [ "$1" == "--all" ];
then
	cd SFTP
	build OpenSSL openssl
	build libssh2 libssh2
	cd ..
	
elif [ "$1" == "--curl-only" ];
then
    echo "Skipping SFTP libraries"
	
else
	echo "Usage: build-libs.sh { --all | --curl-only }"
	exit 0
fi

# build libcurl and libcares
cd CURLHandleSource
build CURLHandle libcurl

echo "Done"
open "built"