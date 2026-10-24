include $(ROOTDIR)/rules.mk

# D2K 24.10.2026, d2k-20261024-1911-fe4443e.
PKG_NAME:=d2k
PKG_VERSION:=fe4443e88bdbf294086d7766d66281d18dd676fe
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/necronicle/d2k/tar.gz
PKG_SOURCE_URL_FILE:=$(PKG_VERSION)
PKG_HASH:=d1ea6440d89fbee7f566dfce334c656b7458ab4f2b0481b8fcdad477e060a3d5

include $(INCLUDE_DIR)/package.mk

RELEASE_ID:=padavan-fe4443e
D2K_CFLAGS=$(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -D_DEFAULT_SOURCE \
	-Iinclude -I../core/include -I../datapath/include -I../detect/include \
	-include $(CURDIR)/padavan-compat.h

# Environment CFLAGS preserve upstream additions (release ID, UDP archive).
define Build/Configure
endef

define Build/Compile
	CFLAGS="$(D2K_CFLAGS) -std=gnu99" LDFLAGS="$(TARGET_LDFLAGS)" \
		$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR)/datapath d2kd CC="$(TARGET_CC)" RELEASE_ID=$(RELEASE_ID)
	CFLAGS="$(D2K_CFLAGS) -std=gnu99" LDFLAGS="$(TARGET_LDFLAGS)" \
		$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR)/core d2kc CC="$(TARGET_CC)" AR="$(TARGET_AR)" RELEASE_ID=$(RELEASE_ID)
	CFLAGS="$(D2K_CFLAGS) -std=gnu11 -DD2K_PANEL_VERSION='\"$(RELEASE_ID)\"' -DD2K_PANEL_COMMIT='\"$(PKG_VERSION)\"'" \
		$(MAKE) -C $(PKG_BUILD_DIR)/panel d2kpanel CC="$(TARGET_CC)" RELEASE_ID=$(RELEASE_ID)
endef

ifeq ($(CONFIG_FIRMWARE_INCLUDE_D2K_TELEGRAM),y)
define Build/Telegram
	$(MAKE) -C $(PKG_BUILD_DIR)/telegram d2ktg CC="$(TARGET_CC)" RELEASE_ID=$(RELEASE_ID) \
		BUILD_DIR=build CFLAGS="$(D2K_CFLAGS) -std=gnu11" \
		OPENSSL_CFLAGS="-I$(STAGING_DIR)/include" \
		OPENSSL_LIBS="$(TARGET_LDFLAGS) -lssl -lcrypto"
endef
Hooks/Compile/Post += Build/Telegram
endif

$(eval $(call BuildPackage,d2k))

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/sbin $(ROMFSDIR)/usr/bin $(ROMFSDIR)/usr/share/d2k/files/fake
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/datapath/d2kd $(ROMFSDIR)/usr/sbin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/core/d2kc $(ROMFSDIR)/usr/sbin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/panel/d2kpanel $(ROMFSDIR)/usr/sbin/
	$(INSTALL_BIN) d2k.sh $(ROMFSDIR)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/S99d2k $(ROMFSDIR)/usr/share/d2k/d2k-service
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/d2k-fw-heal.sh $(ROMFSDIR)/usr/share/d2k/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/d2k-log-maintenance.sh $(ROMFSDIR)/usr/share/d2k/
	$(INSTALL_DATA) config.default $(ROMFSDIR)/usr/share/d2k/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/meta-ranges.txt $(ROMFSDIR)/usr/share/d2k/files/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/fake/stun.bin $(ROMFSDIR)/usr/share/d2k/files/fake/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/fake/quic_initial_dbankcloud_ru.bin $(ROMFSDIR)/usr/share/d2k/files/fake/
	$(INSTALL_DIR) $(ROMFSDIR)/usr/share/d2k/panel
	$(CP) $(PKG_BUILD_DIR)/internal/web/assets/. $(ROMFSDIR)/usr/share/d2k/panel/
# No Entware updater, Keenetic DNS/PPE helpers, tests or build tools in ROM.
ifeq ($(CONFIG_FIRMWARE_INCLUDE_D2K_TELEGRAM),y)
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/telegram/build/d2ktg $(ROMFSDIR)/usr/sbin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/d2k-tg-firewall.sh $(ROMFSDIR)/usr/share/d2k/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/d2k-tg-watchdog.sh $(ROMFSDIR)/usr/share/d2k/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/tg-roots.pem $(ROMFSDIR)/usr/share/d2k/files/
endif
