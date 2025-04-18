from typing import Optional

import torch

from ._ops import ops
from .opchecks import opchecks


def relu(x: torch.Tensor, out: Optional[torch.Tensor] = None) -> torch.Tensor:
    if out is None:
        out = torch.empty_like(x)
    ops.relu(out, x)
    return out


__all__ = ["opchecks", "ops", "relu"]
