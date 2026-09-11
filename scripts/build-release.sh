#!/bin/bash
set -euo pipefail

# DockNet Release Build & DMG Packaging Script
# Produces an ad-hoc signed Apple Silicon (arm64) macOS application and DMG.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-${MARKETING_VERSION:-}}"
if [ -z "${VERSION}" ]; then
    # Attempt to derive from git tag or fallback to 2.0.0
    VERSION="$(git describe --tags --exact-match 2>/dev/null || echo "2.0.0")"
fi
VERSION="${VERSION#v}" # Strip leading 'v' if present

BUILD_NUMBER="${2:-${GITHUB_RUN_NUMBER:-${CURRENT_PROJECT_VERSION:-2}}}"

echo "=================================================="
echo "Building DockNet Release (arm64)"
echo "Version:      ${VERSION}"
echo "Build Number: ${BUILD_NUMBER}"
echo "Root:         ${ROOT_DIR}"
echo "=================================================="

cd "${ROOT_DIR}"

DERIVED_DATA="${ROOT_DIR}/build/DerivedData"
RELEASE_DIR="${DERIVED_DATA}/Build/Products/Release"
APP_PATH="${RELEASE_DIR}/DockNet.app"
BINARY_PATH="${APP_PATH}/Contents/MacOS/DockNet"
DIST_DIR="${ROOT_DIR}/dist"
STAGING_DIR="${ROOT_DIR}/build/staging"
DMG_NAME="DockNet-${VERSION}-macOS-arm64.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
CHECKSUM_NAME="${DMG_NAME}.sha256"
CHECKSUM_PATH="${DIST_DIR}/${CHECKSUM_NAME}"

echo "--> Compiling Apple Silicon Release Binary (arm64)..."
xcodebuild \
    -project DockNet.xcodeproj \
    -scheme DockNet \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="arm64" \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    build

if [ ! -d "${APP_PATH}" ]; then
    echo "ERROR: ${APP_PATH} was not found after build." >&2
    exit 1
fi

echo "--> Verifying Architecture with lipo..."
file "${BINARY_PATH}"
LIPO_OUTPUT="$(lipo -info "${BINARY_PATH}")"
echo "${LIPO_OUTPUT}"

if ! echo "${LIPO_OUTPUT}" | grep -q "arm64"; then
    echo "ERROR: arm64 architecture missing from ${BINARY_PATH}" >&2
    exit 1
fi

if echo "${LIPO_OUTPUT}" | grep -q "x86_64"; then
    echo "ERROR: x86_64 architecture unexpectedly present in ${BINARY_PATH}" >&2
    exit 1
fi

echo "--> Apple Silicon binary verified: arm64 only."

echo "--> Code Signing (Ad-hoc)..."
echo "Signing: ad-hoc"
echo "Developer ID: none"
echo "Notarization: none"

codesign --force --deep --sign - "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign -dv --verbose=4 "${APP_PATH}"

echo "--> Preparing DMG Staging Directory..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/DockNet.app"
ln -s /Applications "${STAGING_DIR}/Applications"

mkdir -p "${DIST_DIR}"
rm -f "${DMG_PATH}" "${CHECKSUM_PATH}"

echo "--> Creating compressed read-only DMG with hdiutil..."
hdiutil create \
    -volname "DockNet" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

echo "--> Verifying DMG image..."
hdiutil verify "${DMG_PATH}"

echo "--> Testing DMG mount..."
MOUNT_DIR="$(mktemp -d /tmp/docknet-dmg-test.XXXXXX)"
hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_DIR}" -nobrowse -readonly
if [ ! -d "${MOUNT_DIR}/DockNet.app" ]; then
    echo "ERROR: DockNet.app missing inside mounted DMG." >&2
    hdiutil detach "${MOUNT_DIR}" || true
    exit 1
fi
if [ ! -L "${MOUNT_DIR}/Applications" ]; then
    echo "ERROR: Applications symlink missing inside mounted DMG." >&2
    hdiutil detach "${MOUNT_DIR}" || true
    exit 1
fi
hdiutil detach "${MOUNT_DIR}"
rm -rf "${MOUNT_DIR}"

echo "--> Generating SHA-256 Checksum..."
(
    cd "${DIST_DIR}"
    shasum -a 256 "${DMG_NAME}" > "${CHECKSUM_NAME}"
)

echo "=================================================="
echo "Release Build Succeeded!"
echo "Artifacts in ${DIST_DIR}:"
ls -lh "${DIST_DIR}"
echo "--------------------------------------------------"
cat "${CHECKSUM_PATH}"
echo "=================================================="
