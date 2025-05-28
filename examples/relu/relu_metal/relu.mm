#include <torch/torch.h>

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <string>

char const *CUSTOM_KERNEL = R"(
        #include <metal_stdlib>
        using namespace metal;

        kernel void relu_forward_kernel_float(device const float *inA [[buffer(0)]],
                                        device float *outC [[buffer(1)]],
                                        uint index [[thread_position_in_grid]]) {
            // Explicitly write to output
            outC[index] = max(0.0f, inA[index]);
        }

        kernel void relu_forward_kernel_half(device const half *inA [[buffer(0)]],
                                        device half *outC [[buffer(1)]],
                                        uint index [[thread_position_in_grid]]) {
            // Explicitly write to output
            outC[index] = max(static_cast<half>(0.0), inA[index]);
        }
)";

static inline id<MTLBuffer> getMTLBufferStorage(const torch::Tensor &tensor) {
  return __builtin_bit_cast(id<MTLBuffer>, tensor.storage().data());
}

torch::Tensor &dispatchReluKernel(torch::Tensor const &input,
                                  torch::Tensor &output) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    NSError *error = nil;

    int numThreads = input.numel();

    id<MTLLibrary> customKernelLibrary = [device
        newLibraryWithSource:[NSString stringWithUTF8String:CUSTOM_KERNEL]
                     options:nil
                       error:&error];
    TORCH_CHECK(customKernelLibrary,
                "Failed to to create custom kernel library, error: ",
                error.localizedDescription.UTF8String);

    std::string kernel_name =
        std::string("relu_forward_kernel_") +
        (input.scalar_type() == torch::kFloat ? "float" : "half");
    id<MTLFunction> customReluFunction = [customKernelLibrary
        newFunctionWithName:[NSString
                                stringWithUTF8String:kernel_name.c_str()]];
    TORCH_CHECK(customReluFunction,
                "Failed to create function state object for ",
                kernel_name.c_str());

    id<MTLComputePipelineState> reluPSO =
        [device newComputePipelineStateWithFunction:customReluFunction
                                              error:&error];
    TORCH_CHECK(reluPSO, error.localizedDescription.UTF8String);

    id<MTLCommandBuffer> commandBuffer = torch::mps::get_command_buffer();
    TORCH_CHECK(commandBuffer, "Failed to retrieve command buffer reference");

    dispatch_queue_t serialQueue = torch::mps::get_dispatch_queue();

    dispatch_sync(serialQueue, ^() {
      id<MTLComputeCommandEncoder> computeEncoder =
          [commandBuffer computeCommandEncoder];
      TORCH_CHECK(computeEncoder, "Failed to create compute command encoder");

      [computeEncoder setComputePipelineState:reluPSO];
      [computeEncoder setBuffer:getMTLBufferStorage(input)
                         offset:input.storage_offset() * input.element_size()
                        atIndex:0];
      [computeEncoder setBuffer:getMTLBufferStorage(output)
                         offset:output.storage_offset() * output.element_size()
                        atIndex:1];

      MTLSize gridSize = MTLSizeMake(numThreads, 1, 1);

      NSUInteger threadGroupSize = reluPSO.maxTotalThreadsPerThreadgroup;
      if (threadGroupSize > numThreads) {
        threadGroupSize = numThreads;
      }
      MTLSize threadgroupSize = MTLSizeMake(threadGroupSize, 1, 1);

      [computeEncoder dispatchThreads:gridSize
                threadsPerThreadgroup:threadgroupSize];

      [computeEncoder endEncoding];

      torch::mps::commit();
    });
  }

  return output;
}

void relu(torch::Tensor &out, const torch::Tensor &input) {
  TORCH_CHECK(input.device().is_mps(), "input must be a MPS tensor");
  TORCH_CHECK(input.is_contiguous(), "input must be contiguous");
  TORCH_CHECK(input.scalar_type() == torch::kFloat ||
                  input.scalar_type() == torch::kHalf,
              "Unsupported data type: ", input.scalar_type());

  TORCH_CHECK(input.sizes() == out.sizes(),
              "Tensors must have the same shape. Got input shape: ",
              input.sizes(), " and output shape: ", out.sizes());

  TORCH_CHECK(input.scalar_type() == out.scalar_type(),
              "Tensors must have the same data type. Got input dtype: ",
              input.scalar_type(), " and output dtype: ", out.scalar_type());

  TORCH_CHECK(input.device() == out.device(),
              "Tensors must be on the same device. Got input device: ",
              input.device(), " and output device: ", out.device());

  dispatchReluKernel(input, out);
}
