#!/usr/bin/env bash

set -euo pipefail

# Konfiguration (Standardwerte)
TARGET_URL="${TARGET_URL:-https://foreverdb.docker.alexbangert.dev/imports/forevercollect}"
FILE_PATH="${1:-/home/alex/cloud/Games/WoW/_classic_era_/WTF/Account/112598966#2/SavedVariables/ForeverCollect.lua}"
FIELD_NAME="${FIELD_NAME:-file}"

# Validierung
if [[ -z "$FILE_PATH" ]]; then
  echo "Fehler: Kein Dateipfad angegeben." >&2
  echo "Nutzung: $0 <pfad-zur-datei>" >&2
  exit 1
fi

if [[ ! -f "$FILE_PATH" ]]; then
  echo "Fehler: Datei '$FILE_PATH' existiert nicht oder ist kein regulärer Pfad." >&2
  exit 1
fi

# Upload durchführen
echo "Sende '$FILE_PATH' an $TARGET_URL..."

curl --fail --location \
  --form "${FIELD_NAME}=@\"${FILE_PATH}\"" \
  "$TARGET_URL"

echo -e "\nUpload erfolgreich abgeschlossen."
