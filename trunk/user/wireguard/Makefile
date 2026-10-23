SRC_NAME = wireguard
THISDIR = $(shell pwd)

all: 

config_test:

configure:

clean:

romfs:
	$(ROMFSINST) -p +x $(THISDIR)/wg-common.sh /usr/bin/wg-common.sh
	$(ROMFSINST) -p +x $(THISDIR)/wgc.sh /usr/bin/wgc.sh
	$(ROMFSINST) -p +x $(THISDIR)/wgs.sh /usr/bin/wgs.sh
	$(ROMFSINST) -p +x $(THISDIR)/wireguard.sh /usr/bin/wireguard.sh
