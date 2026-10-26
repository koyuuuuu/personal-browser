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
swift test --scratch-path .build/macos 2>&1 | tee build/core-tests.log

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

# Loopback servers are needed only by selected UI tests.
# Certificates are ephemeral, stay outside artifacts, and contain no user data.
fixture_dir=""
package_dir=""
fixture_pid=""
cleanup() {
    if [[ -n "$fixture_pid" ]]; then kill "$fixture_pid" 2>/dev/null || true; fi
    if [[ -n "$fixture_dir" ]]; then rm -rf "$fixture_dir"; fi
    if [[ -n "$package_dir" ]]; then rm -rf "$package_dir"; fi
}
trap cleanup EXIT
# No simulator boot, certificates, or UI fixtures for unrelated changes.
if [[ -n "${UI_TESTS:-}" ]]; then
    IFS=',' read -r -a ui_names <<< "$UI_TESTS"
    ui_selection=()
    for name in "${ui_names[@]}"; do
        if [[ ! "$name" =~ ^test[A-Za-z0-9_]+$ ]]; then
            echo 'Invalid selected UI test name.' >&2
            exit 1
        fi
        ui_selection+=("-only-testing:PersonalBrowserUITests/BrowserUITests/$name")
    done
    simulator_sdk="$(xcodebuild -version -sdk iphonesimulator SDKVersion)"
    simulator_id="$(xcrun simctl list devices available --json | python3 scripts/select_simulator.py --sdk-version "$simulator_sdk")"
    echo "Selected Simulator ${simulator_id} for SDK ${simulator_sdk}"
    fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/browser-web-fixtures.XXXXXX")"
    cat > "$fixture_dir/openssl.cnf" <<'CERT_CONFIG'
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=localhost
[v3]
subjectAltName=DNS:localhost,IP:127.0.0.1
CERT_CONFIG
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 -config "$fixture_dir/openssl.cnf" \
        -keyout "$fixture_dir/key.pem" -out "$fixture_dir/cert.pem" >/dev/null 2>&1
    python3 scripts/test_local_server.py --cert "$fixture_dir/cert.pem" --key "$fixture_dir/key.pem" --simulator-id "$simulator_id" &
    fixture_pid=$!
    for attempt in {1..50}; do
        if curl --silent --fail http://127.0.0.1:18765/health >/dev/null; then break; fi
        sleep 0.1
    done
    curl --silent --fail http://127.0.0.1:18765/health >/dev/null

    xcodebuild test \
        "${ui_selection[@]}" \
        -project PersonalBrowser.xcodeproj \
        -scheme PersonalBrowser \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=${simulator_id}" \
        -parallel-testing-enabled NO \
        ONLY_ACTIVE_ARCH=YES \
        -derivedDataPath build/simulator \
        -resultBundlePath "build/UI-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}.xcresult" \
        "${signing[@]}" \
        "BROWSER_BUNDLE_ID=${bundle_id}" \
        "CURRENT_PROJECT_VERSION=${build_number}" \
        COMPILER_INDEX_STORE_ENABLE=NO \
        2>&1 | tee build/ui-tests.log

else
    echo 'UI checks: not applicable to this change; no Simulator started.'
fi

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
mkdir -p "${package_dir}/Payload"
ditto build/device/Build/Products/Release-iphoneos/PersonalBrowser.app "${package_dir}/Payload/PersonalBrowser.app"
ditto -c -k --keepParent "${package_dir}/Payload" dist/PersonalBrowser.ipa
python3 scripts/inspect_ipa.py dist/PersonalBrowser.ipa \
    --unsigned --target-ios 18.4.1 --bundle-id "$bundle_id" > dist/build-info.json
cat dist/build-info.json
