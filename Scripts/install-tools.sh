#!/usr/bin/env bash

brew update
brew install automake
brew versions automake
cd /usr/local/Library/Formula/
git checkout 3a7567c /usr/local/Library/Formula/automake.rb
brew unlink automake
brew install automake

brew install pkg-config
brew install libtool

