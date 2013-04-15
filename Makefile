ARCHS = armv7
TARGET = iphone:clang:6.0:6.0

include theos/makefiles/common.mk

TOOL_NAME = NoWarningKo
NoWarningKo_FILES = main.mm ../Utils/FilePatch.mm
NoWarningKo_CFLAGS = -fno-objc-arc

include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)cp obj/NoWarningKo layout/DEBIAN/postinst$(ECHO_END)
	$(ECHO_NOTHING)chmod +x layout/DEBIAN/postinst$(ECHO_END)
