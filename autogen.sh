#!/bin/bash
# Generate build configuration from autoconf/automake templates

set -e

echo "Generating build configuration files..."

# Check for required tools
for prog in aclocal autoconf automake libtool; do
    if ! command -v $prog &> /dev/null; then
        echo "Error: $prog not found. Please install autotools."
        echo "  Ubuntu/Debian: sudo apt-get install autoconf automake libtool"
        echo "  Fedora/RHEL:   sudo dnf install autoconf automake libtool"
        echo "  macOS:         brew install autoconf automake libtool"
        exit 1
    fi
done

# Create m4 directory if needed
mkdir -p m4

# Run autotools in order
echo "Running libtoolize..."
libtoolize --force --copy

echo "Running aclocal..."
aclocal -I m4

echo "Running autoconf..."
autoconf

echo "Running automake..."
automake --add-missing --copy

echo ""
echo "Build configuration generated successfully!"
echo "Next steps:"
echo "  ./configure [OPTIONS]"
echo "  make"
echo "  sudo make install"
echo ""
echo "For help with configure options:"
echo "  ./configure --help"
