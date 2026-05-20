#!/bin/bash
# Pre-download all vLLM external dependencies so CMake doesn't need to fetch them.
# Usage: bash download_deps.sh [target_dir]
#   target_dir defaults to /vllm-workspace

set -euo pipefail

TARGET="${1:-/vllm-workspace}"
mkdir -p "$TARGET"
cd "$TARGET"

echo "=== Downloading vLLM external dependencies to: $TARGET ==="

# 1. CUTLASS (v4.4.2)
if [ ! -d "cutlass-4.4.2" ]; then
    echo "[1/6] Cloning cutlass v4.4.2..."
    git clone --branch v4.4.2 --depth 1 https://github.com/nvidia/cutlass.git cutlass-4.4.2
else
    echo "[1/6] cutlass already exists, skipping."
fi

# 2. vllm-flash-attention
if [ ! -d "flash-attention-bce2942" ]; then
    echo "[2/6] Cloning vllm-flash-attention..."
    git clone https://github.com/vllm-project/flash-attention.git flash-attention-bce2942
    cd flash-attention-bce2942
    git checkout bce29425653ec0fbc579d329883030e832d15ada
    cd ..
else
    echo "[2/6] vllm-flash-attention already exists, skipping."
fi

# 3. Triton kernels (v3.6.0)
if [ ! -d "triton-3.6.0" ]; then
    echo "[3/6] Cloning triton v3.6.0..."
    git clone --branch v3.6.0 --depth 1 https://github.com/triton-lang/triton.git triton-3.6.0
else
    echo "[3/6] triton already exists, skipping."
fi

# 4. DeepGEMM
if [ ! -d "DeepGEMM-891d57b" ]; then
    echo "[4/6] Cloning DeepGEMM (with submodules)..."
    git clone https://github.com/deepseek-ai/DeepGEMM.git DeepGEMM-891d57b
    cd DeepGEMM-891d57b
    git checkout 891d57b4db1071624b5c8fa0d1e51cb317fa709f
    git submodule update --init --recursive
    cd ..
else
    echo "[4/6] DeepGEMM already exists, skipping."
fi

# 5. FlashMLA
if [ ! -d "FlashMLA-a6ec2ba" ]; then
    echo "[5/6] Cloning FlashMLA..."
    git clone https://github.com/vllm-project/FlashMLA FlashMLA-a6ec2ba
    cd FlashMLA-a6ec2ba
    git checkout a6ec2ba7bd0a7dff98b3f4d3e6b52b159c48d78b
    cd ..
else
    echo "[5/6] FlashMLA already exists, skipping."
fi

# 6. QuTLASS
if [ ! -d "qutlass-830d2c4" ]; then
    echo "[6/6] Cloning QuTLASS..."
    git clone https://github.com/IST-DASLab/qutlass.git qutlass-830d2c4
    cd qutlass-830d2c4
    git checkout 830d2c4537c7396e14a02a46fbddd18b5d107c65
    cd ..
else
    echo "[6/6] QuTLASS already exists, skipping."
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
