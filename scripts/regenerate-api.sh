#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 scripts/generate.py
swift build --package-path Packages/SpaceWorksAPI
# The OpenAPIGenerator SPM build plugin emits Swift into .build, never source control.
