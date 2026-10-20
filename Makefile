TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Flow

Flow_FILES = Tweak.xm
Flow_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
Flow_LDFLAGS = -Wl,-install_name,@rpath/Flow.dylib
Flow_FRAMEWORKS = UIKit Foundation CoreFoundation CoreGraphics QuartzCore Security
Flow_LIBRARIES = sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk

after-Flow-stage::
	install_name_tool -id "@rpath/Flow.dylib" "$(THEOS_OBJ_DIR)/Flow.dylib" 2>/dev/null || true
	install_name_tool -change "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "$(THEOS_OBJ_DIR)/Flow.dylib" 2>/dev/null || true
	install_name_tool -change "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate" "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "$(THEOS_OBJ_DIR)/Flow.dylib" 2>/dev/null || true
	install_name_tool -change "@loader_path/.jbroot/usr/lib/libsubstrate.dylib" "@rpath/CydiaSubstrate.framework/CydiaSubstrate" "$(THEOS_OBJ_DIR)/Flow.dylib" 2>/dev/null || true
