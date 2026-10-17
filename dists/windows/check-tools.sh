#!/usr/bin/env bash

# Check before downloading sources or clearing a previous dependency build.
missing_tools=()
missing_packages=()
for requirement in \
	/usr/bin/patch:patch \
	cmake:mingw-w64-ucrt-x86_64-cmake \
	gcc:mingw-w64-ucrt-x86_64-gcc \
	g++:mingw-w64-ucrt-x86_64-gcc \
	make:make \
	meson:mingw-w64-ucrt-x86_64-meson \
	ninja:mingw-w64-ucrt-x86_64-ninja \
	nasm:mingw-w64-ucrt-x86_64-nasm \
	pkg-config:mingw-w64-ucrt-x86_64-pkgconf \
	curl:curl \
	unzip:unzip; do
	tool=${requirement%%:*}
	package=${requirement#*:}
	if ! command -v "$tool" >/dev/null 2>&1; then
		missing_tools+=("$tool")
		missing_packages+=("$package")
	fi
done

if ((${#missing_tools[@]})); then
	printf 'Missing Windows dependency build tools:\n' >&2
	printf '  %s\n' "${missing_tools[@]}" >&2
	printf 'Install them from an MSYS2 UCRT64 shell:\n  pacman -S --needed' >&2
	printf ' %s' "${missing_packages[@]}" >&2
	printf '\nUse MSYS2 /usr/bin/patch; FPC\047s bundled patch is not supported.\n' >&2
	exit 1
fi

# Finding the Meson launcher alone does not prove its Python module is usable.
if ! meson --version >/dev/null 2>&1; then
	printf 'Meson cannot run. Check the MSYS2 Meson and Python installation.\n' >&2
	printf 'See the Windows prerequisites in COMPILING.md.\n' >&2
	exit 1
fi
