# macOS build of the AppKit backend object simple_gui.ecf expects. Usage: make -C Clib
# (Cairo's header from Homebrew; Cocoa from the system.)
CC ?= cc
CAIRO_CFLAGS := $(shell pkg-config --cflags cairo 2>/dev/null || echo -I/opt/homebrew/include/cairo)
CFLAGS ?= -O2 -g
CFLAGS += -fobjc-arc -Wall $(CAIRO_CFLAGS)

simple_gui_appkit.o: simple_gui_appkit.m simple_gui_appkit.h
	$(CC) $(CFLAGS) -c simple_gui_appkit.m -o simple_gui_appkit.o

clean:
	rm -f simple_gui_appkit.o

.PHONY: clean
