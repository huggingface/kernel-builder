"""Kernel test utils"""

import itertools
import random
import unittest
from numbers import Number
from typing import Any, Dict, List, NamedTuple, Optional, Sequence, Tuple, Union

import pytest
import torch
from torch._prims_common import TensorLikeType

# For now, disable "test_aot_dispatch_dynamic" since there are some
# bugs related to this test in PyTorch 2.4.
DEFAULT_OPCHECK_TEST_UTILS: Tuple[str, ...] = (
    "test_schema",
    "test_autograd_registration",
    "test_faketensor",
)

ALL_OPCHECK_TEST_UTILS: Tuple[str, ...] = (
    "test_schema",
    "test_autograd_registration",
    "test_faketensor",
    "test_aot_dispatch_dynamic",
)


# Copied/modified from torch._refs.__init__.py
def fp8_allclose(
    a: TensorLikeType,
    b: TensorLikeType,
    rtol: float = 1e-05,
    atol: float = 1e-08,
    equal_nan: bool = False,
) -> bool:
    """
    Reference implementation of torch.allclose
    """
    torch._refs._check_close_args(name="torch.allclose", a=a, b=b, rtol=rtol, atol=atol)

    return bool(
        torch.all(
            torch.isclose(
                a.double(), b.double(), rtol=rtol, atol=atol, equal_nan=equal_nan
            )
        ).item()
    )


# A special version of op check that has a restricted default set of test_utils
# and a patched version of allclose that supports fp8 types.
def opcheck(
    op: Union[
        torch._ops.OpOverload,
        torch._ops.OpOverloadPacket,
        torch._library.custom_ops.CustomOpDef,
    ],
    args: Tuple[Any, ...],
    kwargs: Optional[Dict[str, Any]] = None,
    *,
    test_utils: Union[str, Sequence[str]] = ALL_OPCHECK_TEST_UTILS,
    raise_exception: bool = True,
    cond: bool = True
) -> Dict[str, str]:
    with unittest.mock.patch("torch.allclose", new=fp8_allclose):
        return (
            torch.library.opcheck(
                op, args, kwargs, test_utils=test_utils, raise_exception=raise_exception
            )
            if cond
            else {}
        )
