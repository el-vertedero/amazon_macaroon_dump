#!/bin/sh
set -eu
SOURCE_FILE="${STATE_DIRECTORY}/count"
COUNTER_FILE="${RUNTIME_DIRECTORY}/boot_counter"
if [ -f "$SOURCE_FILE" ]; then
    COUNT=$(cat "$SOURCE_FILE")
    COUNT=$((COUNT + 1))
    [ "$COUNT" -gt 100 ] && COUNT=1
else
    COUNT=1
fi
echo "$COUNT" > "$SOURCE_FILE" || exit 1
chmod 644 "$SOURCE_FILE"
echo "$COUNT" > "$COUNTER_FILE" || exit 1
chsmack -a "_" "$RUNTIME_DIRECTORY"
chsmack -a "_" "$COUNTER_FILE"
chmod 444 "$COUNTER_FILE"
sync "$COUNTER_FILE"
