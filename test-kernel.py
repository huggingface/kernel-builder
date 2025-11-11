# /// script
# requires-python = ">=3.10"
# dependencies = ["kernels", "torch", "numpy"]
# ///
from kernels import get_local_kernel
import torch
from pathlib import Path

relu = get_local_kernel(Path("examples/relu-metal-cpp/result"), "relu").relu

input = torch.tensor([-1.0, -1.5, 0.0, 2.0, 3.5], device="mps", dtype=torch.float16)
out = relu(input)
ref = torch.relu(input)

assert torch.allclose(out, ref), f"Float16 failed: {out} != {ref}"

print(out.cpu().numpy())
print(ref.cpu().numpy())

print("PASS")
# [0.  0.  0.  2.  3.5]
# [0.  0.  0.  2.  3.5]
# PASS
