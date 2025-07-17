#pragma once

#include <torch/torch.h>

namespace relu {

// Kernel implementation function
void relu(torch::Tensor &out, const torch::Tensor &input);

} // namespace relu