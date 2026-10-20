TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Messenger
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Flow

Flow_FILES = Tweak.xm
Flow_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
Flow_FRAMEWORKS = UIKit Foundation CoreFoundation CoreGraphics QuartzCore Security
Flow_LIBRARIES = sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk
