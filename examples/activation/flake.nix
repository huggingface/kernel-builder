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
      inherit self;
      path = ./.;
    };
}
