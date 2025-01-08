import torch
from . import {{ ext_name }}
ops = torch.ops.{{ ext_name }}

def add_op_namespace_prefix(op_name: str):
    """
    Prefix op by namespace.
    """
    return f"{{ ext_name }}::{op_name}"
