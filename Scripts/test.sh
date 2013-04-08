#!/usr/bin/env bash

# This script builds and runs the unit tests and produces output in a format that is compatible with Jenkins.

base=`dirname $0`
pushd "$base/.." > /dev/null
build="$PWD/test-build"
ocunit2junit="$PWD/CURLHandleSource/Tests/MockServer/UnitTests/OCUnit2JUnit/bin/ocunit2junit"
popd > /dev/null

echo "Building and running tests into $build"

sym="$build/sym"
obj="$build/obj"

testout="$build/output.log"
testerr="$build/error.log"

rm -rf "$build"
mkdir -p "$build"

xcodebuild -workspace "CURLHandle.xcworkspace" -scheme "CURLHandle" -sdk "macosx" -config "Debug" test OBJROOT="$obj" SYMROOT="$sym" > "$testout" 2> "$testerr"
cd "$build"
"$ocunit2junit" < "$testout"
