# Changelog

All notable changes to the Single Node Frappista project will be documented in this file.

## [Unreleased]

### Added
- **Native ARM64 Support**: Switched to using GitHub's native `ubuntu-24.04-arm` runners for the ARM64 build job (`build-arm64`). This completely bypasses QEMU emulation, resulting in massive speed improvements during the container build process for Apple Silicon / ARM-based hosts.
- **procps-ng Package**: Added `procps-ng` to the base image dependencies in `Containerfile` to provide the `ps` command. This fixes the CI `smoke-test` failing to verify running processes.
- **User-friendly README**: Refactored `README.md` to prioritize the end-user experience. It now explains what Single Node Frappista is, lists the available Docker Hub image coordinates, and details exactly how to run the container and mount custom applications locally.

### Changed
- **Parallel Pipeline Architecture**: Split the monolithic sequential `build-and-test` GitHub Actions job into parallel `build-amd64` and `build-arm64` jobs to drastically reduce overall execution time.
- **Simplified Architecture Branching**: Removed the verbose 15-line `if/else` architecture check for installing `wkhtmltox` in the `Containerfile`. It now dynamically resolves the correct package using a single 3-line `RUN` step leveraging `$(uname -m)`.
- **Manifest Creation Job**: Updated the `create-manifests` job to build multi-arch manifests entirely from remote Docker Hub images via `docker://` syntax, bypassing local Makefile constraints.
- **Documentation Migration**: Relocated the highly technical "S2I Builder Image" documentation from the main README into the `docs/s2i-builder.md` file to keep the entry point clean.
