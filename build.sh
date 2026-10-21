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
    local sub_path="$3"
    local dylib_src="$4"
    local pkg_root="${WORK_DIR}/pkg_${arch}"
    local deb_out="${OUT_DIR}/${PACKAGE_ID}_${VERSION}_${arch}.deb"

    rm -rf "${pkg_root}"
    mkdir -p "${pkg_root}/DEBIAN"
    local dylib_dir="${pkg_root}${prefix}/Library/MobileSubstrate/DynamicLibraries"
    local bundle_dir="${pkg_root}${prefix}/Library/Application Support/Flow"
    mkdir -p "${dylib_dir}" "${bundle_dir}"

    cp "${dylib_src}" "${dylib_dir}/Flow.dylib"
    if command -v install_name_tool >/dev/null 2>&1; then
        install_name_tool -id "${prefix}/Library/MobileSubstrate/DynamicLibraries/Flow.dylib" "${dylib_dir}/Flow.dylib" 2>/dev/null || true
        install_name_tool -change "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "${sub_path}" "${dylib_dir}/Flow.dylib" 2>/dev/null || true
        install_name_tool -change "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "${sub_path}" "${dylib_dir}/Flow.dylib" 2>/dev/null || true
    fi
    if command -v ldid >/dev/null 2>&1; then
        ldid -S "${dylib_dir}/Flow.dylib" 2>/dev/null || true
    elif command -v codesign >/dev/null 2>&1; then
        codesign -f -s - "${dylib_dir}/Flow.dylib" 2>/dev/null || true
    fi

    cp "${PROJECT_DIR}/Flow.plist" "${dylib_dir}/Flow.plist"
    if [[ -d "${PROJECT_DIR}/Flow.bundle" ]]; then
        cp -R "${PROJECT_DIR}/Flow.bundle" "${bundle_dir}/"
    fi

    local installed_size
    installed_size=$(du -sk "${pkg_root}" | awk '{print $1}')

    cat > "${pkg_root}/DEBIAN/control" <<CTRL
Package: ${PACKAGE_ID}
Name: Flow for Messenger
Version: ${VERSION}
Architecture: ${arch}
Description: Flow for Messenger with Anti-Unsend Messages, Stealth Mode, Story Controls, and crash logging.
Maintainer: dvntm
Author: dvntm
Section: Tweaks
Depends: mobilesubstrate (>= 0.9.5000)
Installed-Size: ${installed_size}
CTRL

    chmod -R 0755 "${pkg_root}"
    dpkg-deb -Zgzip --root-owner-group -b "${pkg_root}" "${deb_out}" >/dev/null
}

setup_theos
make -C "${PROJECT_DIR}" livecontainer
DYLIB_BUILT="${PROJECT_DIR}/build_livecontainer/Flow.dylib"

cp "${DYLIB_BUILT}" "${OUT_DIR}/Flow_${VERSION}.dylib"
patch_for_livecontainer "${OUT_DIR}/Flow_${VERSION}.dylib"
cp "${OUT_DIR}/Flow_${VERSION}.dylib" "${OUT_DIR}/Flow.dylib"

package_deb "iphoneos-arm" "" "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "${DYLIB_BUILT}"
package_deb "iphoneos-arm64" "/var/jb" "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "${DYLIB_BUILT}"
package_deb "iphoneos-arm64e" "" "@loader_path/.jbroot/usr/lib/libsubstrate.dylib" "${DYLIB_BUILT}"

rm -rf "${WORK_DIR}"
