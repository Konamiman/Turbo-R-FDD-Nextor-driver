# Makefile for the MSX Turbo-R FDD driver for Nextor 3.
#
# This driver can be built in two flavors:
#
#   * ROM driver (default): combined with a Nextor kernel base file to
#     produce a full Nextor ROM image, ready to be flashed to an MSX
#     ROM cartridge using an ASCII16 mapper. Built by `make` or
#     `make rom`.
#
#   * RAM driver: standalone .drv file that loads into a mapped RAM
#     segment at runtime via CALL IDRIVER or the DRVROP.COM tool.
#     Built by `make ram`. Doesn't need NEXTOR_BASE.
#
# Both flavors come out under `bin/`:
#
#   * bin/Nextor-<ver>.TurboRFDD.ROM       - ROM driver
#   * bin/turbofdd.drv                     - RAM driver
#
# Intermediate build artifacts go to `tmp/`.
#
# <ver> and any variant suffix (e.g. ".NO_UNDOC.SHIFT_INV") are taken
# from the NEXTOR_BASE filename, which must follow the convention
# Nextor-<ver>.base[<suffix>].dat as produced by the Nextor kernel
# Makefile. If NEXTOR_BASE has a non-standard filename, the ROM is
# named after that filename's stem instead.
#
# The default slot for the Turbo-R FDC hardware is 3-2 (slot byte 8Bh
# = slot 3 + 4*subslot 2 + 128). Override at build time for the ROM
# variant by setting FDC_SLOT on the make command line (e.g. FDC_SLOT=8Bh);
# for the RAM variant the slot is configured at load time via CALL
# IDRIVER / DRVROP.COM, not at assembly time.


### Configurable variables ###################################################

# Targets that don't need NEXTOR_BASE.
_NO_BASE_GOALS := setup clean clean-bin distclean ram

# Compute whether NEXTOR_BASE is required for this make invocation.
ifeq ($(MAKECMDGOALS),)
_NEEDS_BASE := 1
else
_NEEDS_BASE := $(if $(filter-out $(_NO_BASE_GOALS),$(MAKECMDGOALS)),1,)
endif

ifeq ($(_NEEDS_BASE),1)
ifeq ($(strip $(NEXTOR_BASE)),)
$(error NEXTOR_BASE is not set. Point it at a Nextor kernel base .dat file (or use `make ram` for the RAM-only driver, which does not need it))
endif
ifeq ($(wildcard $(NEXTOR_BASE)),)
$(error NEXTOR_BASE points at '$(NEXTOR_BASE)' which does not exist)
endif
endif

# NEXTOR_SDK: path to the Nextor SDK directory (the one containing 'asm/').
# Defaults to the bundled git submodule.
NEXTOR_SDK ?= external/Nextor/sdk

# Tool overrides. Default to invoking the executables from PATH.
N80      ?= N80
MKNEXROM ?= mknexrom

# NO_UNDOC_CPU_INSTRUCTIONS: when set (e.g. =1) the driver is assembled
# with undocumented Z80 opcodes (those operating on ixh/ixl/iyh/iyl)
# replaced with documented equivalents, for compatibility with
# Z180-based MSX machines. For the ROM build, set this whenever
# NEXTOR_BASE points at a .NO_UNDOC. variant; the driver developer is
# responsible for keeping the two consistent.
NO_UNDOC_CPU_INSTRUCTIONS ?=

# FDC_SLOT (ROM build only): override the FDC hardware slot at
# assembly time. Default 8Bh = slot 3-2 (the standard for the
# FS-A1GT/FS-A1ST). Value format: slot + 4*subslot + 128 (e.g. 8Bh
# for 3-2, 8Fh for 3-3). For the RAM build, the slot is set at load
# time instead.
FDC_SLOT ?=


### Output directories #######################################################

BIN := bin
TMP := tmp


### Filename derivation ######################################################

# Decompose NEXTOR_BASE's basename: 'Nextor-<ver>.base[.<suffix>].dat'.
_BASE_NAME    := $(notdir $(NEXTOR_BASE))
_BASE_STEM    := $(_BASE_NAME:.dat=)
_BASE_VERSION := $(firstword $(subst .base, ,$(_BASE_STEM)))
_BASE_SUFFIX  := $(patsubst $(_BASE_VERSION).base%,%,$(_BASE_STEM))

# If the filename didn't parse (no '.base' found), fall back to using
# the whole stem as the prefix and no variant suffix.
ifeq ($(_BASE_SUFFIX),$(_BASE_STEM))
_DRIVER_PREFIX := $(_BASE_STEM)
_VARIANT       :=
else
_DRIVER_PREFIX := $(_BASE_VERSION).TurboRFDD
_VARIANT       := $(_BASE_SUFFIX)
endif

ROM       := $(BIN)/$(_DRIVER_PREFIX)$(_VARIANT).ROM
_RAM_SUFFIX := $(if $(NO_UNDOC_CPU_INSTRUCTIONS),.NO_UNDOC)
RAM_DRV   := $(BIN)/turbofdd$(_RAM_SUFFIX).drv


### Assembly flags ###########################################################

N80_FLAGS := --no-string-escapes --no-show-banner --verbosity 0 \
             --build-type abs --output-file-extension bin \
             --output-file-case lower \
             --include-directory $(NEXTOR_SDK)

_DEFINES_NO_UNDOC := $(if $(NO_UNDOC_CPU_INSTRUCTIONS),--define-symbols NO_UNDOC_CPU_INSTRUCTIONS)
_DEFINES_FDC_SLOT := $(if $(FDC_SLOT),--define-symbols FDC_SLOT=$(FDC_SLOT))


### Top-level targets ########################################################

.PHONY: all rom ram clean clean-bin distclean setup
all: rom

rom: $(ROM)
ram: $(RAM_DRV)

# Order-only prereqs for outputs that live in the build directories.
$(BIN) $(TMP):
	@mkdir -p $@


### ROM build ################################################################

# Driver binary for the ROM build (FDC_SLOT can be overridden at assembly time).
$(TMP)/driver.bin: driver.asm | $(TMP)
	$(N80) driver.asm $(TMP)/ $(N80_FLAGS) $(_DEFINES_NO_UNDOC) $(_DEFINES_FDC_SLOT)

# Bank-switching routine for the ASCII16 mapper.
$(TMP)/chgbnk.bin: chgbnk.asm | $(TMP)
	$(N80) chgbnk.asm $(TMP)/ $(N80_FLAGS) $(_DEFINES_NO_UNDOC)

# The Turbo-R FDD driver assembles starting at 4100h, so a 256-byte
# zero block is prepended to the driver binary before mknexrom
# combines it with the kernel base.
$(TMP)/256.bytes: | $(TMP)
	dd if=/dev/zero of=$@ bs=1 count=256

$(ROM): $(TMP)/driver.bin $(TMP)/chgbnk.bin $(TMP)/256.bytes | $(BIN)
	cat $(TMP)/256.bytes $(TMP)/driver.bin > $(TMP)/_driver.padded.bin
	$(MKNEXROM) $(NEXTOR_BASE) $@ /d:$(TMP)/_driver.padded.bin /m:$(TMP)/chgbnk.bin
	rm -f $(TMP)/_driver.padded.bin


### RAM driver build #########################################################

# `--define-symbols RAM_DRIVER` selects the RAM build path inside
# driver.asm. The output goes directly to bin/turbofdd[.NO_UNDOC].drv.
$(RAM_DRV): driver.asm | $(BIN)
	$(N80) driver.asm $@ $(N80_FLAGS) $(_DEFINES_NO_UNDOC) --define-symbols RAM_DRIVER


### Housekeeping #############################################################

# `make clean` keeps shippable outputs in bin/, only wipes intermediates.
clean:
	rm -rf $(TMP)

# `make clean-bin` removes the shippable outputs.
clean-bin:
	rm -rf $(BIN)

# `make distclean` removes both.
distclean: clean clean-bin


### One-time setup ###########################################################

# `make setup` initializes the Nextor SDK submodule as a blobless
# partial clone with sparse-checkout for the `sdk/` directory only, so
# that the full Nextor repository is never fetched. Run this once,
# right after cloning this repo, instead of using `git clone
# --recurse-submodules`.
setup:
	@echo "Setting up the Nextor SDK submodule (blobless + sparse-checkout for sdk/ only)..."
	git submodule init external/Nextor
	git submodule update --init --filter=blob:none external/Nextor
	git -C external/Nextor sparse-checkout init --cone
	git -C external/Nextor sparse-checkout set sdk
	git -C external/Nextor checkout
	@echo "Done. Set NEXTOR_BASE and run 'make' to build the ROM, or run 'make ram' for the RAM driver."
