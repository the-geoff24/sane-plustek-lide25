## frontend/Makefile.am - Scanning CLI tools

bin_PROGRAMS = scanimage

# scanimage: CLI tool for scanning documents
scanimage_SOURCES = scanimage.c stiff.c jpegtopdf.c
scanimage_CPPFLAGS = $(AM_CPPFLAGS)
scanimage_LDFLAGS = -Wl,-rpath,$(libdir)
scanimage_LDADD = ../lib/libsanei_compat.la ../sanei/libsanei.a
