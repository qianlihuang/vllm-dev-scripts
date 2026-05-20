#!/bin/bash
# Pre-download all vLLM external dependencies so CMake doesn't need to fetch them.
# Usage: bash download_deps.sh [target_dir]
#   target_dir defaults to /vllm-workspace

set -euo pipefail

TARGET="${1:-/vllm-workspace}"
mkdir -p "$TARGET"
cd "$TARGET"

echo "=== Downloading vLLM external dependencies to: $TARGET ==="

# 1. CUTLASS (v4.4.2) — for main vLLM C++ extensions (_C, _moe_C, etc.)
if [ ! -d "cutlass-4.4.2" ]; then
    echo "[1/7] Cloning cutlass v4.4.2..."
    git clone --branch v4.4.2 --depth 1 https://github.com/nvidia/cutlass.git cutlass-4.4.2
else
    echo "[1/7] cutlass v4.4.2 already exists, skipping."
fi

# 2. vllm-flash-attention
if [ ! -d "flash-attention-bce2942" ]; then
    echo "[2/7] Cloning vllm-flash-attention..."
    git clone https://github.com/vllm-project/flash-attention.git flash-attention-bce2942
    cd flash-attention-bce2942
    git checkout bce29425653ec0fbc579d329883030e832d15ada
    cd ..
else
    echo "[2/7] vllm-flash-attention already exists, skipping."
fi

# flash-attention has csrc/cutlass as a git submodule pointing to CUTLASS v3.9.
# CUTLASS v4.4.2 (step 1) has a different CuTE API so FA2/FA3 won't compile with it.
# Clone the exact CUTLASS version that flash-attn expects.
FLASH_ATTN_CUTLASS_DIR="cutlass-flashattn-62750a2"
if [ ! -d "$FLASH_ATTN_CUTLASS_DIR" ]; then
    echo "[2/7] Cloning cutlass v3.9 for flash-attention..."
    git clone https://github.com/NVIDIA/cutlass.git "$FLASH_ATTN_CUTLASS_DIR"
    cd "$FLASH_ATTN_CUTLASS_DIR"
    git checkout 62750a2b75c802660e4894434dc55e839f322277
    cd ..
else
    echo "[2/7] cutlass v3.9 for flash-attention already exists, skipping."
fi

# Symlink the correct CUTLASS into flash-attention's expected submodule path
if [ ! -f "flash-attention-bce2942/csrc/cutlass/include/cute/tensor.hpp" ]; then
    echo "[2/7] Linking flash-attn submodule: csrc/cutlass -> $FLASH_ATTN_CUTLASS_DIR"
    rm -rf flash-attention-bce2942/csrc/cutlass
    ln -sf "$TARGET/$FLASH_ATTN_CUTLASS_DIR" flash-attention-bce2942/csrc/cutlass
fi

# 3. Triton kernels (v3.6.0)
if [ ! -d "triton-3.6.0" ]; then
    echo "[3/7] Cloning triton v3.6.0..."
    git clone --branch v3.6.0 --depth 1 https://github.com/triton-lang/triton.git triton-3.6.0
else
    echo "[3/7] triton already exists, skipping."
fi

# 4. DeepGEMM
if [ ! -d "DeepGEMM-891d57b" ]; then
    echo "[4/7] Cloning DeepGEMM (with submodules)..."
    git clone https://github.com/deepseek-ai/DeepGEMM.git DeepGEMM-891d57b
    cd DeepGEMM-891d57b
    git checkout 891d57b4db1071624b5c8fa0d1e51cb317fa709f
    git submodule update --init --recursive
    cd ..
else
    echo "[4/7] DeepGEMM already exists, skipping."
fi

# 5. FlashMLA
if [ ! -d "FlashMLA-a6ec2ba" ]; then
    echo "[5/7] Cloning FlashMLA..."
    git clone https://github.com/vllm-project/FlashMLA FlashMLA-a6ec2ba
    cd FlashMLA-a6ec2ba
    git checkout a6ec2ba7bd0a7dff98b3f4d3e6b52b159c48d78b
    cd ..
else
    echo "[5/7] FlashMLA already exists, skipping."
fi
# FlashMLA has csrc/cutlass as a git submodule. Reuse the CUTLASS from step 1
# via symlink to avoid network issues with submodule clone.
if [ ! -f "FlashMLA-a6ec2ba/csrc/cutlass/include/cutlass/bfloat16.h" ]; then
    echo "[5/7] Linking FlashMLA submodule: csrc/cutlass -> cutlass-4.4.2"
    rm -rf FlashMLA-a6ec2ba/csrc/cutlass
    ln -sf "$TARGET/cutlass-4.4.2" FlashMLA-a6ec2ba/csrc/cutlass
fi

# 6. QuTLASS
if [ ! -d "qutlass-830d2c4" ]; then
    echo "[6/7] Cloning QuTLASS..."
    git clone https://github.com/IST-DASLab/qutlass.git qutlass-830d2c4
    cd qutlass-830d2c4
    git checkout 830d2c4537c7396e14a02a46fbddd18b5d107c65
    cd ..
else
    echo "[6/7] QuTLASS already exists, skipping."
fi

# 7. Add torch/lib to ldconfig and bashrc so vllm._C can find libtorch.so at runtime
TORCH_LIB_DIR="$(python3 -c 'import torch; print(torch.__file__.rsplit("/",2)[0]+"/lib")' 2>/dev/null || true)"
if [ -n "$TORCH_LIB_DIR" ] && [ -d "$TORCH_LIB_DIR" ]; then
    echo "[7/7] Registering torch lib path: $TORCH_LIB_DIR"
    echo "$TORCH_LIB_DIR" > /etc/ld.so.conf.d/torch.conf
    ldconfig
    if ! grep -q "torch/lib" /root/.bashrc 2>/dev/null; then
        echo 'export LD_LIBRARY_PATH='"$TORCH_LIB_DIR"':$LD_LIBRARY_PATH' >> /root/.bashrc
    fi
else
    echo "[7/7] WARNING: Could not find torch lib directory. Set LD_LIBRARY_PATH manually."
fi

echo ""
echo "=== All dependencies downloaded ==="
echo ""
echo "Export these before running 'pip install -e .':"
echo ""
echo "export VLLM_CUTLASS_SRC_DIR=$TARGET/cutlass-4.4.2"
echo "export VLLM_FLASH_ATTN_SRC_DIR=$TARGET/flash-attention-bce2942"
echo "export TRITON_KERNELS_SRC_DIR=$TARGET/triton-3.6.0/python/triton_kernels/triton_kernels"
echo "export DEEPGEMM_SRC_DIR=$TARGET/DeepGEMM-891d57b"
echo "export FLASH_MLA_SRC_DIR=$TARGET/FlashMLA-a6ec2ba"
echo "export QUTLASS_SRC_DIR=$TARGET/qutlass-830d2c4"
