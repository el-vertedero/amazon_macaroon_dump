#!/bin/sh

BOOTID="$(< /proc/sys/kernel/random/boot_id tr -d '-')"
read UP IDLE < /proc/uptime

OUTDIR="/var/log/reboot"
OUT="${OUTDIR}/reboot_log_${BOOTID}.log"

# if more than 5 logs in /var/log/reboot, then clear the directory 
if [ $(find "$OUTDIR" -mindepth 1 -maxdepth 1 | wc -l) -gt 5 ]; then
    rm -rf "$OUTDIR"/*
fi

echo "BootId: ${BOOTID}" > "$OUT"
echo "Uptime: ${UP}s" >> "$OUT"
echo -e "IdleTime: ${IDLE}s\n" >> "$OUT"

echo "[Logs]" >> "$OUT"
SYSTEMD_COLORS=false journalctl --no-pager >> "$OUT"

if grep -q -e '-- No entries --' "$OUT"; then
    echo "Smartbox flushed the journal before reboot logs could be read/written to this file. Please check other journal logs to find reboot reason."
fi

sync
