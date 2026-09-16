#!/usr/bin/env bash

set -euo pipefail

# Konfiguration (Standardwerte)
TARGET_URL="${TARGET_URL:-https://foreverdb.docker.alexbangert.dev/imports/forevercollect}"
FILE_PATH="${1:-/home/alex/cloud/Games/WoW/_classic_era_/WTF/Account/112598966#2/SavedVariables/ForeverCollect.lua}"
FIELD_NAME="${FIELD_NAME:-file}"
WOW_PROCESS_PATTERN="${WOW_PROCESS_PATTERN:-WoWClassic\.exe}"
BACKUP_PATH="${FILE_PATH}.bak"

wow_is_running() {
  pgrep -f "$WOW_PROCESS_PATTERN" >/dev/null 2>&1
}

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

# Nach erfolgreichem Upload die SavedVariables entfernen, damit die nächste
# Sitzung mit leerer Datenbank startet – aber nur, wenn WoW nicht läuft,
# da der Client die Datei sonst beim Beenden wieder überschreibt.
if wow_is_running; then
  echo "WoW läuft noch – '$FILE_PATH' und '$BACKUP_PATH' bleiben erhalten."
  exit 0
fi

rm -f -- "$FILE_PATH" "$BACKUP_PATH"
echo "WoW läuft nicht – '$FILE_PATH' und '$BACKUP_PATH' wurden gelöscht."
