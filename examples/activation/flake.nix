{
  description = "Flake for activation kernels";

  inputs = {
    kernel-builder.url = "path:../..";
  };

  outputs =
    {
      self,
      kernel-builder,
    }:

    kernel-builder.lib.genFlakeOutputs {
      path = ./.;
      rev = self.shortRev or self.dirtyShortRev or self.lastModifiedDate;
      # Example of adding Python test dependencies directly in the flake
      pythonTestDeps = [ "numpy" "pytest-benchmark" ];
    };
}