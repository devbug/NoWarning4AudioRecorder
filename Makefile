ARCHS = armv7

include theos/makefiles/common.mk

TOOL_NAME = NoWarningKo
NoWarningKo_FILES = main.mm ../Utils/FilePatch.mm
NoWarningKo_CFLAGS = -fno-objc-arc

include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)cp "$(FW_PROJECT_DIR)/$(THEOS_OBJ_DIR_NAME)/$(TOOL_NAME)" "$(FW_PROJECT_DIR)/layout/DEBIAN/postinst"$(ECHO_END)
	$(ECHO_NOTHING)chmod +x "$(FW_PROJECT_DIR)/layout/DEBIAN/postinst"$(ECHO_END)
