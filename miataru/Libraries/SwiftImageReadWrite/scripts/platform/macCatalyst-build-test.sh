#!/bin/bash

# Basic sanity check before commit that all the expected targets build and test

# Note: don't include 'arch=' within the destination on macOS builds so it _should_ work for M1 arm based macs as well as Intel

# Stop on error
set -e

ORIGDIR=$PWD
BASEDIR=$(dirname $(realpath "$0"))

pushd .

# Move back up to the SwiftImageReadWrite root directory, or else Xcode complains...
cd "${BASEDIR}"/../..

echo ">>>> macCatalyst build and test..."

xcodebuild clean build archive -scheme "SwiftImageReadWrite" -destination 'generic/platform=macOS,variant=Mac Catalyst' -quiet
xcodebuild test -scheme "SwiftImageReadWrite" -destination 'platform=macOS,variant=Mac Catalyst' -quiet

echo "<<<< macCatalyst build and test COMPLETE..."

popd
