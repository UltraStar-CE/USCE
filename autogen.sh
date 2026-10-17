#!/bin/sh
# Run this to set up the build system: configure, makefiles, etc.
set -e

srcdir=`dirname $0`
test -n "$srcdir" && cd "$srcdir"

if command -v python3 >/dev/null 2>&1; then
  python3 tools/generate-version.py
else
  python tools/generate-version.py
fi

echo "Updating build configuration files for USDX, please wait..."

autoreconf --verbose --install --symlink --force
if ! [ -e dists/autogen/config.sub ] ; then
	# autoreconf < 2.70 relied on automake to install aux files
	# but didn't run it in projects that don't use automake macros
	automake --add-missing 2>&1 | grep installing || true
fi
