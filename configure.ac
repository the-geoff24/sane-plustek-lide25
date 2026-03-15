dnl Minimal SANE backend for Canon CanoScan LiDE 25 - Scanning only

AC_INIT([sane-plustek-lide25], [1.0.0], [user@example.com])
AC_CONFIG_SRCDIR([backend/plustek.c])
AC_CONFIG_HEADERS([include/sane/config.h])

AM_INIT_AUTOMAKE([1.15 subdir-objects -Wall])
AM_SILENT_RULES([yes])

AC_PROG_CC
AC_PROG_CC_C99
AC_PROG_RANLIB

LT_INIT([disable-static win32-dll])
LT_PREREQ([2.4.6])

AC_SUBST(AM_CFLAGS, '-Wall -Wextra -Wno-unused')
AC_SUBST(AM_CPPFLAGS, '-I$(top_srcdir)/include')

dnl Check for libusb-1.0 (REQUIRED for USB scanning)
PKG_CHECK_MODULES([LIBUSB], [libusb-1.0 >= 1.0.0],
    [AC_DEFINE([HAVE_LIBUSB], [1], [libusb available])],
    [AC_MSG_ERROR([libusb-1.0 not found. Install libusb-1.0-dev])])

AC_SUBST(LIBUSB_CFLAGS)
AC_SUBST(LIBUSB_LIBS)

dnl Essential functions only
AC_SEARCH_LIBS([strerror], [cposix])
AC_CHECK_FUNCS([memset strcasecmp strdup strerror])

AC_CONFIG_FILES([Makefile include/Makefile include/sane/Makefile \
                 backend/Makefile sanei/Makefile lib/Makefile frontend/Makefile])

AC_OUTPUT
echo ""
echo "Configuration complete! Build with:"
echo "  make -j4          # Build"
echo "  make install      # Install"
echo ""
