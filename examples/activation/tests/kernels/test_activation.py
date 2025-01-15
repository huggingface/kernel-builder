import math
import random
from typing import Type

import activation
import pytest
import torch
import torch.nn.functional as F

from .utils import opcheck
from .allclose_default import get_default_atol, get_default_rtol

DTYPES = [torch.half, torch.bfloat16, torch.float]
NUM_TOKENS = [7, 83, 2048]  # Arbitrary values for testing
D = [512, 13824]  # Arbitrary values for testing
SEEDS = [0]
CUDA_DEVICES = [f"cuda:{i}" for i in range(1 if torch.cuda.device_count() == 1 else 2)]


def gelu_fast(x: torch.Tensor) -> torch.Tensor:
    return 0.5 * x * (1.0 + torch.tanh(x * 0.7978845608 * (1.0 + 0.044715 * x * x)))


def gelu_new(x: torch.Tensor) -> torch.Tensor:
    c = math.sqrt(2.0 / math.pi)
    return 0.5 * x * (1.0 + torch.tanh(c * (x + 0.044715 * torch.pow(x, 3.0))))


def gelu_quick(x: torch.Tensor) -> torch.Tensor:
    return x * torch.sigmoid(1.702 * x)


def fatrelu_and_mul(x: torch.Tensor, threshold: float) -> torch.Tensor:
    d = x.shape[-1] // 2
    x1 = x[..., :d]
    x2 = x[..., d:]
    x1 = F.threshold(x1, threshold, 0.0)
    return x1 * x2


def silu_and_mul(x: torch.Tensor) -> torch.Tensor:
    d = x.shape[-1] // 2
    return F.silu(x[..., :d]) * x[..., d:]


def gelu_and_mul(x: torch.Tensor, approximate: str) -> torch.Tensor:
    d = x.shape[-1] // 2
    return F.gelu(x[..., :d], approximate=approximate) * x[..., d:]


@pytest.mark.parametrize("activation_name", ["silu", "gelu", "gelu_tanh", "fatrelu"])
@pytest.mark.parametrize("num_tokens", NUM_TOKENS)
@pytest.mark.parametrize("d", D)
@pytest.mark.parametrize("dtype", DTYPES)
@pytest.mark.parametrize("seed", SEEDS)
@pytest.mark.parametrize("device", CUDA_DEVICES)
@torch.inference_mode()
def test_act_and_mul(
    activation_name: str,
    num_tokens: int,
    d: int,
    dtype: torch.dtype,
    seed: int,
    device: str,
) -> None:
    random.seed(seed)
    torch.manual_seed(seed)
    torch.set_default_device(device)
    x = torch.randn(num_tokens, 2 * d, dtype=dtype)
    if activation_name == "silu":
        torch_fn = silu_and_mul
        fn = activation.silu_and_mul
        op = activation.ops.silu_and_mul
    elif activation_name == "gelu":
        torch_fn = lambda x: gelu_and_mul(x, "none")
        fn = activation.gelu_and_mul
        op = activation.ops.gelu_and_mul
    elif activation_name == "gelu_tanh":
        torch_fn = lambda x: gelu_and_mul(x, "tanh")
        fn = activation.gelu_tanh_and_mul
        op = activation.ops.gelu_tanh_and_mul
    elif activation_name == "fatrelu":
        threshold = random.uniform(0, 1)
        torch_fn = lambda x: fatrelu_and_mul(x, threshold)
        fn = lambda out, x: activation.fatrelu_and_mul(out, x, threshold)
        op = activation.ops.fatrelu_and_mul

    out_shape = x.shape[:-1] + (x.shape[-1] // 2,)
    out = torch.empty(out_shape, dtype=x.dtype, device=x.device)
    out = fn(out, x)
    ref_out = torch_fn(x)

    # The SiLU, GELU and FatReLU implementations are equivalent to the native
    # PyTorch implementations, so we can do exact comparison.
    torch.testing.assert_close(out, ref_out, atol=0.0, rtol=0.0)

    d = x.shape[-1] // 2
    output_shape = x.shape[:-1] + (d,)
    out = torch.empty(output_shape, dtype=x.dtype, device=x.device)
    if activation_name == "fatrelu":
        opcheck(op, (out, x, threshold))
    else:
        opcheck(op, (out, x))


@pytest.mark.parametrize(
    "activation_fns",
    [
        (gelu_fast, activation.gelu_fast, activation.ops.gelu_fast),
        (gelu_new, activation.gelu_new, activation.ops.gelu_new),
        (gelu_quick, activation.gelu_quick, activation.ops.gelu_quick),
    ],
)
@pytest.mark.parametrize("num_tokens", NUM_TOKENS)
@pytest.mark.parametrize("d", D)
@pytest.mark.parametrize("dtype", DTYPES)
@pytest.mark.parametrize("seed", SEEDS)
@pytest.mark.parametrize("device", CUDA_DEVICES)
@torch.inference_mode()
def test_activation(
    activation_fns,
    num_tokens: int,
    d: int,
    dtype: torch.dtype,
    seed: int,
    device: str,
) -> None:
    torch.manual_seed(seed)
    torch.set_default_device(device)
    x = torch.randn(num_tokens, d, dtype=dtype)
    torch_fn, fn, op = activation_fns
    out = fn(torch.empty_like(x), x)
    ref_out = torch_fn(x)
    torch.testing.assert_close(
        out, ref_out, atol=get_default_atol(out), rtol=get_default_rtol(out)
    )

    out = torch.empty_like(x)
    opcheck(op, (out, x))
