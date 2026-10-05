# Building mowser: the extension the shell loads, and the helper CEF re-executes.
#
# A MAKEFILE RATHER THAN SCONS, which is what godot-cpp itself uses and what
# every GDExtension tutorial reaches for. The reason is that this build has
# exactly two outputs and three inputs, and all of the actual difficulty is in
# WHICH godot-cpp and WHICH CEF -- questions the Containerfile answers with
# pinned checksums before make is ever called. A SConstruct here would add a
# second build system to a repo that has none, to express four link lines.
#
# Everything is passed in, nothing is discovered. The variables below have no
# sensible default on a developer's machine on purpose: this is built inside the
# image build, against payloads that were checksummed on the way in.
#
#   CEF_ROOT     unpacked CEF binary distribution (include/, Release/, libcef_dll/)
#   GODOT_CPP    built godot-cpp checkout (include/, gen/include/, bin/lib*.a)
#   OUT          where to write libmowser.so and mowser-helper

CEF_ROOT  ?= /build/cef
GODOT_CPP ?= /build/godot-cpp
OUT       ?= /build/out

CXX      ?= g++
# C++20 IS REQUIRED BY CEF, not chosen. CEF 151's base/ headers use concepts
# (`concept IsRefCountedType`), `requires` clauses and the three-way comparison
# operator, so anything below C++20 fails to parse cef_scoped_refptr.h before
# it reaches a line of this project's code. godot-cpp's floor is C++17 and it
# builds fine above it, so C++20 is what both agree on.
#
# -fno-strict-aliasing is Chromium's own build setting and matters here because
# the CEF wrapper punts through pointers in ways GCC's aliasing analysis is
# entitled to miscompile without it.
CXXFLAGS ?= -std=c++20 -O2 -fPIC -fno-strict-aliasing -fvisibility=hidden -Wall

INCLUDES = -I$(CEF_ROOT) -I$(GODOT_CPP)/include -I$(GODOT_CPP)/gen/include \
           -I$(GODOT_CPP)/gdextension

# libcef_dll_wrapper is the C++ convenience layer over CEF's C API. It is
# SHIPPED AS SOURCE, not as a library, because it has to be compiled with the
# same compiler and flags as the code using it -- so the Containerfile builds it
# with cmake before calling this, and it is linked in here.
# FOUND RATHER THAN SPELLED. godot-cpp names its static library after the
# platform, target and architecture it was built for, and that name has changed
# across 4.x releases -- so hard-coding it means a build that fails with "no
# such file" the first time the binding is rebuilt differently. The wildcard
# with an explicit error is the same trade the Containerfile makes everywhere
# else: find it, or say precisely what is missing.
GODOT_CPP_LIB := $(firstword $(wildcard $(GODOT_CPP)/bin/libgodot-cpp*.a))
ifeq ($(GODOT_CPP_LIB),)
$(error no libgodot-cpp*.a under $(GODOT_CPP)/bin -- godot-cpp did not finish building)
endif

CEF_WRAPPER := $(CEF_ROOT)/build/libcef_dll_wrapper/libcef_dll_wrapper.a

LIBS = -L$(CEF_ROOT)/Release -lcef $(CEF_WRAPPER) $(GODOT_CPP_LIB)

# --allow-shlib-undefined, AND IT IS NOT A WARNING BEING SILENCED.
#
# libcef.so carries undefined references to a long tail of system libraries --
# NSS for certificates, ALSA for audio, dbus, cairo, pango, at-spi, Xdamage,
# Xfixes, CUPS -- which it resolves ITSELF at load time. They are Chromium's
# dependencies, not this project's: nothing in mowser/src calls any of them,
# and linking the -devel half of fifteen packages into this build to satisfy
# symbols that belong to somebody else's library would be inventing a
# dependency to describe one that already exists.
#
# WHAT ACTUALLY PROTECTS THE APPLIANCE IS THE RUNTIME ASSERTION. Those
# libraries have to be in the IMAGE or libcef.so fails to load -- so the
# Containerfile greps ldconfig for each one, exactly as it already does for the
# libraries the Godot shell dlopens. That check is on the machine that has to
# have them, which is the honest place for it; this flag only says the linker
# is not the one to enforce it.
LDFLAGS_SHARED = -Wl,--allow-shlib-undefined

EXT_SOURCES = src/mowser_runtime.cpp src/mowser_client.cpp src/mowser_downloads.cpp src/mowser_view.cpp \
              src/register_types.cpp

.PHONY: all clean
all: $(OUT)/libmowser.so $(OUT)/mowser-helper

$(OUT)/libmowser.so: $(EXT_SOURCES) src/mowser.h src/mowser_client.h src/mowser_view.h
	@mkdir -p $(OUT)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -shared -o $@ $(EXT_SOURCES) $(LIBS) \
	    $(LDFLAGS_SHARED) -Wl,-rpath,'$(MOWSER_INSTALL_DIR):$$ORIGIN'

# THE RPATH IS LOAD-BEARING on both outputs, and it is ABSOLUTE rather than
# $ORIGIN. libcef.so is not in the system library path and must not be -- it is
# 256 MB of one application's engine, not a system library, and putting it in
# /usr/lib64 would offer it to everything else on the machine.
#
# $ORIGIN was the first spelling and it is wrong for the EXTENSION, because
# $ORIGIN is wherever Godot's exporter decided to stage its copy: the exporter
# copies a GDExtension library next to the exported binary (it will not export
# at all if it cannot), so libmowser.so runs from the shell's directory while
# the engine sits in the payload directory on purpose. An absolute rpath is the
# only one that is true in both places.
#
# The helper keeps $ORIGIN as well: it is installed INTO the payload directory
# and never moves, and a binary that can find its own engine without depending
# on an absolute path is the more robust of the two.
MOWSER_INSTALL_DIR ?= /usr/lib/marwanos/mowser
$(OUT)/mowser-helper: src/subprocess.cpp
	@mkdir -p $(OUT)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $@ src/subprocess.cpp \
	    -L$(CEF_ROOT)/Release -lcef $(CEF_WRAPPER) \
	    $(LDFLAGS_SHARED) -Wl,-rpath,'$$ORIGIN'

clean:
	rm -f $(OUT)/libmowser.so $(OUT)/mowser-helper
