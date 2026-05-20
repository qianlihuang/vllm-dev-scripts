#!/bin/bash
# Fix missing CUDA 13 dev headers and library symlinks for vLLM build.
# Usage: sudo bash fix_cuda_deps.sh

set -euo pipefail

CUDA_DIR="/usr/local/cuda"
CUDA_LIB="${CUDA_DIR}/lib64"
CUDA_INC="${CUDA_DIR}/include"

echo "=== Step 1: Detect CUDA version ==="
CUDA_MAJOR=$(grep -oP 'version\s+\K\d+' "${CUDA_DIR}/version.txt" 2>/dev/null || echo "13")
CUDA_MINOR=$(grep -oP 'version\s+\d+\.\K\d+' "${CUDA_DIR}/version.txt" 2>/dev/null || echo "0")
CUDA_VER="${CUDA_MAJOR}-${CUDA_MINOR}"
echo "CUDA ${CUDA_MAJOR}.${CUDA_MINOR} (package suffix: ${CUDA_VER})"

echo ""
echo "=== Step 2: Find required headers from PyTorch CUDAContextLight.h ==="
# PyTorch's CUDAContextLight.h is the main header that triggers includes
TORCH_CUDA_HEADER=$(find / -path "*/torch/include/ATen/cuda/CUDAContextLight.h" 2>/dev/null | head -1)
REQUIRED_HEADERS=()
if [ -f "$TORCH_CUDA_HEADER" ]; then
    while IFS= read -r h; do
        h="${h%.h}.h"  # normalize
        REQUIRED_HEADERS+=("$h")
        echo "  Required: $h"
    done < <(grep -oP '#include\s+<\K[^>]+' "$TORCH_CUDA_HEADER" | grep -E '^cu')
else
    # Fallback: list known requirements from CUDA 13 + PyTorch
    REQUIRED_HEADERS=(cuda_runtime_api.h cusparse.h cublas_v2.h cublasLt.h cusolverDn.h cudss.h cufft.h curand.h nvJitLink.h)
    echo "  (using fallback list) ${REQUIRED_HEADERS[*]}"
fi

echo ""
echo "=== Step 3: Check missing headers ==="
MISSING_HEADERS=()
for h in "${REQUIRED_HEADERS[@]}"; do
    if [ ! -f "${CUDA_INC}/${h}" ]; then
        echo "  MISSING: ${h}"
        MISSING_HEADERS+=("$h")
    else
        echo "  OK: ${h}"
    fi
done

echo ""
echo "=== Step 4: Check missing .so symlinks (unversioned) ==="
# Libraries that PyTorch/vLLM link against
CUDA_LIBS=(cublas cufft curand cusolver cusparse cupti nvJitLink cufile nvrtc nvrtc-builtins)

MISSING_SO=()
for lib in "${CUDA_LIBS[@]}"; do
    so_file="${CUDA_LIB}/lib${lib}.so"
    if [ -f "$so_file" ] || [ -L "$so_file" ]; then
        echo "  OK: lib${lib}.so"
    else
        # Check if versioned files exist but unversioned symlink is missing
        versioned=$(ls "${CUDA_LIB}/lib${lib}".so.* 2>/dev/null | head -1)
        if [ -n "$versioned" ]; then
            echo "  MISSING symlink: lib${lib}.so (have: $versioned)"
            MISSING_SO+=("$lib")
        else
            echo "  MISSING entirely: lib${lib}.so"
            MISSING_SO+=("$lib")
        fi
    fi
done

# Also check for lowercase variants (CUDA 13 uses camelCase like nvJitLink)
for lib in "${CUDA_LIBS[@]}"; do
    lib_lower=$(echo "$lib" | tr '[:upper:]' '[:lower:]')
    if [ "$lib_lower" != "$lib" ]; then
        so_file="${CUDA_LIB}/lib${lib_lower}.so"
        if [ -f "$so_file" ] || [ -L "$so_file" ]; then
            :
        else
            camel_file="${CUDA_LIB}/lib${lib}.so"
            if [ -f "$camel_file" ] || [ -L "$camel_file" ]; then
                echo "  MISSING lowercase alias: lib${lib_lower}.so -> lib${lib}.so"
                MISSING_SO+=("${lib_lower}")
            fi
        fi
    fi
done

echo ""
echo "=== Step 5: Map missing headers to apt packages ==="
declare -A HEADER_TO_PKG
HEADER_TO_PKG[cublas_v2.h]="libcublas-dev-${CUDA_VER}"
HEADER_TO_PKG[cublasLt.h]="libcublas-dev-${CUDA_VER}"
HEADER_TO_PKG[cusparse.h]="libcusparse-dev-${CUDA_VER}"
HEADER_TO_PKG[cusolverDn.h]="libcusolver-dev-${CUDA_VER}"
HEADER_TO_PKG[cufft.h]="libcufft-dev-${CUDA_VER}"
HEADER_TO_PKG[curand.h]="libcurand-dev-${CUDA_VER}"
HEADER_TO_PKG[cudss.h]="libcudss-dev-${CUDA_VER}"
HEADER_TO_PKG[nvJitLink.h]="libnvjitlink-dev-${CUDA_VER}"
HEADER_TO_PKG[cuda_runtime_api.h]="cuda-cudart-dev-${CUDA_VER}"

declare -A LIB_TO_PKG
LIB_TO_PKG[cupti]="cuda-cupti-dev-${CUDA_VER}"
LIB_TO_PKG[cufile]="libcufile-dev-${CUDA_VER}"
LIB_TO_PKG[nvJitLink]="libnvjitlink-dev-${CUDA_VER}"
LIB_TO_PKG[nvjitlink]="libnvjitlink-dev-${CUDA_VER}"
LIB_TO_PKG[nvrtc]="cuda-nvrtc-dev-${CUDA_VER}"
LIB_TO_PKG[nvrtc-builtins]="cuda-nvrtc-dev-${CUDA_VER}"

TO_INSTALL=()
for h in "${MISSING_HEADERS[@]}"; do
    pkg="${HEADER_TO_PKG[$h]:-}"
    if [ -n "$pkg" ] && ! dpkg -s "$pkg" &>/dev/null 2>&1; then
        TO_INSTALL+=("$pkg")
    fi
done
for lib in "${MISSING_SO[@]}"; do
    pkg="${LIB_TO_PKG[$lib]:-}"
    if [ -n "$pkg" ] && ! dpkg -s "$pkg" &>/dev/null 2>&1; then
        TO_INSTALL+=("$pkg")
    fi
done

# Deduplicate
TO_INSTALL=($(printf '%s\n' "${TO_INSTALL[@]}" | sort -u))

echo ""
echo "=== Step 6: Install missing packages ==="
if [ ${#TO_INSTALL[@]} -gt 0 ]; then
    echo "  Installing: ${TO_INSTALL[*]}"
    apt-get install -y "${TO_INSTALL[@]}"
else
    echo "  No apt packages needed."
fi

echo ""
echo "=== Step 7: Create missing .so symlinks ==="
for lib in "${MISSING_SO[@]}"; do
    # Find the latest versioned .so file
    versioned=$(ls -1 "${CUDA_LIB}/lib${lib}".so.* 2>/dev/null | grep -v '\.so\.[0-9]' | sort -V | tail -1)
    if [ -z "$versioned" ]; then
        # Try the two-level versioned file (e.g. libfoo.so.13.0.88 -> libfoo.so.13)
        versioned=$(ls -1 "${CUDA_LIB}/lib${lib}".so.*.* 2>/dev/null | sort -V | tail -1)
        if [ -z "$versioned" ]; then
            # Try camelCase variant
            camel_lib=""
            for candidate in "${CUDA_LIBS[@]}"; do
                candidate_lower=$(echo "$candidate" | tr '[:upper:]' '[:lower:]')
                if [ "$candidate_lower" = "$lib" ]; then
                    camel_lib="$candidate"
                    break
                fi
            done
            if [ -n "$camel_lib" ] && ([ -f "${CUDA_LIB}/lib${camel_lib}.so" ] || [ -L "${CUDA_LIB}/lib${camel_lib}.so" ]); then
                ln -sf "${CUDA_LIB}/lib${camel_lib}.so" "${CUDA_LIB}/lib${lib}.so"
                echo "  Created lowercase alias: lib${lib}.so -> lib${camel_lib}.so"
            else
                echo "  WARN: Cannot find any lib${lib}.so* files, skipping"
            fi
            continue
        fi
        # Create libfoo.so.13 -> libfoo.so.13.0.88
        shortver=$(basename "$versioned" | grep -oP '\.so\.\d+')
        if [ ! -f "${CUDA_LIB}/lib${lib}${shortver}" ] && [ ! -L "${CUDA_LIB}/lib${lib}${shortver}" ]; then
            ln -sf "$(basename "$versioned")" "${CUDA_LIB}/lib${lib}${shortver}"
        fi
        # Create libfoo.so -> libfoo.so.13
        ln -sf "lib${lib}${shortver}" "${CUDA_LIB}/lib${lib}.so"
        echo "  Created: lib${lib}.so -> lib${lib}${shortver}"
    else
        ln -sf "$(basename "$versioned")" "${CUDA_LIB}/lib${lib}.so"
        echo "  Created: lib${lib}.so -> $(basename "$versioned")"
    fi
done

echo ""
echo "=== Step 8: Fix CCCL symlinks (CUDA 13 moved thrust/cub/cuda into cccl/) ==="
TARGETS_INC="${CUDA_DIR}/targets/x86_64-linux/include"

fix_cccl_symlink() {
    local name="$1"
    local link_path="${CUDA_INC}/${name}"
    local targets_link="${TARGETS_INC}/${name}"

    # Check for self-referencing circular symlink
    local tgt=$(readlink "$targets_link" 2>/dev/null || true)
    if [ "$tgt" = "$targets_link" ]; then
        echo "  Fixing circular symlink: $targets_link -> $targets_link"
        rm -f "$targets_link"
        ln -sf "cccl/${name}" "$targets_link"
    elif [ ! -e "$targets_link" ]; then
        echo "  Creating missing symlink: $targets_link -> cccl/${name}"
        rm -f "$targets_link"
        ln -sf "cccl/${name}" "$targets_link"
    else
        echo "  OK: $targets_link"
    fi

    # Fix top-level include symlink
    local top_tgt=$(readlink "$link_path" 2>/dev/null || true)
    if [ "$top_tgt" = "$link_path" ]; then
        rm -f "$link_path"
        ln -sf "$targets_link" "$link_path"
    elif [ ! -e "$link_path" ]; then
        rm -f "$link_path"
        ln -sf "$targets_link" "$link_path"
    fi
}

for name in thrust cub cuda; do
    fix_cccl_symlink "$name"
done

echo ""
echo "=== Step 9: Run ldconfig ==="
ldconfig

echo ""
echo "=== Done. All CUDA dependencies should now be in place. ==="
