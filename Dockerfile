FROM nixos/nix:2.18.8
# default build args
ARG MAX_JOBS=4
ARG CORES=4
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf \
    && echo "max-jobs = $MAX_JOBS" >> /etc/nix/nix.conf \
    && echo "cores = $CORES" >> /etc/nix/nix.conf \
    && nix profile install nixpkgs#cachix nixpkgs#git-lfs \
    && cachix use kernel-builder
WORKDIR /kernelcode
COPY . /etc/kernel-builder/
ENV MAX_JOBS=${MAX_JOBS}
ENV CORES=${CORES}
RUN mkdir -p /etc/kernelcode && \
    cat <<'EOF' > /etc/kernelcode/cli.sh
#!/bin/sh
set -e

# Default values
BUILD_URL=""
DEV_SHELL=0
HELP=0

# CLI usage function
function show_usage {
  echo "Kernel Builder CLI"
  echo ""
  echo "Usage: docker run [docker-options] kernel-builder:dev [command] [options]"
  echo ""
  echo "Commands:"
  echo "  build               Build the kernel extension (default if no command specified)"
  echo "  dev                 Start a development shell"
  echo "  fetch [URL]         Clone and build from a Git URL"
  echo "  help                Show this help message"
  echo ""
  echo "Options:"
  echo "  --jobs, -j NUMBER   Set maximum number of parallel jobs (default: $MAX_JOBS)"
  echo "  --cores, -c NUMBER  Set number of cores per job (default: $CORES)"
  echo ""
  echo "Examples:"
  echo "  docker run -v \$(pwd):/kernelcode kernel-builder:dev build"
  echo "  docker run -it -v \$(pwd):/kernelcode kernel-builder:dev dev"
  echo "  docker run kernel-builder:dev fetch https://huggingface.co/user/repo.git"
}

# Function to generate a basic flake.nix if it doesn't exist
function ensure_flake_exists {
  if [ ! -f "/kernelcode/flake.nix" ]; then
    echo "No flake.nix found, creating a basic one..."
    cat <<'FLAKE_EOF' > /kernelcode/flake.nix
{
  description = "Flake for Torch kernel extension";

  inputs = {
    kernel-builder.url = "github:huggingface/kernel-builder";
  };

  outputs = { self, kernel-builder, }:
    kernel-builder.lib.genFlakeOutputs {
      path = ./.;
      rev = self.shortRev or self.dirtyShortRev or self.lastModifiedDate;
    };
}
FLAKE_EOF
    echo "flake.nix created. You can customize it as needed."
  else
    echo "flake.nix already exists, skipping creation."
  fi
}

# Function to build the extension
function build_extension {
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
  
  # Check for flake.nix or create one
  ensure_flake_exists
  
  # Pure bundle build
  echo "Building with Nix..."
  nix build \
    . \
    --max-jobs $MAX_JOBS \
    -j $CORES \
    -L
  
  echo "Build completed. Copying results to /kernelcode/build/"
  mkdir -p /kernelcode/build
  cp -r --dereference ./result/* /kernelcode/build/
  chmod -R u+w /kernelcode/build
  echo 'Done'
}

# Function to start a dev shell
function start_dev_shell {
  echo "Starting development shell..."
  # Check for flake.nix or create one
  ensure_flake_exists
  /root/.nix-profile/bin/nix develop
}

# Function to fetch and build from URL
function fetch_and_build {
  if [ -z "$1" ]; then
    echo "Error: URL required for fetch command"
    show_usage
    exit 1
  fi
  
  echo "Fetching code from $1"
  rm -rf /kernelcode/* /kernelcode/.* 2>/dev/null || true
  git lfs install
  git clone "$1" /kernelcode
  cd /kernelcode
  build_extension
}

# Parse arguments
COMMAND="build"  # Default command
ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    build|dev|fetch|help)
      COMMAND="$1"
      shift
      ;;
    --jobs|-j)
      MAX_JOBS="$2"
      shift 2
      ;;
    --cores|-c)
      CORES="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

# Execute the command
case $COMMAND in
  build)
    build_extension
    ;;
  dev)
    start_dev_shell
    ;;
  fetch)
    fetch_and_build "${ARGS[0]}"
    ;;
  help)
    show_usage
    ;;
  *)
    echo "Unknown command: $COMMAND"
    show_usage
    exit 1
    ;;
esac
EOF

RUN chmod +x /etc/kernelcode/cli.sh
ENTRYPOINT ["/etc/kernelcode/cli.sh"]