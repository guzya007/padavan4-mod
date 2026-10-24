.EXPORT_ALL_VARIABLES:
.PHONY: all romfs clean

ifndef ROOTDIR
ROOTDIR=..
endif
ifndef ROMFSDIR
ROMFSDIR=$(ROOTDIR)/romfs
endif

include $(PROJECT_CONFIG)
include $(ARCH_CONFIG)

DESTDIR=$(ROOTDIR)/stage

LIBC=$(if $(findstring musl,$(CROSS_COMPILE)),musl,uclibc)

all:
	$(MAKE) -C $(LIBC)

%_only:
	$(MAKE) -C $(@:_only=)

%_romfs:
	$(MAKE) -C $(@:_romfs=) romfs

%_clean:
	$(MAKE) -C $(@:_clean=) clean

romfs:
	$(MAKE) -C $(LIBC) romfs
	# OpenSSL threads and libusb need GCC's atomic runtime on MIPS32.
	@libatomic="$$($(CC) -print-file-name=libatomic.so.1)" || exit 1; \
	if [ "$$libatomic" = libatomic.so.1 ] || [ ! -f "$$libatomic" ]; then \
		echo "ERROR: target toolchain is missing libatomic.so.1" >&2; \
		exit 1; \
	fi; \
	install -m 644 "$$libatomic" "$(ROMFSDIR)/lib/libatomic.so.1"

clean:
	$(MAKE) -C $(LIBC) clean
