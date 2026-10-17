ARCH = $(shell uname -m)

.PHONY: all install
all: prefix/$(ARCH)/built_libs

prefix/$(ARCH)/built_libs: tasks.sh check-tools.sh Makefile sdl2_image-1-no-webp-anim.patch
	@./tasks.sh dl
	@./tasks.sh all_deps

install: all
	@./tasks.sh install
