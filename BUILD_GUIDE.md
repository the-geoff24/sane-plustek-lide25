# Simple Build & Installation Guide - Scanning Only

Build and install in under 10 minutes. One feature: scan documents and save as images.

## Quick Start (All Platforms)

```bash
cd sane-plustek-lide25
./autogen.sh
./configure --prefix=$HOME/.local
make -j4
make install
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH
export PATH=$HOME/.local/bin:$PATH
scanimage -A
```

## Prerequisites

### Ubuntu/Debian
```bash
sudo apt-get install build-essential autoconf automake libtool libusb-1.0-0-dev
```

### Fedora/RHEL
```bash
sudo dnf install gcc autoconf automake libtool libusb1-devel
```

### macOS
```bash
brew install autoconf automake libtool libusb
```

### Windows (MSYS2)
```bash
pacman -S base-devel mingw-w64-x86_64-libusb
```

## Build Steps

### 1. Generate Build System
```bash
./autogen.sh
```

### 2. Configure
```bash
# Local (recommended - no root needed)
./configure --prefix=$HOME/.local

# Or system-wide
./configure --prefix=/usr
```

### 3. Build
```bash
make -j4
```

### 4. Install
```bash
make install
```

### 5. Setup Environment
```bash
# Local installation
export PATH=$HOME/.local/bin:$PATH
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH

# System installation (already in PATH)
sudo ldconfig
```

## Usage

```bash
# List scanners
scanimage -A

# Scan to file
scanimage -d plustek > scan.pnm

# Scan in greyscale (faster)
scanimage -d plustek --mode Gray > scan.pnm

# Different resolution
scanimage -d plustek --resolution 300 > scan-hq.pnm
```

## Installation on Other Devices

### Transfer to Linux/Mac Device
```bash
# Build and stage
make DESTDIR=./staging install
tar czf sane.tar.gz -C staging .

# Transfer
scp sane.tar.gz user@device:/tmp/

# On device
cd / && sudo tar xzf /tmp/sane.tar.gz
sudo ldconfig
```

### Transfer to Raspberry Pi (ARM)
```bash
# On build machine with ARM cross-compiler
./configure --host=arm-linux-gnueabihf CC=arm-linux-gnueabihf-gcc
make
make DESTDIR=./pi-staging install
tar czf sane-pi.tar.gz -C pi-staging .

# Transfer and install on Pi
scp sane-pi.tar.gz pi@raspberrypi:/tmp/
ssh pi@raspberrypi "cd / && sudo tar xzf /tmp/sane-pi.tar.gz && sudo ldconfig"
```

### Docker (One Command)
```bash
docker build -t sane-scan .
docker run --device /dev/bus/usb --rm sane-scan scanimage -A
```

## Troubleshooting

### Scanner Not Found
```bash
# Check USB
lsusb | grep Canon

# Check with root (permission issue)
sudo scanimage -A

# Fix permissions (Linux)
sudo tee /etc/udev/rules.d/60-sane.rules > /dev/null << 'EOF'
SUBSYSTEMS=="usb", ATTRS{idVendor}=="04a9", ATTRS{idProduct}=="2220", MODE="0666"
EOF
sudo udevadm control --reload-rules
```

### Library Not Found
```bash
# Set library path
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH

# Verify installed
ls -la ~/.local/lib/libsane*
```

### Build Fails
```bash
# Clean and try again
make distclean
./autogen.sh
./configure --prefix=$HOME/.local
make clean
make -j4
```

## Uninstall
```bash
cd sane-plustek-lide25
make uninstall
```

---

That's it! Simple, focused, scanning only.

### Ubuntu/Debian (LTS and modern versions)

#### Step 1: Install Dependencies

```bash
# Update package lists
sudo apt-get update

# Install build tools and libraries
sudo apt-get install -y \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libusb-1.0-0-dev
```

#### Step 2: Build and Install

##### Option A: Local Installation (Recommended for Development)

```bash
cd sane-plustek-lide25
./autogen.sh
./configure --prefix=$HOME/.local
make -j$(nproc)
make install

# Add to shell configuration (~/.bashrc or ~/.zshrc)
cat >> ~/.bashrc << 'EOF'
export PATH=$HOME/.local/bin:$PATH
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=$HOME/.local/lib/pkgconfig:$PKG_CONFIG_PATH
EOF

source ~/.bashrc
```

##### Option B: System-Wide Installation

```bash
cd sane-plustek-lide25
./autogen.sh
./configure --prefix=/usr
make -j$(nproc)
sudo make install
sudo ldconfig
```

#### Step 3: Setup Device Permissions

For non-root USB access:

```bash
# Create udev rule for scanner
sudo tee /etc/udev/rules.d/60-sane-plustek.rules > /dev/null << 'EOF'
# Canon CanoScan LiDE 25
SUBSYSTEMS=="usb", ATTRS{idVendor}=="04a9", ATTRS{idProduct}=="2220", \
  MODE="0666", GROUP="scanner"
EOF

# Add current user to scanner group
sudo usermod -a -G scanner $USER

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Log out and back in for group membership to take effect
```

#### Step 4: Verify Installation

```bash
# Check backend is available
scanimage -A

# List connected scanners
lsusb | grep Canon

# Test scanning
scanimage -d plustek:libusb:001:002 --format=pnm > test.pnm
```

### Fedora/RHEL/CentOS 8+

#### Step 1: Install Dependencies

```bash
sudo dnf groupinstall "Development Tools"
sudo dnf install \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libusb1-devel
```

#### Step 2: Build and Install

```bash
cd sane-plustek-lide25
./autogen.sh
./configure --prefix=/usr
make -j$(nproc)
sudo make install
sudo ldconfig
```

#### Step 3: Setup Permissions and Verify

```bash
# Create udev rule
sudo tee /etc/udev/rules.d.d/60-sane-plustek.rules > /dev/null << 'EOF'
SUBSYSTEMS=="usb", ATTRS{idVendor}=="04a9", ATTRS{idProduct}=="2220", \
  MODE="0666", GROUP="scanner"
EOF

# Add user to scanner group
sudo usermod -a -G scanner $(whoami)

# Verify
scanimage -A
```

---

## macOS Installation

### Using Homebrew

#### Step 1: Install Homebrew (if not installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### Step 2: Install Dependencies

```bash
brew install autoconf automake libtool libusb pkg-config
```

#### Step 3: Build and Install

```bash
cd sane-plustek-lide25
./autogen.sh

# Local installation
./configure --prefix=$HOME/.local
make -j$(sysctl -n hw.ncpu)
make install

# Or system-wide (requires sudo for /usr/local)
./configure --prefix=/usr/local
make -j$(sysctl -n hw.ncpu)
sudo make install
```

#### Step 4: Setup Environment

```bash
# Add to ~/.bash_profile or ~/.zsh_profile
export PATH=$HOME/.local/bin:/usr/local/bin:$PATH
export DYLD_LIBRARY_PATH=$HOME/.local/lib:/usr/local/lib:$DYLD_LIBRARY_PATH
export PKG_CONFIG_PATH=$HOME/.local/lib/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
```

#### Step 5: Test

```bash
scanimage -A
```

---

## Windows Installation

### Using MSYS2

#### Step 1: Install MSYS2

Download and install from https://www.msys2.org/

#### Step 2: Install Dependencies

Open MSYS2 MinGW 64-bit terminal:

```bash
# Update package database
pacman -Syu

# Install build tools
pacman -S base-devel \
    mingw-w64-x86_64-toolchain \
    mingw-w64-x86_64-libusb \
    mingw-w64-x86_64-pkg-config \
    autoconf automake libtool
```

#### Step 3: Build

```bash
cd /c/Users/YourUsername/Downloads/sane-plustek-lide25

./autogen.sh

# Configure for Windows installation
./configure --prefix=/mingw64
make -j$(nproc)
make install
```

#### Step 4: Add to PATH

The MSYS2 environment automatically adds `/mingw64/bin` to PATH.

#### Step 5: Test

```bash
scanimage -A
```

---

## Remote/Cross-Platform Installation

### Method 1: Cross-Compilation for ARM (e.g., Raspberry Pi)

#### On Build Machine (x86_64 host)

```bash
# Install ARM cross-compiler toolchain
sudo apt-get install arm-linux-gnueabihf-gcc arm-linux-gnueabihf-g++

# Install ARM target libraries
sudo apt-get install libusb-1.0-0-dev:armhf

cd sane-plustek-lide25

./autogen.sh

# Configure for ARM target
./configure --host=arm-linux-gnueabihf \
            --prefix=/usr/local \
            CC=arm-linux-gnueabihf-gcc \
            CXX=arm-linux-gnueabihf-g++ \
            CFLAGS="-march=armv7-a -O2"

make -j4

# Prepare staging directory
make DESTDIR=./arm-staging install

# Create archive for transfer
tar czf sane-plustek-lide25-armhf.tar.gz -C arm-staging .
```

#### On Target Device (Raspberry Pi)

```bash
# Transfer and extract
cd /
sudo tar xzf ~/sane-plustek-lide25-armhf.tar.gz

# Update library cache
sudo ldconfig

# Verify
scanimage -A
```

### Method 2: SSH Remote Installation

#### Build and Transfer Script

```bash
#!/bin/bash
set -e

TARGET_HOST="user@raspberrypi.local"
TARGET_HOME="/home/user"

cd sane-plustek-lide25

# Clean previous build
make distclean 2>/dev/null || true

# Build for current system first (if cross-compiling, skip this)
./autogen.sh
./configure --prefix=/opt/sane
make clean
make -j4

# Create installation package
make DESTDIR=./install-pkg install
tar czf sane-plustek-package.tar.gz -C install-pkg .

# Transfer to target
scp sane-plustek-package.tar.gz $TARGET_HOST:/tmp/

# Extract on target
ssh $TARGET_HOST "cd / && sudo tar xzf /tmp/sane-plustek-package.tar.gz && sudo ldconfig"

# Verify
ssh $TARGET_HOST "scanimage -A"

echo "Installation complete!"
```

Run it:
```bash
chmod +x install-remote.sh
./install-remote.sh
```

### Method 3: Package Creation (for Distribution)

#### Create Debian Package

```bash
cd sane-plustek-lide25

./autogen.sh
./configure --prefix=/usr

# Build and create package metadata
mkdir -p debian/DEBIAN
cat > debian/DEBIAN/control << 'EOF'
Package: sane-plustek-lide25
Version: 1.0.0
Architecture: amd64
Maintainer: Your Name <email@example.com>
Depends: libusb-1.0-0 (>= 1.0.0)
Description: SANE backend for Canon CanoScan LiDE 25
 Minimal SANE (Scanner Access Now Easy) backend
 supporting only the Canon CanoScan LiDE 25.
EOF

# Build package
make DESTDIR=./debian install
dpkg-deb --build debian sane-plustek-lide25-1.0.0.deb

# Transfer to target
scp sane-plustek-lide25-1.0.0.deb user@device:/tmp/
ssh user@device "sudo dpkg -i /tmp/sane-plustek-lide25-1.0.0.deb"
```

#### Create RPM Package

```bash
cd sane-plustek-lide25

# Build for RPM
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

./autogen.sh
./configure --prefix=/usr
make

# Create package
cd ~/rpmbuild/SPECS
cat > sane-plustek-lide25.spec << 'EOF'
Name:           sane-plustek-lide25
Version:        1.0.0
Release:        1%{?dist}
Summary:        SANE backend for Canon CanoScan LiDE 25
License:        GPLv2+
URL:            https://example.com

Requires:       libusb1 >= 1.0.0

%description
Minimal SANE (Scanner Access Now Easy) backend supporting only the Canon CanoScan LiDE 25.

%install
rm -rf %{buildroot}
%{make_install}

%files
%doc
%{_bindir}/*
%{_libdir}/*
%{_sysconfdir}/sane.d/*

%changelog
* $(date '+%a %b %d %Y') User <user@example.com> - 1.0.0-1
- Initial release
EOF

rpmbuild -bb sane-plustek-lide25.spec
```

---

## Docker Deployment

### Dockerfile for Isolated Environment

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    build-essential \
    autoconf automake libtool \
    libusb-1.0-0 libusb-1.0-0-dev \
    pkg-config

WORKDIR /build
COPY . .

RUN ./autogen.sh && \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    ldconfig

WORKDIR /root
ENTRYPOINT ["/usr/local/bin/scanimage"]
CMD ["-A"]
```

### Build and Use

```bash
# Build Docker image
docker build -t sane-plustek:latest .

# Run scanner discovery
docker run --device /dev/bus/usb sane-plustek:latest -A

# Scan image
docker run --device /dev/bus/usb \
    -v $(pwd):/output \
    sane-plustek:latest \
    -d plustek -o /output/scan.pnm

# Interactive shell in container
docker run -it --device /dev/bus/usb sane-plustek:latest /bin/bash
```

### Docker Compose for Service

```yaml
version: '3.8'

services:
  sane-backend:
    build:
      context: .
      dockerfile: Dockerfile
    devices:
      - /dev/bus/usb
    volumes:
      - ./scans:/output
    environment:
      - SANE_CONFIG_DIR=/etc/sane.d
    ports:
      - "6566:6566"  # saned network port
```

Run:
```bash
docker-compose up
```

---

## Troubleshooting

### Scanner Not Detected

**Issue**: `scanimage -A` returns no devices

**Solutions**:

1. Check USB connection:
```bash
lsusb | grep Canon
# Should show something like:
# Bus 001 Device 003: ID 04a9:2220 Canon, Inc.
```

2. Check USB permissions:
```bash
# Linux: verify udev rules were applied
ls -la /etc/udev/rules.d/60-sane-plustek.rules

# Check device permissions
lsusb -v -d 04a9:2220 | grep -i "Bus\|Device\|idVendor\|idProduct"

# Try as root to verify driver works
sudo scanimage -A
```

3. Verify library is found:
```bash
ldd $(which scanimage) | grep sane
# or
ldd ~/.local/bin/scanimage | grep sane
```

### "libsane.so: cannot open shared object file"

**Issue**: Cannot load SANE library

**Solutions**:

```bash
# Ensure library path is set
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH

# Or for system installation
sudo ldconfig

# Verify library exists
find /usr/local -name "libsane*" 2>/dev/null
find $HOME/.local -name "libsane*" 2>/dev/null

# Check library dependencies
ldd /usr/local/lib/libsane.so | grep "not found"
```

### "permission denied" when opening scanner

**Solutions**:

```bash
# Try with sudo (temporary fix)
sudo scanimage -A

# Make permanent: set proper udev rules
sudo tee /etc/udev/rules.d/60-sane-plustek.rules > /dev/null << 'EOF'
SUBSYSTEMS=="usb", ATTRS{idVendor}=="04a9", ATTRS{idProduct}=="2220", \
  MODE="0666", GROUP="scanner"
EOF

# Reload and reapply rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Add user to scanner group
sudo usermod -a -G scanner $USER

# Log out and back in
```

### Build Failures

**Missing autotools**:
```bash
./autogen.sh
# Error: command not found: libtoolize

# Ubuntu/Debian
sudo apt-get install libtool autoconf automake

# Fedora/RHEL
sudo dnf install libtool autoconf automake
```

**Missing libusb development files**:
```bash
./configure
# Error: Package libusb-1.0 was not found

# Ubuntu/Debian
sudo apt-get install libusb-1.0-0-dev

# Fedora/RHEL
sudo dnf install libusb1-devel
```

---

## Uninstallation

### If build directory still exists:

```bash
cd sane-plustek-lide25
make uninstall
```

### Manual removal:

```bash
# For --prefix=/usr/local
rm /usr/local/bin/scanimage
rm /usr/local/lib/libsane*
rm /usr/local/lib/sane/libsane-plustek*
rm /usr/local/etc/sane.d/plustek.conf
sudo ldconfig

# For --prefix=/usr
sudo rm /usr/bin/scanimage
sudo rm /usr/lib/libsane*
sudo rm /usr/lib/sane/libsane-plustek*
sudo rm /etc/sane.d/plustek.conf
sudo ldconfig

# For --prefix=$HOME/.local
rm $HOME/.local/bin/scanimage
rm $HOME/.local/lib/libsane*
rm $HOME/.local/lib/sane/libsane-plustek*
rm $HOME/.local/etc/sane.d/plustek.conf
```

---

## Environment Variables Reference

| Variable | Purpose | Example |
|----------|---------|---------|
| `LD_LIBRARY_PATH` | Shared library search path | `$HOME/.local/lib:/usr/local/lib` |
| `PATH` | Executable search path | `$HOME/.local/bin:/usr/local/bin` |
| `PKG_CONFIG_PATH` | pkg-config search path | `$HOME/.local/lib/pkgconfig` |
| `SANE_CONFIG_DIR` | SANE config directory | `/etc/sane.d` |
| `SANE_DEBUG_*` | Enable debug output | `SANE_DEBUG_PLUSTEK=3` |

---

## Additional Resources

- [SANE Project](https://sane-project.org/)
- [libusb Documentation](https://libusb.info/)
- [Autoconf Manual](https://www.gnu.org/software/autoconf/manual/)
- [Automake Manual](https://www.gnu.org/software/automake/manual/)
