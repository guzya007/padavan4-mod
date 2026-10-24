#ifndef D2K_PADAVAN_COMPAT_H
#define D2K_PADAVAN_COMPAT_H

#include <netinet/in.h>
/* Linux socket ABI; absent from older uClibc headers. */
#ifndef IPV6_HDRINCL
#define IPV6_HDRINCL 36
#endif

#endif
