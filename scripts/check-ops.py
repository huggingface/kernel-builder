import argparse
import importlib
from types import ModuleType
from typing import Any, Dict, List

import torch
from torch.library import opcheck


def check_ops(module: ModuleType, checks: Dict[str, List[Any]]):
    if not hasattr(torch._C, "_jit_get_all_schemas"):
        return

    if not hasattr(module, "opchecks"):
        print("🛑 Module does not have opchecks")
        return

    namespace = getattr(module, "_ops").ops.name
    schemas = [
        schema
        for schema in torch._C._jit_get_all_schemas()
        if schema.name.startswith(namespace)
    ]
    for schema in schemas:
        op_name = schema.name.removeprefix(f"{namespace}::")
        opchecks = module.opchecks.get(op_name, None)
        if opchecks is None:
            print(f"🛑 No operator check found for {op_name}")
        else:
            for check in opchecks:
                opcheck(getattr(module._ops.ops, op_name), check)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Check operations in a module.")
    parser.add_argument("module_name", help="The module to check operations for.")
    args = parser.parse_args()

    module = importlib.import_module(args.module_name)
    check_ops(module, None)
