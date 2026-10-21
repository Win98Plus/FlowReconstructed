TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Messenger
ARCHS ?= arm64 arm64e
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Flow

Flow_FILES = Tweak.xm
Flow_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-parameter -Wno-undeclared-selector
Flow_CCFLAGS = -std=c++17 -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-parameter -Wno-undeclared-selector
Flow_FRAMEWORKS = UIKit Foundation CoreFoundation CoreGraphics Security QuartzCore
Flow_LIBRARIES = sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk

livecontainer: all
	@mkdir -p build_livecontainer
	@if [ -f "$(THEOS_OBJ_DIR)/Flow.dylib" ]; then \
		cp "$(THEOS_OBJ_DIR)/Flow.dylib" build_livecontainer/Flow.dylib; \
	elif [ -f ".theos/obj/Flow.dylib" ]; then \
		cp ".theos/obj/Flow.dylib" build_livecontainer/Flow.dylib; \
	elif [ -f ".theos/obj/debug/Flow.dylib" ]; then \
		cp ".theos/obj/debug/Flow.dylib" build_livecontainer/Flow.dylib; \
	fi