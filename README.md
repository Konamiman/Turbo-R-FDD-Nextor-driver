# MSX Turbo-R FDD driver for Nextor

This repository contains a driver for the floppy disk controller built into the MSX Turbo-R computers (Panasonic FS-A1GT and FS-A1ST), for [Nextor](https://github.com/Konamiman/Nextor) v3.0 or newer. It drives the TC8566AF FDC and uses the S1990 system controller hardware for disk-change detection.

The driver can be built in two flavors:

| Output                                | Notes                                                                                  |
| ------------------------------------- | -------------------------------------------------------------------------------------- |
| `Nextor-<ver>.TurboRFDD.ROM`          | **ROM driver** (default `make` target). Combined with a Nextor kernel base file to produce a ROM image, ready to be flashed to an ASCII16-mapper cartridge. |
| `turbofdd.drv`                        | **RAM driver** (via `make ram`). Standalone `.drv` file that loads into a mapped RAM segment at runtime via CALL IDRIVER or DRVROP.COM.                       |

For the ROM driver, `<ver>` and any kernel-base variant suffix (e.g. `.NO_UNDOC.SHIFT_INV`) are picked up automatically from the `NEXTOR_BASE` filename; see [Building](#building) below.

## Hardware slot configuration

The default slot for the Turbo-R FDC is 3-2 (slot byte `8Bh` = slot 3 + 4×subslot 2 + 128). This matches the FS-A1GT/FS-A1ST built-in hardware. Override as follows:

- **ROM build**: pass `FDC_SLOT=<value>` on the `make` command line (slot + 4·subslot + 128 in hex with a trailing `h`, e.g. `8Bh` for 3-2, `8Fh` for 3-3). The value is baked into the assembled driver.
- **RAM build**: the slot is configured at load time by passing it as initialization data to CALL IDRIVER or to DRVROP.COM (write `1` to `4000h` and the slot byte to `4001h` of the driver segment before initialization). Nothing to do at build time.

## Repository contents

| File              | Purpose                                                                                  |
| ----------------- | ---------------------------------------------------------------------------------------- |
| `driver.asm`      | The Turbo-R FDD driver. Conditionally assembled as a ROM driver or a RAM driver depending on the `RAM_DRIVER` build-time symbol. |
| `chgbnk.asm`      | Bank-switching routine for the ASCII16 mapper used by the cartridge.                     |
| `Makefile`        | Build rules; see below.                                                                  |
| `external/Nextor` | Git submodule pointing at the Nextor repo, sparse-checkout to the `sdk/` directory only. |

## Development environment

You need:

- [**Nestor80**](https://github.com/Konamiman/Nestor80) (`N80`) on your `PATH`, or pointed at via the `N80` make variable.
- **`mknexrom`** on your `PATH`, or pointed at via the `MKNEXROM` make variable. Only needed for the ROM build. The source lives in the Nextor repository under `buildtools/sources/mknexrom.c`.
- A POSIX **`make`** and `dd` / `cat` (for the ROM build).

## Cloning the repository

This repository uses a git submodule to pull in the Nextor SDK; clone with `--recurse-submodules` and then configure the submodule for a sparse checkout of the `sdk/` directory (the only thing this driver consumes from Nextor):

```sh
git clone --recurse-submodules https://github.com/Konamiman/TurboR-FDD-Nextor-driver.git [<target-dir>]
cd <target-dir>/external/Nextor
git sparse-checkout init --cone
git sparse-checkout set sdk
cd ../..
```

If you already cloned without `--recurse-submodules`, run `git submodule update --init` first.

If you have a local clone of Nextor and want the submodule to point at it (e.g. while developing the SDK locally), override the URL once:

```sh
git config submodule.external/Nextor.url /path/to/your/local/Nextor
git submodule sync
git submodule update --init
```

### If you'd rather not fetch the full Nextor repository

The sequence above clones the entire Nextor repository before the sparse-checkout limits the working tree. If you'd rather only fetch the SDK files (typically <100 KB instead of tens of MB), clone the driver *without* `--recurse-submodules` and then set up the submodule as a blobless partial clone with sparse-checkout from the start:

```sh
git clone https://github.com/Konamiman/TurboR-FDD-Nextor-driver.git [<target-dir>]
cd <target-dir>
git submodule init external/Nextor
git submodule update --init --filter=blob:none external/Nextor
git -C external/Nextor sparse-checkout init --cone
git -C external/Nextor sparse-checkout set sdk
git -C external/Nextor checkout
```

...or, equivalently, just `make setup`:

```sh
git clone https://github.com/Konamiman/TurboR-FDD-Nextor-driver.git [<target-dir>]
cd <target-dir>
make setup
```

## Building

### ROM driver (default)

The build needs a Nextor kernel base file, supplied via `NEXTOR_BASE`:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.dat make
```

That produces the ROM in the `bin/` directory.

For an undoc-instruction-free build (compatible with Z180-based MSX machines), pair an undoc-free kernel base with the matching driver-side flag:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.NO_UNDOC.dat \
NO_UNDOC_CPU_INSTRUCTIONS=1 \
make
```

To target a non-default FDC slot, add `FDC_SLOT=<value>`:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.dat FDC_SLOT=8Fh make    # slot 3-3
```

The Nextor base filename's version and variant suffix (e.g. `.NO_UNDOC.SHIFT_INV`) are mirrored in the output ROM filename. **You are responsible for keeping `NO_UNDOC_CPU_INSTRUCTIONS` consistent with the base file's variant**: the Makefile does not infer it for you.

### RAM driver

The RAM driver doesn't need `NEXTOR_BASE` (it isn't combined with a kernel base):

```sh
make ram
```

That produces `bin/turbofdd.drv`. Combine with `NO_UNDOC_CPU_INSTRUCTIONS=1` for an undoc-free build (output goes to `bin/turbofdd.NO_UNDOC.drv`). The hardware slot is *not* baked in at build time; configure it at load time via CALL IDRIVER or DRVROP.COM (see [Hardware slot configuration](#hardware-slot-configuration) above).

### Building without `make`

The Makefile is the recommended way, but each flavor is produced by a small handful of tool invocations.

**ROM driver:**

```sh
mkdir -p tmp

# Assemble the driver  ->  tmp/driver.bin
N80 driver.asm tmp/ \
    --no-string-escapes --build-type abs --output-file-extension bin \
    --include-directory external/Nextor/sdk

# Assemble the bank-switching routine  ->  tmp/chgbnk.bin
N80 chgbnk.asm tmp/ \
    --no-string-escapes --build-type abs --output-file-extension bin \
    --include-directory external/Nextor/sdk

# The driver assembles starting at 4100h, so prepend 256 zero bytes
# before handing it to mknexrom.
dd if=/dev/zero bs=1 count=256 of=tmp/256.bytes
cat tmp/256.bytes tmp/driver.bin > tmp/driver.padded.bin

# Combine kernel base + driver + chgbnk  ->  Nextor-<ver>.TurboRFDD.ROM
mknexrom /path/to/Nextor-<ver>.base.dat Nextor-<ver>.TurboRFDD.ROM \
    /d:tmp/driver.padded.bin /m:tmp/chgbnk.bin
```

To override the FDC slot, add `--define-symbols FDC_SLOT=<value>` to the driver `N80` call. For an undoc-free build, add `--define-symbols NO_UNDOC_CPU_INSTRUCTIONS` to *both* `N80` calls and use a `Nextor-<ver>.base.NO_UNDOC.dat` kernel base.

**RAM driver:**

```sh
N80 driver.asm turbofdd.drv \
    --no-string-escapes --build-type abs \
    --include-directory external/Nextor/sdk \
    --define-symbols RAM_DRIVER
```

For an undoc-free build, add `--define-symbols NO_UNDOC_CPU_INSTRUCTIONS`.

## Make variables

| Variable                    | Purpose                                                                                                       | Default                  |
| --------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `NEXTOR_BASE`               | Path to the Nextor kernel base `.dat` file. Mandatory for the ROM build, not used by the RAM build.            | _(unset; error for ROM)_ |
| `NEXTOR_SDK`                | Path to the Nextor SDK directory (the one containing `asm/`).                                                  | `external/Nextor/sdk`    |
| `N80`                       | Path to the Nestor80 assembler.                                                                                | `N80` (from `PATH`)      |
| `MKNEXROM`                  | Path to the `mknexrom` tool.                                                                                   | `mknexrom` (from `PATH`) |
| `NO_UNDOC_CPU_INSTRUCTIONS` | If set (e.g. `=1`), assemble the driver without undocumented opcodes.                                          | _(unset)_                |
| `FDC_SLOT`                  | ROM build only: override the FDC hardware slot (e.g. `FDC_SLOT=8Fh` for slot 3-3). Ignored by the RAM build.   | _(default 8Bh, slot 3-2)_ |

Cleanup targets:

| Target           | Effect                                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------------------------- |
| `make clean`     | Removes `tmp/` (intermediate `.bin` files and helper artifacts). `bin/` and the shippable outputs in it are kept. |
| `make clean-bin` | Removes `bin/` (the shippable ROM and `.drv`).                                                                  |
| `make distclean` | Removes both `tmp/` and `bin/`.                                                                                 |

## License

MIT - see [LICENSE](LICENSE). Note that [Nextor itself has a different license](https://github.com/Konamiman/Nextor/blob/v3.0/LICENSE.md).
