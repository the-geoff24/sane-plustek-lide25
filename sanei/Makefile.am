## sanei/Makefile.am - USB and device config support

noinst_LIBRARIES = libsanei.a

# Core USB and configuration only
libsanei_a_SOURCES = \
    sanei_usb.c \
    sanei_config.c \
    sanei_config2.c \
    sanei_init_debug.c \
    sanei_constrain_value.c

libsanei_a_CPPFLAGS = $(AM_CPPFLAGS) $(LIBUSB_CFLAGS)
