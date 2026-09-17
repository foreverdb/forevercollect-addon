#!/usr/bin/env bash

set -euo pipefail

# Lädt die ForeverCollect-SavedVariables eines Clients zum Ingress hoch.
#
#   ./upload.sh              # Forever (_classic_beta_)
#   ./upload.sh era          # Classic Era (_classic_era_)
#   ./upload.sh forever /pfad/zu/ForeverCollect.lua
#
# Client-Ordner und Prozessnamen siehe "$WOW_DIR/.build.info".

TARGET_URL="${TARGET_URL:-https://foreverdb.docker.alexbangert.dev/imports/forevercollect}"
FIELD_NAME="${FIELD_NAME:-file}"
WOW_DIR="${WOW_DIR:-/home/alex/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft}"

CLIENT="${1:-forever}"
case "$CLIENT" in
  forever|beta) CLIENT_DIR="_classic_beta_"; WOW_PROCESS_PATTERN="WowB\.exe" ;;
  era|classic)  CLIENT_DIR="_classic_era_";  WOW_PROCESS_PATTERN="WowClassic\.exe" ;;
  *)
    echo "Fehler: Unbekannter Client '$CLIENT' (erwartet: forever, era)." >&2
    exit 1
    ;;
esac

if [[ -n "${2:-}" ]]; then
  FILE_PATH="$2"
else
  # Erstes Account-Verzeichnis des Clients (je Client existiert genau eines).
  ACCOUNT_DIR="$(find "$WOW_DIR/$CLIENT_DIR/WTF/Account" -mindepth 1 -maxdepth 1 -type d -name '*#*' | head -n 1 || true)"
  if [[ -z "$ACCOUNT_DIR" ]]; then
    echo "Fehler: Kein Account-Verzeichnis unter '$WOW_DIR/$CLIENT_DIR/WTF/Account' gefunden." >&2
    exit 1
  fi
  FILE_PATH="$ACCOUNT_DIR/SavedVariables/ForeverCollect.lua"
fi
BACKUP_PATH="${FILE_PATH}.bak"

wow_is_running() {
  pgrep -fi "$WOW_PROCESS_PATTERN" >/dev/null 2>&1
}

if [[ ! -f "$FILE_PATH" ]]; then
  echo "Fehler: Datei '$FILE_PATH' existiert nicht oder ist kein regulärer Pfad." >&2
  exit 1
fi

if wow_is_running; then
  echo "Hinweis: $CLIENT_DIR läuft noch – der Client schreibt die SavedVariables erst beim Ausloggen/Beenden." >&2
fi

echo "Sende '$FILE_PATH' ($CLIENT) an $TARGET_URL..."

curl --fail --location \
  --form "${FIELD_NAME}=@\"${FILE_PATH}\"" \
  "$TARGET_URL"

echo -e "\nUpload erfolgreich abgeschlossen."

# Nach erfolgreichem Upload die SavedVariables entfernen, damit die nächste
# Sitzung mit leerer Datenbank startet – aber nur, wenn der Client nicht läuft,
# da er die Datei sonst beim Beenden wieder überschreibt.
if wow_is_running; then
  echo "$CLIENT_DIR läuft noch – '$FILE_PATH' und '$BACKUP_PATH' bleiben erhalten."
  exit 0
fi

rm -f -- "$FILE_PATH" "$BACKUP_PATH"
echo "$CLIENT_DIR läuft nicht – '$FILE_PATH' und '$BACKUP_PATH' wurden gelöscht."
