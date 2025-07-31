{
  description = "Flake for ReLU kernel";

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
      torchVersions = defaultVersions: [
        {
          torchVersion = "2.7";
          cudaVersion = "12.8";
          cxx11Abi = true;
          systems = [
            "x86_64-linux"
            "aarch64-linux"
          ];
          upstreamVariant = true;
        }
      ];
    };
}
