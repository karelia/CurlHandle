Building libraries

## Install Tools

Homebrew
	brew update
	brew install automake (if it's not already installed)
	brew versions automake (we want to use ver. 1.12.6)
	cd /usr/local/Library/Formula/
	git checkout 3a7567c /usr/local/Library/Formula/automake.rb
	brew unlink automake
	brew install automake (should show ver 1.12.6 installing)
	(also note the cool beer mug emoji when brew is done :-P )



## Fetch Code

git
	git checkout "sam/async"
	git submodule update --recursive
		(new commits in CurlHandle and SFTP leave the library build dirs in place to allow debugging)

## Build
		 
Xcode
	OpenSSL - libcrypto, libssl
		open SFTP/OpenSSL.xcodeproj
		build target openssl   (with Product / Build For / Archiving)
	libssh2
		open SFTP/libssh2.xcodeproj
		build target libssh2   (for archiving)
	libcurl, libcares
		open CURLHandleSource/CURLHandle.xcodeproj
		build target libcurl   (for archiving)

Build Framework and debug. libcurl, etc. should show full source in the debugger.