#!/usr/bin/env bash

set -euo pipefail
# shopt -s globstar

OUTDIR="$(node -p 'require("./docs/config.js").outputDir')"

if [ ! -d node_modules ]; then
  npm ci
fi

rm -rf "$OUTDIR"

export SHELL=/bin/bash

# Check if forge is installed
if ! command -v forge &> /dev/null; then
  (curl -L https://foundry.paradigm.xyz | bash) || true
  echo $HOME
  source $HOME/.bashrc
  $HOME/.foundry/bin/foundryup
  export PATH="$PATH:$HOME/.foundry/bin"
  echo "export PATH=$PATH" >> $HOME/.bashrc
fi

forge install

hardhat docgen

node scripts/gen-nav.js "$OUTDIR" > "$OUTDIR/../nav.adoc"