#!/usr/bin/env bash

set -euo pipefail

TARGET="/home/alex/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_classic_era_/Interface/AddOns/ForeverCollect"

mkdir -p "$TARGET"
rm -rf "$TARGET/Core" "$TARGET/Modules"
cp ForeverCollect.* "$TARGET"
cp -r Core Modules "$TARGET"
