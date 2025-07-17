#include <torch/torch.h>
#include "torch_binding.h"
#include "registration.h"

// PyTorch operator registration
TORCH_LIBRARY_EXPAND(TORCH_EXTENSION_NAME, ops) {
  // Define the operator signature
  ops.def("relu(Tensor! out, Tensor input) -> ()");
  
  // Register Metal implementation
  ops.impl("relu", torch::kMPS, &relu::relu);
}

// Register the extension for Python import
REGISTER_EXTENSION(TORCH_EXTENSION_NAME)