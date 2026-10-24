#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo 'This script requires macOS with Xcode.' >&2
    exit 1
fi
if [[ -n "${BROWSER_XCODE_PATH:-}" ]]; then
    export DEVELOPER_DIR="${BROWSER_XCODE_PATH}/Contents/Developer"
fi

mkdir -p build dist
xcodebuild -version
xcodebuild -showsdks
python3 scripts/generate_project.py --check
swift test --scratch-path .build/macos 2>&1 | tee build/core-tests.log

simulator_sdk="$(xcodebuild -version -sdk iphonesimulator SDKVersion)"
simulator_id="$(xcrun simctl list devices available --json | python3 scripts/select_simulator.py --sdk-version "$simulator_sdk")"
echo "Selected Simulator ${simulator_id} for SDK ${simulator_sdk}"
build_number="${GITHUB_RUN_NUMBER:-1}"
bundle_id="${BROWSER_BUNDLE_ID:-local.personalbrowser.app}"
if [[ "$bundle_id" != "local.personalbrowser.app" ]]; then
    echo 'Changing the installed app identity is prohibited for this update pipeline.' >&2
    exit 1
fi
if [[ "${CHECK_DATA_COMPATIBILITY:-0}" == "1" ]]; then
    bash scripts/check_data_compatibility.sh 2>&1 | tee build/data-compatibility.log
fi
signing=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 'CODE_SIGN_IDENTITY=')

xcodebuild test \
    -project PersonalBrowser.xcodeproj \
    -scheme PersonalBrowser \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${simulator_id}" \
    -parallel-testing-enabled NO \
    -derivedDataPath build/simulator \
    -resultBundlePath "build/UI-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}.xcresult" \
    "${signing[@]}" \
    "BROWSER_BUNDLE_ID=${bundle_id}" \
    "CURRENT_PROJECT_VERSION=${build_number}" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    2>&1 | tee build/ui-tests.log

if [[ "${BUILD_IPA:-1}" != "1" ]]; then
    exit 0
fi

xcodebuild build \
    -project PersonalBrowser.xcodeproj \
    -scheme PersonalBrowser \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath build/device \
    "${signing[@]}" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    "BROWSER_BUNDLE_ID=${bundle_id}" \
    "CURRENT_PROJECT_VERSION=${build_number}" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    2>&1 | tee build/device-build.log

package_dir="$(mktemp -d "${TMPDIR:-/tmp}/personal-browser.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "${package_dir}/Payload"
ditto build/device/Build/Products/Release-iphoneos/PersonalBrowser.app "${package_dir}/Payload/PersonalBrowser.app"
ditto -c -k --keepParent "${package_dir}/Payload" dist/PersonalBrowser.ipa
python3 scripts/inspect_ipa.py dist/PersonalBrowser.ipa \
    --unsigned --target-ios 18.4.1 --bundle-id "$bundle_id" > dist/build-info.json
cat dist/build-info.json
