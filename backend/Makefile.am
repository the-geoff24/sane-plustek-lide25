## backend/Makefile.am - Plustek USB scanning driver

lib_LTLIBRARIES = libsane-plustek.la

# USB-only scanner driver (no parallel port support)
libsane_plustek_la_SOURCES = \
    plustek.c \
    plustek-usb.c \
    plustek-usbio.c \
    plustek-usbscan.c \
    plustek-usbhw.c \
    plustek-usbmap.c \
    plustek-usbcal.c \
    plustek-usbcalfile.c \
    plustek-usbdevs.c \
    plustek-usbimg.c \
    plustek-usbshading.c

libsane_plustek_la_CPPFLAGS = $(AM_CPPFLAGS) $(LIBUSB_CFLAGS)
libsane_plustek_la_LDFLAGS = -version-info 1:0:0 -module -avoid-version
libsane_plustek_la_LIBADD = $(LIBUSB_LIBS) ../lib/libsanei_compat.la ../sanei/libsanei.a

# Device configuration
saned_confdir = $(sysconfdir)/sane.d
dist_saned_conf_DATA = plustek.conf.in

# Private headers
noinst_HEADERS = plustek.h plustek-usb.h
