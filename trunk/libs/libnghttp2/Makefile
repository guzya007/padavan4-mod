include $(ROOTDIR)/rules.mk

PKG_NAME:=nghttp2
PKG_VERSION:=1.69.0
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://github.com/nghttp2/nghttp2/releases/download/v$(PKG_VERSION)
PKG_HASH:=1fb324b6ec2c56f6bde0658f4139ffd8209fa9e77ce98fd7a5f63af8d0e508ad

include $(INCLUDE_DIR)/package.mk

CONFIGURE_ARGS += --enable-lib-only --enable-shared --disable-static

$(eval $(call BuildPackage,nghttp2))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/lib
	$(CP) $(PKG_INSTALL_DIR)/lib/libnghttp2.so* $(ROMFSDIR)/lib/
