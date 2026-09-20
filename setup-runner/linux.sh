#!/usr/bin/env bash
# Put a C/C++ toolchain on PATH. Skip apt when the tools are already present.
set -euo pipefail

missing=()
for tool in cc c++ make clang cmake ninja pkg-config nasm wget; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if ((${#missing[@]})); then
    printf 'Installing native build tools; missing: %s\n' "${missing[*]}"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        build-essential clang cmake ninja-build pkg-config libssl-dev nasm wget
fi

for tool in cc c++ make clang cmake ninja pkg-config nasm wget; do
    command -v "$tool"
done
