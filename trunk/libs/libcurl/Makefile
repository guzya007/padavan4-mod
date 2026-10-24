include $(ROOTDIR)/rules.mk

PKG_NAME:=curl
PKG_VERSION:=8.21.0

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://github.com/curl/curl/releases/download/curl-$(subst .,_,$(PKG_VERSION))/
PKG_HASH:=aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6

include $(INCLUDE_DIR)/package.mk

CONFIGURE_ARGS += \
	--disable-static \
	--enable-shared \
	--enable-ipv6 \
	--disable-ldap \
	--disable-rtsp \
	--disable-smb \
	--disable-telnet \
	--disable-tftp \
	--disable-dict \
	--disable-gopher \
	--disable-imap \
	--disable-pop3 \
	--disable-smtp \
	--disable-debug \
	--disable-docs \
	--without-libidn2 \
	--without-libssh2 \
	--without-libpsl \
	--without-zstd \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
	--with-zlib=$(STAGING_DIR) \
	--with-openssl=$(STAGING_DIR)
ifeq ($(CONFIG_FIRMWARE_INCLUDE_DOH),y)
CONFIGURE_ARGS += --with-nghttp2=$(STAGING_DIR)
else
CONFIGURE_ARGS += --without-nghttp2
endif
D2K_TELEGRAM_ENABLED:=$(if $(filter y,$(CONFIG_FIRMWARE_INCLUDE_D2K)),$(CONFIG_FIRMWARE_INCLUDE_D2K_TELEGRAM))

$(eval $(call BuildPackage,curl))

romfs:
ifneq ($(filter y,$(CONFIG_FIRMWARE_INCLUDE_CURL) $(D2K_TELEGRAM_ENABLED)),)
	$(INSTALL_DIR) $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/curl $(ROMFSDIR)/usr/bin/
endif
	$(INSTALL_DIR) $(ROMFSDIR)/lib
	$(CP) $(PKG_INSTALL_DIR)/lib/libcurl.so* $(ROMFSDIR)/lib/
