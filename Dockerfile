FROM nixos/nix:2.18.8

# default build args
ARG MAX_JOBS=4
ARG CORES=4
ARG REV="unknown"

RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf \
    && echo "max-jobs = $MAX_JOBS" >> /etc/nix/nix.conf \
    && echo "cores = $CORES" >> /etc/nix/nix.conf \
    && nix profile install nixpkgs#cachix \
    && cachix use kernel-builder

WORKDIR /kernelcode
COPY . /etc/kernel-builder/

ENV MAX_JOBS=${MAX_JOBS}
ENV CORES=${CORES}
ENV REV=${REV}

RUN mkdir -p /etc/kernelcode && \
    cat <<'EOF' > /etc/kernelcode/entry.sh
#!/bin/sh
echo "Building Torch Extension Bundle"

nix build \
    --impure \
    --max-jobs $MAX_JOBS \
    -j $CORES \
    --expr 'with import /etc/kernel-builder; lib.x86_64-linux.buildTorchExtensionBundle { path = /kernelcode; rev = $REV; }' \
    -L

echo "Build completed. Copying results to /kernelcode/build-output/"

mkdir -p /kernelcode/build-output
cp -r --dereference ./result/* /kernelcode/build-output/
chmod -R u+w /kernelcode/build-output

echo 'Done'
EOF

RUN chmod +x /etc/kernelcode/entry.sh

ENTRYPOINT ["/etc/kernelcode/entry.sh"]
