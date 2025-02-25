import torch
import torch.nn.functional as F

import relu


def test_relu():
    x = torch.randn(1024, 1024, dtype=torch.float32, device="cuda")
    torch.testing.assert_allclose(F.relu(x), relu.relu(x))
