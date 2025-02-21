#pragma once

#include <torch/torch.h>

void silu_and_mul(torch::Tensor &out, torch::Tensor &input);

void gelu_and_mul(torch::Tensor &out, torch::Tensor &input);

void gelu_tanh_and_mul(torch::Tensor &out, torch::Tensor &input);

void fatrelu_and_mul(torch::Tensor &out, torch::Tensor &input,
                     double threshold);

void gelu_new(torch::Tensor &out, torch::Tensor &input);

void gelu_fast(torch::Tensor &out, torch::Tensor &input);

void gelu_quick(torch::Tensor &out, torch::Tensor &input);
