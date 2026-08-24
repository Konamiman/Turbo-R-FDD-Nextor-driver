# MSX Turbo-R FDD driver for Nextor

This repository contains a driver for the floppy disk controller built into the MSX Turbo-R computers (Panasonic FS-A1GT and FS-A1ST), for [Nextor](https://github.com/Konamiman/Nextor) v3.0 or newer. It drives the TC8566AF FDC and uses the S1990 system controller hardware for disk-change detection.

The driver can be built in two flavors:

| Output                                | Notes                                                                                  |
| ------------------------------------- | -------------------------------------------------------------------------------------- |
| `Nextor-<ver>.TurboRFDD.ROM`          | **ROM driver** (default `make` target). Combined with a Nextor kernel base file to produce a ROM image, ready to be flashed to an ASCII16-mapper cartridge. |
| `turbofdd.drv`                        | **RAM driver** (via `make ram`). Standalone `.drv` file that loads into a mapped RAM segment at runtime via CALL IDRIVER or DRVROP.COM.                       |

For the ROM driver, `<ver>` comes from the Nextor SDK and any kernel-base variant suffix (e.g. `.NO_UNDOC.SHIFT_INV.KANJI_INV`) is picked up automatically from the `NEXTOR_BASE` filename; see [Building](#building) below.

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
| `docker-build.sh` | Wrapper that builds the driver in the Nextor dev Docker image (no local toolchain needed). |
| `build-all.sh`    | Builds the ROM driver against every kernel base-file variant found in a directory, plus both RAM drivers, with the local toolchain. |
| `external/Nextor` | Git submodule pointing at the Nextor repo, sparse-checkout to the `sdk/` directory only. |

## Development environment

The quickest path needs **nothing but Docker**: see [Building with the Nextor dev Docker image](#building-with-the-nextor-dev-docker-image) below, which supplies the toolchain, the SDK and the kernel base files for you (no submodule or base file to fetch). To build with a local toolchain instead, you need:

- [**Nestor80**](https://github.com/Konamiman/Nestor80) (`N80`) on your `PATH`, or pointed at via the `N80` make variable.
- **`mknexrom`** on your `PATH`, or pointed at via the `MKNEXROM` make variable. Only needed for the ROM build. The source lives in the Nextor repository under `buildtools/sources/mknexrom.c`.
- A POSIX **`make`** and `dd` / `cat` (for the ROM build).
- A Nextor kernel base file (for the ROM build) and the Nextor SDK (the `external/Nextor` submodule, set up with `make setup`).

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

There are two ways to build: with the **Nextor dev Docker image** (no local toolchain, SDK or kernel base file needed) or with a **local toolchain**.

### Building with the Nextor dev Docker image

The [`nextor-dev`](https://github.com/Konamiman/Nextor/pkgs/container/nextor-dev) image bundles `N80`, `mknexrom`, the Nextor SDK and all twelve kernel base-file variants, and presets `NEXTOR_BASE` / `NEXTOR_SDK`, so a build needs nothing else on your machine - not even the `external/Nextor` submodule. The `docker-build.sh` wrapper runs the build in a container, mounting this repository and writing the outputs into `bin/` owned by you (not root):

```sh
./docker-build.sh                       # the ROM driver, default kernel base
./docker-build.sh --variant NO_UNDOC    # build against the NO_UNDOC kernel base
./docker-build.sh --variant CTRL_INV
./docker-build.sh --variant NO_UNDOC.SHIFT_INV
./docker-build.sh --variant KANJI_INV
./docker-build.sh --variant NO_UNDOC.CTRL_INV.KANJI_INV
./docker-build.sh ram                   # the RAM driver (.drv); needs no base
./docker-build.sh --variant ram         # alias for `ram`
./docker-build.sh --variant all         # every base variant + both RAM drivers
./docker-build.sh clean                 # any extra args are passed to make
```

`--variant <suffix>` selects one of the image's kernel base files (`kernel_base<suffix>.dat`). The variants combine three independent axes: `NO_UNDOC` (no undocumented Z80 opcodes, for Z180-based machines), `SHIFT_INV` _or_ `CTRL_INV` (the SHIFT or CTRL boot key inverted), and `KANJI_INV` (the "6" boot key inverted, so the Kanji driver is installed at boot unless the key is pressed; always the last component of the suffix). The twelve suffixes are therefore `NO_UNDOC`, `SHIFT_INV`, `CTRL_INV`, `NO_UNDOC.SHIFT_INV`, `NO_UNDOC.CTRL_INV`, each of these with `.KANJI_INV` appended, and plain `KANJI_INV`; omitting `--variant` selects the default base. For a `*NO_UNDOC*` variant the Makefile assembles the driver undoc-free to match, and the variant suffix is reflected in the output ROM name, exactly as with a local build. `--variant all` builds the ROM against every base file the image ships and both forms of the RAM driver (default and NO_UNDOC) in a single container — 14 files in all (this runs `build-all.sh`, described below, inside the image). Run `./docker-build.sh --help` for the full list.

The image tag used by default is the kernel version this driver is built for (`3.0.0-beta1`); override it with `--image <ref>` or the `NEXTOR_IMAGE` environment variable. Note that the image's `latest` tag tracks stable kernel releases only, so it is not what you want while the driver targets a prerelease.

Extra arguments are passed straight through to `make`, so the wrapper covers the RAM driver and the FDC slot override too: `./docker-build.sh ram` (or its alias `./docker-build.sh --variant ram`) builds `bin/turbofdd.drv`, the RAM driver, which doesn't need a kernel base; and `./docker-build.sh FDC_SLOT=8Fh` overrides the FDC slot for the ROM build.

### Building with a local toolchain

#### ROM driver (default)

The build needs a Nextor kernel base file, supplied via `NEXTOR_BASE`:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.dat make
```

That produces the ROM in the `bin/` directory.

For an undoc-instruction-free build (compatible with Z180-based MSX machines), just point `NEXTOR_BASE` at an undoc-free kernel base — the Makefile infers `NO_UNDOC_CPU_INSTRUCTIONS` from a `NO_UNDOC` in the base filename's variant suffix, so the driver always matches the kernel it is combined with:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.NO_UNDOC.dat make
```

To target a non-default FDC slot, add `FDC_SLOT=<value>`:

```sh
NEXTOR_BASE=/path/to/Nextor-3.0.0.base.dat FDC_SLOT=8Fh make    # slot 3-3
```

The output ROM filename's version comes from the SDK's `nextor-kernel-version.txt`, and any variant suffix (e.g. `.NO_UNDOC.SHIFT_INV.KANJI_INV`) is taken from the Nextor base filename. The undoc inference only works when the base file follows one of the two naming conventions (`Nextor-<ver>.base[<suffix>].dat` or `kernel_base[<suffix>].dat`); with a base file named otherwise, set `NO_UNDOC_CPU_INSTRUCTIONS` by hand. An explicit value on the command line or in the environment always wins over the inference.

#### RAM driver

The RAM driver doesn't need `NEXTOR_BASE` (it isn't combined with a kernel base):

```sh
make ram
```

That produces `bin/turbofdd.drv`. Combine with `NO_UNDOC_CPU_INSTRUCTIONS=1` for an undoc-free build (output goes to `bin/turbofdd.NO_UNDOC.drv`). The hardware slot is *not* baked in at build time; configure it at load time via CALL IDRIVER or DRVROP.COM (see [Hardware slot configuration](#hardware-slot-configuration) above).

#### Building every variant at once

To build the ROM for all the kernel base-file variants, plus both forms of the RAM driver (the local counterpart of `docker-build.sh --variant all`), point `NEXTOR_KERNEL_BASE_DIR` at the directory holding the base files and run `build-all.sh`:

```sh
NEXTOR_KERNEL_BASE_DIR=/path/to/Nextor/bin/kernel-base ./build-all.sh
NEXTOR_KERNEL_BASE_DIR=/path/to/Nextor/bin/kernel-base ./build-all.sh clean-bin all   # extra args go to make
```

There is no list of variants to maintain: the script scans the directory and builds against every `.dat` file there named by either convention the Makefile understands (`Nextor-<ver>.base[<suffix>].dat`, as built by the Nextor repository, or `kernel_base[<suffix>].dat`, as shipped in the Docker image), ordering the builds so the driver is reassembled only once when crossing into the undoc-free (`*NO_UNDOC*`) group. With the twelve variants of Nextor 3.0 that is 12 ROMs, and the two RAM drivers are built after them — 14 files in all (the RAM drivers are skipped when extra make args are given, since those usually name specific targets such as `distclean`). If the directory mixes base files from several kernel versions, the ones matching the SDK's version are used (and the script stops if none do). Run `./build-all.sh --help` for the details.

#### Building without `make`

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
| `NO_UNDOC_CPU_INSTRUCTIONS` | If non-empty (e.g. `=1`), assemble the driver without undocumented opcodes.                                    | _inferred: `1` if the `NEXTOR_BASE` filename's variant suffix contains `NO_UNDOC`, unset otherwise (so always unset for a `make ram` without `NEXTOR_BASE`)_ |
| `FDC_SLOT`                  | ROM build only: override the FDC hardware slot (e.g. `FDC_SLOT=8Fh` for slot 3-3). Ignored by the RAM build.   | _(default 8Bh, slot 3-2)_ |

Cleanup targets:

| Target           | Effect                                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------------------------- |
| `make clean`     | Removes `tmp/` (intermediate `.bin` files and helper artifacts). `bin/` and the shippable outputs in it are kept. |
| `make clean-bin` | Removes `bin/` (the shippable ROM and `.drv`).                                                                  |
| `make distclean` | Removes both `tmp/` and `bin/`.                                                                                 |

## License

MIT - see [LICENSE](LICENSE). Note that [Nextor itself has a different license](https://github.com/Konamiman/Nextor/blob/master/LICENSE.md).
