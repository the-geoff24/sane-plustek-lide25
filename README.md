# SANE Backend for Canon CanoScan LiDE 25

A minimal, stripped-down SANE (Scanner Access Now Easy) backend for scanning documents with the Canon CanoScan LiDE 25.

## Features

- **Document Scanning**: Scan documents and save as images
- **Simple Output**: PNM, TIFF, or raw image formats
- **USB Detection**: Automatic scanner discovery
- **Minimal Code**: Only essential scanning functionality (no networking, no advanced features)
- **One Command**: `scanimage -d plustek > scan.pnm`

## Device Information

| Property | Value |
|----------|-------|
| Scanner Model | Canon CanoScan LiDE 25 |
| USB Vendor ID | 0x04a9 |
| USB Product ID | 0x2220 |
| Interface | USB |
| Support Status | Fully supported |

## Prerequisites

### Build Requirements
)
- **GNU Autotools**: autoconf, automake, libtool
- **libusb-1.0-dev**: USB library

### Runtime Requirements

- **libusb-1.0**: USB communication library only
- **Linux kernel** with USB HID support (for Linux systems)

### Installation on Different Systems

#### Ubuntu/Debian
```bash
sudo apt-get install build-essential autoconf automake libtool
sudo apt-get install libusb-1.0-0-dev pkg-config
```

#### Fedora/RHEL/CentOS
```bash
sudo dnf install gcc autoconf automake libtool
sudo dnf install libusb1-devel pkg-config
```

#### macOS (with Homebrew)
```bash
brew install autoconf automake libtool
brew install libusb pkg-config
```

#### Windows (MSYS2)
```bash
pacman -S base-devel mingw-w64-x86_64-toolchain
pacman -S mingw-w64-x86_64-libusb mingw-w64-x86_64-pkg-config
```

## Building

### 1. Clone/Extract the Project
```bash
cd sane-plustek-lide25
```

### 2. Generate Build Configuration
```bash
./autogen.sh
```

This creates the `configure` script using autoconf and automake.

### 3. Configure the Build
```bash
./configure --prefix=/usr/local
```

**Configure Options:**
- `--prefix=/usr/local` — Installation prefix (default)
- `--prefix=/usr` — System-wide installation (requires root)
- `--enable-shared` — Build shared libraries (default)
- `--disable-static` — Don't build static libraries

**Examples:**
```bash
# Development build (local prefix)
./configure --prefix=$HOME/sane-build

# System installation
./configure --prefix=/usr

# With debugging symbols
./configure CFLAGS="-g -O0" --prefix=/usr/local
```

### 4. Compile
```bash
make -j4
```

The `-j4` flag uses 4 parallel jobs (adjust based on your CPU cores).

### 5. Install

**Local Installation (no root required):**
```bash
make install
export LD_LIBRARY_PATH=$HOME/sane-build/lib:$LD_LIBRARY_PATH
export PATH=$HOME/sane-build/bin:$PATH
```

**System Installation (requires root):**
```bash
sudo make install
sudo ldconfig
```

## Usage

### Find Scanner
```bash
scanimage -A
```

### Scan Document
```bash
# Scan as PNM image
scanimage -d plustek > document.pnm

# Scan as TIFF
scanimage -d plustek --format=tiff > document.tiff

# Different resolutions
scanimage -d plustek --resolution 150 > scan-150dpi.pnm
scanimage -d plustek --resolution 300 > scan-300dpi.pnm

# Greyscale only (faster)
scanimage -d plustek --mode Gray > scan-grey.pnm
```

## Installation on Remote Devices

### Method 1: Cross-Compilation

For different architecture (e.g., ARM, MIPS):

```bash
# Configure for ARM target
./configure --host=arm-linux-gnueabihf \
            --prefix=/usr/local \
            CC=arm-linux-gnueabihf-gcc

make
make DESTDIR=/tmp/arm-staging install

# Transfer to target device
scp -r /tmp/arm-staging/* user@device:/
```

### Method 2: Docker Container (Consistent Environment)

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    build-essential autoconf automake libtool \
    libusb-1.0-0-dev pkg-config

WORKDIR /build
COPY . .

RUN ./autogen.sh && \
    ./configure --prefix=/usr/local && \
    make && \
    make install

CMD ["/bin/bash"]
```

Build and transfer:
```bash
docker build -t sane-plustek:latest .
docker run -v /tmp/sane-install:/install sane-plustek:latest \
  sh -c "make DESTDIR=/install install"
```

### Method 3: SSH Remote Installation

```bash
# On build machine
make install DESTDIR=/tmp/sane-install
tar czf sane-plustek-lide25.tar.gz -C /tmp sane-install/

# Transfer to target
scp sane-plustek-lide25.tar.gz user@device:/tmp/

# On target device
cd /
sudo tar xzf /tmp/sane-plustek-lide25.tar.gz

# Update library cache
sudo ldconfig
```

### Method 4: Package Creation

Create an installable package for your target system:

```bash
# For Debian/Ubuntu (.deb)
./configure --prefix=/usr
make
checkinstall --pkgname="sane-plustek-lide25" --pkgversion="1.0" \
  --maintainer="your@email.com" make install

# For RPM-based systems (.rpm)
./configure --prefix=/usr
make
fpm -s dir -t rpm -n "sane-plustek-lide25" -v "1.0" \
  -C /tmp/sane-install usr/
```

## Configuration Files

### Device Configuration
- **Location**: `/usr/local/etc/sane.d/plustek.conf` (after installation)
- **Purpose**: Device discovery and connection parameters

Default entries:
```conf
# USB devices
usb 0x04a9 0x2220    # Canon CanoScan LiDE 25
```

### Backend Library
- **Shared Library**: `libsane-plustek.so` (Linux)
- **Shared Library**: `libsane-plustek.dylib` (macOS)
- **DLL**: `libsane-plustek.dll` (Windows)
- **Location**: `{prefix}/lib/sane/` or `{prefix}/lib64/sane/`

## Uninstallation

### From Source Build
```bash
# If you still have the build directory
cd sane-plustek-lide25
make uninstall

# Or manually remove (if using --prefix=/usr/local)
rm /usr/local/bin/scanimage
rm /usr/local/lib/libsane.so*
rm /usr/local/lib/sane/libsane-plustek.so*
rm /usr/local/etc/sane.d/plustek.conf
rm /usr/local/share/man/man1/scanimage.1
sudo ldconfig
```

### From System Package
```bash
# Debian/Ubuntu
sudo apt-get remove sane-plustek-lide25

# Fedora/RHEL
sudo dnf remove sane-plustek-lide25

# Generic (if using fpm)
sudo rpm -e sane-plustek-lide25
```

## Troubleshooting

### Scanner Not Detected

1. Check USB connection:
```bash
lsusb | grep Canon
# Should show: Bus XXX Device YYY: ID 04a9:2220 Canon, Inc.
```

2. Verify libusb can access device:
```bash
lsusb -v -d 04a9:2220
```

3. Check permissions:
```bash
# Linux: USB devices require proper udev rules
sudo usermod -a -G scanner $USER
# Then log out and back in
```

### Library Not Found

```bash
# If running from custom prefix
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH

# Verify library is installed
ls -la /usr/local/lib/libsane.so*
```

### Build Errors

```bash
# Clean and rebuild
make distclean
./autogen.sh
./configure ...
make clean
make
Minimal Project Structure

```
sane-plustek-lide25/
├── README.md
├── LICENSE
├── autogen.sh
├── configure.ac
├── Makefile.am
├── include/sane/
│   ├── sane.h             # SANE API
│   ├── sanei_backend.h    # Backend interface
│   ├── sanei_usb.h        # USB functions
│   ├── sanei_config.h     # Device discovery
│   └── saneopts.h         # Scanner options
├── backend/
│   ├── plustek.c          # Scanner driver
│   ├── plustek.h
│   ├── plustek-usb.c/h    # USB communication
│   └── plustek.conf.in
├── sanei/
│   ├── sanei_usb.c        # USB stack
│   └── sanei_config.c     # Auto-detect scanner
├── lib/
│   ├── getopt.c           # Command-line parsing only
│   └── snprintf.c         # Printf compatibility
├── frontend/
│   └── scanimage.c        # Scan CLI tool
└── m4/ility
│   ├── getopt.c           # Command-line parsing
│   └── (other utilities)
├── frontend/
│   └── scanimage.c        # CLI scanning application
└── m4/                    # Autoconf macros
```

## License

This project is licensed under the **GNU General Public License v2.0 or later**.
See the LICENSE file for details.

Some portions are in the public domain (SANE API headers).

## Contributing

This is a minimal focused backend. For contributions, consider submitting improvements to the main SANE project at https://sane-project.gitlab.io/

## References

- [SANE Project](https://sane-project.org/)
- [SANE Standard Documentation](https://sane-project.gitlab.io/standard/)
- [libusb Documentation](http://libusb.info/)
- [Plustek Backend Documentation](https://sane-project.org/sane-backends.html)
