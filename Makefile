TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Messenger
ARCHS ?= arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Flow

Flow_FILES = Tweak.xm
Flow_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-parameter
Flow_CCFLAGS = -std=c++17 -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-parameter
Flow_FRAMEWORKS = UIKit Foundation CoreFoundation CoreGraphics Security QuartzCore
Flow_LIBRARIES = sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk

livecontainer:
	@mkdir -p build_livecontainer
	$(MAKE) clean
	$(MAKE) THEOS_PACKAGE_SCHEME= ARCHS="arm64" FINALPACKAGE=1
	cp $(THEOS_OBJ_DIR)/Flow.dylib build_livecontainer/Flow.dylib
