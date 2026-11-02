#!/bin/sh
#
# Copyright (c) 2026 Amazon.com, Inc. or its affiliates.  All rights reserved.
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#
# Vega only. Creates the storage dir the daemon reads/writes
# (LocalAutomation.db, account_hash, sync_state, failed_scripts).
#
# Must match LAE_STORAGE_PARENT_DIR / LAE_STORAGE_LEAF_DIR in
# util/include/StoragePaths.h.
PARENT=/var/lib/data
DIR="$PARENT/lae"

# The parent is a mount point we do not own. If it is missing, RequiresMountsFor=
# in the unit did not do its job — fail rather than create a directory over an
# unmounted path, which would strand writes on the rootfs overlay.
#
# This is a directory test, not a mount test: it cannot tell a mounted filesystem
# from a stray directory of the same name. That is deliberate — the mount ordering
# is the unit's job (RequiresMountsFor=), and duplicating it here would just add a
# second thing to keep in sync. The check exists to stop us silently creating the
# store in the wrong place.
if [ ! -d "$PARENT" ]; then
    echo "FATAL: $PARENT missing or not a directory - storage is not mounted"
    exit 1
fi

# Refuse to follow a symlink. Only root can plant one under $PARENT, so the risk is
# low, but chown -R/chmod -R would then recurse into the target as root for free.
if [ -L "$DIR" ]; then
    echo "FATAL: $DIR is a symlink - refusing to chown/chmod through it"
    exit 1
fi

mkdir -p "$DIR" || exit 1
chown -R system:system "$DIR" || exit 1

# Deliberately UNCHANGED from the pre-existing script: 770 recursive.
#
# Review raised that `chmod -R 770` also sets the execute bit on data files and widens the
# 0600 AccountLifecycleManager gives account_hash. Both are true and both are cosmetic --
# SQLite does not care, and the store is system:system inside a 0770 directory, so group
# already has full access either way. A tighter mode was tried and measured working, but
# it is a permission change on a shipping store for hygiene only, and the storage-root
# move is not the change to carry that risk. Left as-is on purpose; tracked separately.
chmod -R 770 "$DIR" || exit 1
exit 0
