set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${PROJECT_DIR}/dist"
mkdir -p "${OUT_DIR}"

patch_for_livecontainer() {
    local dylib_path="$1"

    if command -v install_name_tool >/dev/null 2>&1; then
        install_name_tool -id "@rpath/Flow.dylib" "${dylib_path}" 2>/dev/null || true
        install_name_tool -change \
            "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" \
            "@rpath/CydiaSubstrate.framework/CydiaSubstrate" \
            "${dylib_path}" 2>/dev/null || true
        install_name_tool -change \
            "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" \
            "@rpath/CydiaSubstrate.framework/CydiaSubstrate" \
            "${dylib_path}" 2>/dev/null || true
        install_name_tool -change \
            "@loader_path/.jbroot/usr/lib/libsubstrate.dylib" \
            "@rpath/CydiaSubstrate.framework/CydiaSubstrate" \
            "${dylib_path}" 2>/dev/null || true
    fi

    if command -v ldid >/dev/null 2>&1; then
        ldid -S "${dylib_path}"
    elif command -v codesign >/dev/null 2>&1; then
        codesign -f -s - "${dylib_path}"
    fi
}

if [[ -n "${THEOS:-}" && -d "${THEOS}" ]]; then
    make -C "${PROJECT_DIR}" clean
    make -C "${PROJECT_DIR}" package FINALPACKAGE=1
    make -C "${PROJECT_DIR}" livecontainer
    cp "${PROJECT_DIR}/build_livecontainer/Flow.dylib" "${OUT_DIR}/Flow.dylib"
fi
