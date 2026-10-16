
ARCH = $(shell uname -m)
VERSION = $(shell cat ../../VERSION)
REV = $(shell git rev-parse --short HEAD)
SHELL := /bin/bash
EXE = usce

.PHONY: default build-deps build run compress bundle upload clean distclean

default: build

build-deps: prefix/$(ARCH)/built_libs
prefix/$(ARCH)/built_libs:
	@./dl.sh
	@echo
	@bash -eo pipefail -c './tasks.sh all_deps | tee build-deps.log'
	@sed -r -i "s/\x1B(\[[0-9;]*[JKmsu]|\(B)//g" "build-deps.log" # remove color codes
	@echo

build: build/$(ARCH)/usr/bin/usce
build/$(ARCH)/usr/bin/usce build/$(ARCH)/usr/bin/VERSION: prefix/$(ARCH)/built_libs
	@bash -eo pipefail -c './build.sh | tee build.log'
	@sed -r -i "s/\x1B(\[[0-9;]*[JKmsu]|\(B)//g" "build.log" # remove color codes

# run with Docker:
# ./dockerenv.sh make bundle # x86_64
# linux32 ./dockerenv.sh make bundle # i386/i686
bundle: clean compress
	@echo Complete!

run: build/$(ARCH)/usr/bin/usce
	@build/$(ARCH)/launch.sh

compress: USCE-$(ARCH).AppImage
USCE-$(ARCH).AppImage: build/$(ARCH)/usr/bin/usce build/$(ARCH)/usr/bin/VERSION
	rm -f "./USCE-$(ARCH).AppImage"
	echo "INFO: Any warnings about zsync and binary delta updates can be ignored, since we don't use them."
	PATH="prefix/$(ARCH)/bin:$$PATH" prefix/$(ARCH)/bin/appimagetool --comp xz build/$(ARCH) $@

upload: USCE-$(ARCH).AppImage
	curl --upload-file './USCE-$(ARCH).AppImage' "https://transfer.sh/USCE-$(ARCH).AppImage" && echo

clean:
	rm -rf build/$(ARCH) prefix/$(ARCH) USCE-$(ARCH).tar.xz

distclean: clean
	rm -rf deps build prefix USCE-*.tar.xz
