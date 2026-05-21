# vllm-dev-scripts

```
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
export all_proxy=socks5://127.0.0.1:7897

export CUDA_HOME=/usr/local/cuda-13.0
export PATH=$CUDA_HOME/bin:$PATH

export TARGET=/vllm-workspace
export VLLM_CUTLASS_SRC_DIR=$TARGET/cutlass-4.4.2
export VLLM_FLASH_ATTN_SRC_DIR=$TARGET/flash-attention-bce2942
export TRITON_KERNELS_SRC_DIR=$TARGET/triton-3.6.0/python/triton_kernels/triton_kernels
export DEEPGEMM_SRC_DIR=$TARGET/DeepGEMM-891d57b
export FLASH_MLA_SRC_DIR=$TARGET/FlashMLA-a6ec2ba
export QUTLASS_SRC_DIR=$TARGET/qutlass-830d2c4


cd /vllm-workspace/vllm
cmake -B build -G Ninja \
  -DVLLM_PYTHON_EXECUTABLE=$(which python3) \
  -DCMAKE_CUDA_COMPILER=$(which nvcc)
cmake --build build

pip install -e . --no-build-isolation --config-settings="--build-option=--build-base=$TARGET/build" -v



# Install deps and patch cuda-tile for missing shared Python lib
# (Python 3.12 compiled without --enable-shared, so cuda-tile's .so can't find libpython3.12.so.1.0)
apt-get install -y patchelf 2>/dev/null
patchelf --remove-needed libpython3.12.so.1.0 /usr/local/lib/python3.12/site-packages/cuda/tile/_cext*.so 2>/dev/null || true
```
