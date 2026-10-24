include $(ROOTDIR)/rules.mk

# Same https_dns_proxy revision as padavan-ng, pinned rather than master.
PKG_NAME:=https_dns_proxy
PKG_VERSION:=0ba0525fa7c10115cc7c92e99621bfe484ae96e7
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/aarond10/https_dns_proxy/tar.gz
PKG_SOURCE_URL_FILE:=$(PKG_VERSION)
PKG_HASH:=d8de8b5e42b46088c8aa5e515e2326a3f3e3d65caaae8e37aec801a98cfa592e

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

# Resolve libcurl's indirect shared-library dependencies from the firmware stage.
TARGET_LDFLAGS += -Wl,-rpath-link,$(STAGING_DIR)/lib

CMAKE_BINARY_SUBDIR:=build
CMAKE_OPTIONS += -DCMAKE_DISABLE_FIND_PACKAGE_Git=ON -DSW_VERSION=git-0ba0525 \
	-DUSE_CLANG_TIDY=OFF -DHAVE_SD_DAEMON_H=OFF

$(eval $(call BuildPackage,https_dns_proxy))

# Refresh cached CMake linker flags when this recipe changes.
$(STAMP_CONFIGURED): Makefile

romfs:
	$(INSTALL_DIR) $(ROMFSDIR)/usr/sbin $(ROMFSDIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/build/https_dns_proxy $(ROMFSDIR)/usr/sbin/
	$(INSTALL_BIN) doh_proxy.sh $(ROMFSDIR)/usr/bin/
