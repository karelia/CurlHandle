build() {

	echo "Building $1"

	xcodebuild -project $1.xcodeproj -target $2 -configuration Debug > /tmp/build.log
	res=$?

	if [ $res -ne 0 ];
	then
		cat /tmp/build.log
		echo '$1 build failed'
		exit $res
	fi

}

cd SFTP
build OpenSSL openssl
build libssh2 libssh2

cd ../CURLHandleSource
build CURLHandle libcurl
