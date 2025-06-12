#include <torch/torch.h>

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <string>
#include <dlfcn.h>
#include <mach-o/dyld.h>

static inline id<MTLBuffer> getMTLBufferStorage(const torch::Tensor &tensor) {
  return __builtin_bit_cast(id<MTLBuffer>, tensor.storage().data());
}

static std::string getModuleDirectory() {
  Dl_info dl_info;
  if (dladdr((void*)getModuleDirectory, &dl_info)) {
    std::string path(dl_info.dli_fname);
    size_t pos = path.find_last_of('/');
    if (pos != std::string::npos) {
      return path.substr(0, pos);
    }
  }
  return ".";
}

torch::Tensor &dispatchReluKernel(torch::Tensor const &input,
                                  torch::Tensor &output) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    NSError *error = nil;

    int numThreads = input.numel();

    // Construct the full path to the metallib file
    std::string moduleDir = getModuleDirectory();
    std::string metallibPath = moduleDir + "/" + METALLIB_PATH;
    
    NSString *metallibPathStr = [NSString stringWithUTF8String:metallibPath.c_str()];
    NSURL *metallibURL = [NSURL fileURLWithPath:metallibPathStr];
    id<MTLLibrary> customKernelLibrary = [device newLibraryWithURL:metallibURL error:&error];
    if (!customKernelLibrary) {
      NSLog(@"[relu.mm] Failed to load pre-compiled Metal library at %@, will fall back to runtime compilation. Error: %@", metallibPathStr, error.localizedDescription);
    }

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
