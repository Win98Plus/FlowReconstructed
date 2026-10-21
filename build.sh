#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${PROJECT_DIR}/dist"
WORK_DIR="${PROJECT_DIR}/.build_work"
VERSION="1.0.3"
PACKAGE_ID="com.dvntm.flow"

rm -rf "${OUT_DIR}" "${WORK_DIR}"
mkdir -p "${OUT_DIR}" "${WORK_DIR}"

setup_theos() {
    if ! command -v dpkg-deb >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then
            brew install dpkg
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -y && sudo apt-get install -y dpkg
        fi
    fi
    if ! command -v ldid >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then
            brew install ldid
        fi
    fi
    if [[ -z "${THEOS:-}" ]]; then
        export THEOS="${PROJECT_DIR}/.theos_env"
    fi
    if [[ ! -d "${THEOS}/makefiles" ]]; then
        git clone --depth 1 https://github.com/theos/theos.git "${THEOS}"
        git -C "${THEOS}" submodule update --init --recursive
    fi
    local sdk_count=0
    if [[ -d "${THEOS}/sdks" ]]; then
        sdk_count=$(find "${THEOS}/sdks" -maxdepth 1 -name "*.sdk" | wc -l | tr -d " ")
    fi
    if [[ "${sdk_count}" -eq 0 ]]; then
        mkdir -p "${THEOS}/sdks"
        curl -sL https://github.com/theos/sdks/archive/refs/heads/master.tar.gz | tar -xz -C "${THEOS}/sdks" --strip-components=1
    fi
}

patch_for_livecontainer() {
    local dylib_path="$1"
    if command -v install_name_tool >/dev/null 2>&1; then
        install_name_tool -id "@rpath/Flow.dylib" "${dylib_path}" 2>/dev/null || true
        install_name_tool -change "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "${dylib_path}" 2>/dev/null || true
        install_name_tool -change "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "${dylib_path}" 2>/dev/null || true
        install_name_tool -change "/var/jb/usr/lib/libsubstrate.dylib" "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "${dylib_path}" 2>/dev/null || true
        install_name_tool -change "/usr/lib/libsubstrate.dylib" "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "${dylib_path}" 2>/dev/null || true
        install_name_tool -change "@loader_path/.jbroot/usr/lib/libsubstrate.dylib" "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "${dylib_path}" 2>/dev/null || true
    fi
    if command -v ldid >/dev/null 2>&1; then
        ldid -S "${dylib_path}" 2>/dev/null || true
    elif command -v codesign >/dev/null 2>&1; then
        codesign -f -s - "${dylib_path}" 2>/dev/null || true
    fi
}

package_deb() {
    local arch="$1"
    local prefix="$2"
    local id_path="$3"
    local sub_path="$4"
    local dylib_src="$5"
    local pkg_root="${WORK_DIR}/pkg_${arch}"
    local deb_out="${OUT_DIR}/${PACKAGE_ID}_${VERSION}_${arch}.deb"

    rm -rf "${pkg_root}"
    mkdir -p "${pkg_root}/DEBIAN"
    local dylib_dir="${pkg_root}${prefix}/Library/MobileSubstrate/DynamicLibraries"
    local app_support_dir="${pkg_root}${prefix}/Library/Application Support"
    mkdir -p "${dylib_dir}" "${app_support_dir}"

    cp "${dylib_src}" "${dylib_dir}/Flow.dylib"
    if command -v install_name_tool >/dev/null 2>&1; then
        install_name_tool -id "${id_path}" "${dylib_dir}/Flow.dylib" 2>/dev/null || true
        install_name_tool -change "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "${sub_path}" "${dylib_dir}/Flow.dylib" 2>/dev/null || true
        install_name_tool -change "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "${sub_path}" "${dylib_dir}/Flow.dylib" 2>/dev/null || true
        install_name_tool -change "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "${sub_path}" "${dylib_dir}/Flow.dylib" 2>/dev/null || true
        install_name_tool -change "/usr/lib/libsubstrate.dylib" "${sub_path}" "${dylib_dir}/Flow.dylib" 2>/dev/null || true
    fi
    if command -v ldid >/dev/null 2>&1; then
        ldid -S "${dylib_dir}/Flow.dylib" 2>/dev/null || true
    elif command -v codesign >/dev/null 2>&1; then
        codesign -f -s - "${dylib_dir}/Flow.dylib" 2>/dev/null || true
    fi

    cp "${PROJECT_DIR}/Flow.plist" "${dylib_dir}/Flow.plist"
    if [[ -d "${PROJECT_DIR}/Flow.bundle" ]]; then
        cp -R "${PROJECT_DIR}/Flow.bundle" "${app_support_dir}/Flow.bundle"
    elif [[ -d "${PROJECT_DIR}/layout/Library/Application Support/Flow.bundle" ]]; then
        cp -R "${PROJECT_DIR}/layout/Library/Application Support/Flow.bundle" "${app_support_dir}/Flow.bundle"
    fi

    local installed_size
    installed_size=$(du -sk "${pkg_root}" | awk '{print $1}')

    cat > "${pkg_root}/DEBIAN/control" <<CTRL
Package: ${PACKAGE_ID}
Name: Flow for Messenger
Version: ${VERSION}
Architecture: ${arch}
Description: A lightweight Messenger enhancer with Anti-Unsend Messages
Maintainer: dvntm, nowesr1
Author: dvntm, nowesr1
Section: Tweaks
Depends: mobilesubstrate (>= 0.9.5000)
Icon: https://raw.githubusercontent.com/dayanch96/Flow/refs/heads/main/Sileo/icon.png
SileoDepiction: https://raw.githubusercontent.com/dayanch96/Flow/main/Sileo/depiction.json
Installed-Size: ${installed_size}
CTRL

    find "${pkg_root}" -type d -exec chmod 0755 {} +
    find "${pkg_root}" -type f -exec chmod 0644 {} +
    chmod 0755 "${dylib_dir}/Flow.dylib"
    dpkg-deb -Zgzip --root-owner-group -b "${pkg_root}" "${deb_out}" >/dev/null
    dpkg-deb -I "${deb_out}" >/dev/null
}

setup_theos
make -C "${PROJECT_DIR}" clean
if ! make -C "${PROJECT_DIR}" livecontainer ARCHS="arm64 arm64e"; then
    make -C "${PROJECT_DIR}" clean
    make -C "${PROJECT_DIR}" livecontainer ARCHS="arm64"
fi
DYLIB_BUILT="${PROJECT_DIR}/build_livecontainer/Flow.dylib"

cp "${DYLIB_BUILT}" "${OUT_DIR}/Flow_${VERSION}.dylib"
patch_for_livecontainer "${OUT_DIR}/Flow_${VERSION}.dylib"
cp "${OUT_DIR}/Flow_${VERSION}.dylib" "${OUT_DIR}/Flow.dylib"

package_deb "iphoneos-arm" "" "/Library/MobileSubstrate/DynamicLibraries/Flow.dylib" "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "${DYLIB_BUILT}"
package_deb "iphoneos-arm64" "/var/jb" "/var/jb/Library/MobileSubstrate/DynamicLibraries/Flow.dylib" "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "${DYLIB_BUILT}"
package_deb "iphoneos-arm64e" "" "@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/Flow.dylib" "@loader_path/.jbroot/usr/lib/libsubstrate.dylib" "${DYLIB_BUILT}"

rm -rf "${WORK_DIR}"
ls -lh "${OUT_DIR}"