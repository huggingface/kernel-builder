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

RUN mkdir -p /etc/kernelcode && \
    cat <<'EOF' > /etc/kernelcode/entry.sh
#!/bin/sh
echo "Building Torch Extension Bundle"

# Check if kernelcode is a git repo and get hash if possible
if [ -d "/kernelcode/.git" ]; then
  # Mark git as safe to allow commands
  git config --global --add safe.directory /kernelcode

  # Try to get git revision
  REV=$(git rev-parse --short=8 HEAD)
  
  # Check if working directory is dirty
  if [ -n "$(git status --porcelain 2)" ]; then
    REV="${REV}-dirty"
  fi
else
  # Generate random material if not a git repo
  REV=$(dd if=/dev/urandom status=none bs=1 count=10 2>/dev/null | base32 | tr '[:upper:]' '[:lower:]' | head -c 10)
fi

echo "Building with rev $REV"

nix build \
    --impure \
    --max-jobs $MAX_JOBS \
    -j $CORES \
    --expr "with import /etc/kernel-builder; lib.x86_64-linux.buildTorchExtensionBundle { path = /kernelcode; rev = \"$REV\"; }" \
    -L

echo "Build completed. Copying results to /kernelcode/build/"

mkdir -p /kernelcode/build
cp -r --dereference ./result/* /kernelcode/build/
chmod -R u+w /kernelcode/build

echo 'Done'
EOF

RUN chmod +x /etc/kernelcode/entry.sh

ENTRYPOINT ["/etc/kernelcode/entry.sh"]