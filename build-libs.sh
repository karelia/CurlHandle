cd SFTP

echo 'Building OpenSSL'

xcodebuild -project OpenSSL.xcodeproj -target openssl -configuration Debug
res=$?

if [ $res -ne 0 ];
then
	echo 'OpenSSL build failed'
	exit $res
fi
	
echo 'Building libssh2'

xcodebuild -project libssh2.xcodeproj -target libssh2 -configuration Debug

if [ $res -ne 0 ];
then
	echo 'libssh2 build failed'
	exit $res
fi

cd ../CURLHandleSource

echo 'Building libcurl'

xcodebuild -project CURLHandle.xcodeproj -target libcurl -configuration Debug

if [ $res -ne 0 ];
then
	echo 'libcurl build failed'
	exit $res
fi
