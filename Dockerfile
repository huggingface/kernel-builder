FROM nixos/nix:2.18.8

RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf \
    && nix profile install nixpkgs#cachix \
    && cachix use kernel-builder

WORKDIR /kernelcode
COPY . /etc/kernel-builder/

ENTRYPOINT ["/bin/sh", "-c", "nix build --impure --expr 'with import /etc/kernel-builder; lib.x86_64-linux.buildTorchExtensionBundle /kernelcode' -L"]
