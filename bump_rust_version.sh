#!/usr/bin/env bash

set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: $0 <major|minor|patch>"
  exit 1
fi

VERSION_LEVEL=$1

if [[ ! "$VERSION_LEVEL" =~ ^(major|minor|patch)$ ]]; then
  echo "Error: Version level must be major, minor, or patch"
  exit 1
fi

cargo install cargo-workspaces

cargo workspaces version "$VERSION_LEVEL" --yes --no-git-commit

version=$(cargo metadata --format-version=1 --no-deps | jq -r '.packages[0].version')
echo "version=$version" >> $GITHUB_OUTPUT

files_changed=$(git diff --name-only | grep 'Cargo.toml' | yq -ojson -I0 -e 'split(" ")')
echo "files_changed=$files_changed" >> $GITHUB_OUTPUT
