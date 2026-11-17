#!/bin/bash
set -euo pipefail
SCHEME="${1:-roothide}"
make clean || true
make package THEOS_PACKAGE_SCHEME="$SCHEME" FINALPACKAGE=1
mkdir -p packages
find . -maxdepth 1 -name "*.deb" -exec cp -a {} packages/ \;
