#include <torch/library.h>

#include "registration.h"
#include "torch_binding.h"

TORCH_LIBRARY_EXPAND(TORCH_EXTENSION_NAME, ops) {
  ops.def("relu(Tensor! out, Tensor input) -> ()");
  ops.impl("relu", torch::kCUDA, &relu);
}

REGISTER_EXTENSION(TORCH_EXTENSION_NAME)
