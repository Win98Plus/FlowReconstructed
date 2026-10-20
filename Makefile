TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Messenger
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Flow

Flow_FILES = Tweak.xm
Flow_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
Flow_FRAMEWORKS = Foundation CoreFoundation CoreGraphics CoreServices Security UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

before-all::
	@if [ ! -f control ]; then \
		printf "Package: com.dvntm.flow\nName: Flow for Messenger\nDescription: A lightweight Messenger enhancer (Bug-Fixed v1.0.1)\nMaintainer: dvntm, nowesr1\nAuthor: dvntm, nowesr1\nSection: Tweaks\nDepends: mobilesubstrate (>= 0.9.5000)\nIcon: https://raw.githubusercontent.com/dayanch96/Flow/refs/heads/main/Sileo/icon.png\nSileoDepiction: https://raw.githubusercontent.com/dayanch96/Flow/main/Sileo/depiction.json\nArchitecture: iphoneos-arm64e\nVersion: 1.0.1\n" > control; \
	fi
	@if [ ! -f Flow.plist ]; then \
		printf '{ Filter = { Bundles = ( "com.facebook.Messenger" ); }; }\n' > Flow.plist; \
	fi

.PHONY: livecontainer
livecontainer: all
	@mkdir -p build_livecontainer
	@cp $(THEOS_OBJ_DIR)/Flow.dylib build_livecontainer/Flow.dylib
	@if command -v install_name_tool >/dev/null 2>&1; then \
		install_name_tool -change /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate @rpath/CydiaSubstrate.framework/CydiaSubstrate build_livecontainer/Flow.dylib || true; \
		install_name_tool -change /var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate @rpath/CydiaSubstrate.framework/CydiaSubstrate build_livecontainer/Flow.dylib || true; \
		install_name_tool -change @loader_path/.jbroot/usr/lib/libsubstrate.dylib @rpath/CydiaSubstrate.framework/CydiaSubstrate build_livecontainer/Flow.dylib || true; \
		install_name_tool -id @rpath/Flow.dylib build_livecontainer/Flow.dylib || true; \
	fi
	@if command -v ldid >/dev/null 2>&1; then \
		ldid -S build_livecontainer/Flow.dylib; \
	elif command -v codesign >/dev/null 2>&1; then \
		codesign -f -s - build_livecontainer/Flow.dylib; \
	fi
	@echo "LiveContainer dylib ready at: build_livecontainer/Flow.dylib"
