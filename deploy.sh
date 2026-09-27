#!/usr/bin/env bash

set -euo pipefail

WOW_DIR="/home/alex/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft"
# _classic_era_ = Classic Era (1.15.x), _classic_beta_ = Forever (1.60.x); see "$WOW_DIR/.build.info"
CLIENTS=(_classic_era_ _classic_beta_)

for client in "${CLIENTS[@]}"; do
    if [[ ! -d "$WOW_DIR/$client" ]]; then
        echo "skip $client (not installed)"
        continue
    fi
    TARGET="$WOW_DIR/$client/Interface/AddOns/ForeverCollect"
    mkdir -p "$TARGET"
    rm -rf "$TARGET/Core" "$TARGET/Modules" "$TARGET/Data"
    cp ForeverCollect.* "$TARGET"
    cp -r Core Modules Data "$TARGET"
    echo "deployed to $client"
done
