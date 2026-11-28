#!/bin/sh
set -e

BASEDIR=$(dirname "$0")
BASEDIR=$(cd "$BASEDIR" ; pwd -P)

# Remove Xcode SDK from path. Otherwise this breaks tool compilation when building iOS project.
NEW_PATH=$(echo "$PATH" | tr ":" "\n" | grep -v "Contents/Developer/" | tr "\n" ":")
export PATH=${NEW_PATH%?}

# Platform name (macosx, iphoneos, iphonesimulator)
export CARGOKIT_DARWIN_PLATFORM_NAME=$PLATFORM_NAME

# Active architectures (arm64, x86_64), space separated.
export CARGOKIT_DARWIN_ARCHS=$ARCHS

# Current build configuration (Debug, Release)
export CARGOKIT_CONFIGURATION=$CONFIGURATION

# Path to directory containing Cargo.toml.
export CARGOKIT_MANIFEST_DIR="$SRCROOT/$1"

# Temporary directory for build artifacts.
export CARGOKIT_TARGET_TEMP_DIR=$TARGET_TEMP_DIR

# Output directory for final artifacts.
export CARGOKIT_OUTPUT_DIR=$BUILT_PRODUCTS_DIR

# Directory to store built tool artifacts.
export CARGOKIT_TOOL_TEMP_DIR=$TARGET_TEMP_DIR/build_tool

# Directory inside root project.
export CARGOKIT_ROOT_PROJECT_DIR=$SRCROOT

FLUTTER_EXPORT_BUILD_ENVIRONMENT=(
  "$SRCROOT/Flutter/ephemeral/flutter_export_environment.sh" # macOS
  "$SRCROOT/Flutter/flutter_export_environment.sh" # iOS
)

for path in "${FLUTTER_EXPORT_BUILD_ENVIRONMENT[@]}"
do
  if [ -f "$path" ]; then
    # shellcheck disable=SC1090
    . "$path"
  fi
done

sh "$BASEDIR/run_build_tool.sh" build-pod "$@"
