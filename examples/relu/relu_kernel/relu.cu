#include <ATen/cuda/CUDAContext.h>
#include <c10/cuda/CUDAGuard.h>
#include <torch/all.h>

#include <cmath>

__global__ void relu_kernel(float *__restrict__ out,
                            float const *__restrict__ input,
                            const int d) {
  const int64_t token_idx = blockIdx.x;
  for (int64_t idx = threadIdx.x; idx < d; idx += blockDim.x) {
    auto x = input[token_idx * d + idx];
    out[token_idx * d + idx] = x > 0.0f ? x : 0.0f;
  }
}

void relu(torch::Tensor &out,
          torch::Tensor const &input)
{
  TORCH_CHECK(input.scalar_type() == at::ScalarType::Float &&
                  input.scalar_type() == at::ScalarType::Float,
              "relu_kernel only supports float32");

  int d = input.size(-1);
  int64_t num_tokens = input.numel() / d;
  dim3 grid(num_tokens);
  dim3 block(std::min(d, 1024));
  const at::cuda::OptionalCUDAGuard device_guard(device_of(input));
  const cudaStream_t stream = at::cuda::getCurrentCUDAStream();
  relu_kernel<<<grid, block, 0, stream>>>(out.data_ptr<float>(),
                                          input.data_ptr<float>(), d);
}
