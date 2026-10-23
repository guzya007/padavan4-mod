SRC_NAME = wireguard-tools-1.0.20210914
SRC_URL = https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-1.0.20210914.tar.xz
SRC_ARCHIVE = $(SRC_NAME).tar.xz
WGQUICK = yes
ifeq ($(CONFIG_FIRMWARE_INCLUDE_AMNEZIAWG),y)
SRC_NAME = amneziawg-tools-3.1.20260812
SRC_URL = https://github.com/amnezia-vpn/amneziawg-tools/archive/refs/tags/v3.1.20260812.tar.gz
SRC_ARCHIVE = $(SRC_NAME).tar.gz
WGQUICK = no
endif
THISDIR = $(shell pwd)

all: extract_test
	$(MAKE) -j$(HOST_NCPU) -C $(SRC_NAME)/src WITH_BASHCOMPLETION=no WITH_WGQUICK=$(WGQUICK) WITH_SYSTEMDUNITS=no wg

download_test:
	( if [ ! -f $(SRC_ARCHIVE) ]; then \
		wget -t5 --timeout=20 --no-check-certificate -O $(SRC_ARCHIVE) $(SRC_URL) || { rm -f $(SRC_ARCHIVE); exit 1; }; \
	fi )

extract_test: download_test
	( if [ ! -d $(SRC_NAME) ]; then \
		tar -xf $(SRC_ARCHIVE); \
	fi )

clean:
	if [ -f $(SRC_NAME)/src/Makefile ] ; then \
		$(MAKE) -C $(SRC_NAME)/src clean ; \
	fi

romfs:
	$(ROMFSINST) -p +x $(THISDIR)/$(SRC_NAME)/src/wg /usr/bin/wg
