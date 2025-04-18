import torch

opchecks = {
    "relu": [
        (
            torch.randn((32, 64), dtype=torch.float32, device="cuda"),
            torch.randn((32, 64), dtype=torch.float32, device="cuda"),
        )
    ]
}
