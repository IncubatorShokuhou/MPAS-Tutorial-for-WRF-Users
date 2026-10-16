# Repository Guidelines

## Project Structure & Module Organization

This repository contains reproducible MPAS-Atmosphere build and forecasting tutorials. Keep the top level easy to scan:

- `README.md`: prerequisites and the recommended tutorial path.
- `tutorial/`: numbered Chinese walkthroughs, beginning with compilation and WPS preprocessing.
- `install_*.sh`: interactive and command-line installers for MPAS, its I/O stack, and WPS.
- `configs/`: future namelists, streams files, and version-controlled examples.
- `tests/`: lightweight validation scripts and fixtures.
- `data/`: only small sample inputs; do not commit large model datasets or generated output.

Place generated files in an ignored directory such as `work/` or `output/`. Tutorial-specific assets should live beside their tutorial or in a clearly named subdirectory.

## Build, Test, and Development Commands

Run installers from the repository root:

- `./install_mpas.sh` — interactively build the full dependency stack and MPAS.
- `./install_mpas.sh -y --with-wps` — non-interactive full installation including WPS `ungrib`.
- `./install_io_stack.sh --dry-run` — validate dependency paths without building.
- `bash -n install_*.sh` — check installer syntax.

Shell scripts should use `set -euo pipefail` and expose usage information with `./scripts/<name>.sh --help` when they accept arguments.

## Coding Style & Naming Conventions

Use four spaces for Python and two spaces for YAML. Format shell scripts consistently and quote variable expansions. Choose descriptive, lowercase filenames with underscores, for example `prepare_initial_conditions.py`; use `.sh` for shell entry points. Name MPAS configuration examples by purpose or resolution, such as `namelist.atmosphere.conus`.

Never hard-code machine-specific absolute paths. Accept paths through arguments or documented environment variables instead.

## Testing Guidelines

Add a regression check for each script or reproducible workflow. Tests should use small fixtures and avoid requiring full production datasets. Name Python tests `test_*.py` and shell checks `test_*.sh`. At minimum, verify configuration generation, command exit status, and expected output files. Document any HPC-only validation steps that cannot run locally.

## Commit & Pull Request Guidelines

There is no Git history establishing a local convention. Use short, imperative commit subjects, optionally scoped, such as `docs: add atmosphere setup walkthrough`. Keep commits focused and exclude binaries, credentials, logs, and model output.

Pull requests should explain the goal, list validation performed, note required MPAS/compiler/MPI versions, and link related issues. Include concise output excerpts or screenshots when tutorial results or figures change.
