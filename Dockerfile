FROM nixos/nix:2.18.8

# default build args
ARG MAX_JOBS=4
ARG CORES=4

RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf \
    && echo "max-jobs = $MAX_JOBS" >> /etc/nix/nix.conf \
    && echo "cores = $CORES" >> /etc/nix/nix.conf \
    && nix profile install nixpkgs#cachix \
    && cachix use kernel-builder

WORKDIR /kernelcode
COPY . /etc/kernel-builder/

ENV MAX_JOBS=${MAX_JOBS}
ENV CORES=${CORES}
ENTRYPOINT ["/bin/sh", "-c", "nix build --impure --max-jobs $MAX_JOBS -j $CORES --expr 'with import /etc/kernel-builder; lib.x86_64-linux.buildTorchExtensionBundle /kernelcode' -L"]
