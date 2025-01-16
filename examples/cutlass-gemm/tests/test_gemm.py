import torch

from cutlass_gemm import cutlass_gemm

def test_gemm():
    A = torch.randn((10, 20), device="cuda", dtype=torch.float32)
    B = torch.randn((20, 30), device="cuda", dtype=torch.float32)
    out = torch.randn((10, 30), device="cuda", dtype=torch.float32)

    cutlass_gemm(out, A, B)

    torch.testing.assert_allclose(out, torch.mm(A, B))
