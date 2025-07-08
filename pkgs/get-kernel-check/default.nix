{ makeSetupHook, python3 }:

makeSetupHook {
  name = "get-kernel-check-hook";
  propagatedBuildInputs = [
    (python3.withPackages (ps: with ps; [ kernels ]))
  ];
} ./get-kernel-check-hook.sh
