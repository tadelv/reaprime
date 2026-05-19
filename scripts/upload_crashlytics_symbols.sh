#!/bin/bash
#
# Locate the firebase-ios-sdk Crashlytics `run` script across CocoaPods and
# Swift Package Manager integrations, then invoke `flutterfire upload-crashlytics-symbols`.
#
# The flutterfire_cli-generated default uses a BUILD_ROOT/sed scheme that
# breaks under Flutter + SPM in modern Xcode (BUILD_DIR is remapped to the
# Flutter build dir, BUILD_ROOT can land outside the DerivedData app folder).
# This wrapper probes multiple likely locations and fails loud if none hit.
#
# Tracking: firebase/firebase-ios-sdk#12788, firebase/flutterfire#17081.
set -e

PATH="${PATH}:$FLUTTER_ROOT/bin:${PUB_CACHE}/bin:$HOME/.pub-cache/bin"

PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT=""

# 1) CocoaPods integration
if [ -n "$PODS_ROOT" ] && [ -f "$PODS_ROOT/FirebaseCrashlytics/run" ]; then
  PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT="$PODS_ROOT/FirebaseCrashlytics/run"
fi

# 2) SPM: probe known SourcePackages layouts
if [ -z "$PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT" ]; then
  DERIVED_FROM_BUILD_ROOT="$(echo "$BUILD_ROOT" | sed -E 's|(.*DerivedData/[^/]+).*|\1|')"
  for candidate in \
    "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run" \
    "${DERIVED_FROM_BUILD_ROOT}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"; do
    if [ -f "$candidate" ]; then
      PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT="$candidate"
      break
    fi
  done
fi

# 3) Last-ditch: search DerivedData
if [ -z "$PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT" ]; then
  PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run" \
    -print -quit 2>/dev/null || true)
fi

if [ -z "$PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT" ] || [ ! -f "$PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT" ]; then
  echo "error: firebase-ios-sdk Crashlytics 'run' script not found in Pods or SPM SourcePackages." >&2
  echo "  PODS_ROOT=$PODS_ROOT" >&2
  echo "  BUILD_DIR=$BUILD_DIR" >&2
  echo "  BUILD_ROOT=$BUILD_ROOT" >&2
  exit 1
fi

PLATFORM_FLAG="${1:-ios}"

flutterfire upload-crashlytics-symbols \
  --upload-symbols-script-path="$PATH_TO_CRASHLYTICS_UPLOAD_SCRIPT" \
  --platform="$PLATFORM_FLAG" \
  --apple-project-path="${SRCROOT}" \
  --env-platform-name="${PLATFORM_NAME}" \
  --env-configuration="${CONFIGURATION}" \
  --env-project-dir="${PROJECT_DIR}" \
  --env-built-products-dir="${BUILT_PRODUCTS_DIR}" \
  --env-dwarf-dsym-folder-path="${DWARF_DSYM_FOLDER_PATH}" \
  --env-dwarf-dsym-file-name="${DWARF_DSYM_FILE_NAME}" \
  --env-infoplist-path="${INFOPLIST_PATH}" \
  --default-config=default
