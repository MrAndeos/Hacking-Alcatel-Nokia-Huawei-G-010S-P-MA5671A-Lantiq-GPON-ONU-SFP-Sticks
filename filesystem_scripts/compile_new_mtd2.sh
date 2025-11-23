#!/bin/bash

#!/usr/bin/env bash
# compile_new_mtd2.sh
# Usage:
#   ./compile_new_mtd2.sh original_mtd2.bin new_squashfs.bin OUT_mtd2.bin ROOTFS_START_HEX JFFS2_START_HEX [new_jffs2.bin]
#
# Example:
#   ./compile_new_mtd2.sh mtd2.bin rootfs_new.squashfs mtd2_new.bin 0x127F89 0x410000 new_jffs2.bin

set -euo pipefail

if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
  #echo "Usage: $0 original_mtd2.bin new_squashfs.bin OUT_mtd2.bin ROOTFS_START_HEX JFFS2_START_HEX [new_jffs2.bin]"
  echo "Using default values..."

  ORIG="mtd2.bin"
  NEW_SQ="mtd3_new.bin"
  OUT="mtd2_new.bin"
  ROOTFS_START_HEX="0x127F89"
  JFFS2_START_HEX="0x410000"
  NEW_JFFS2="mtd4_new.bin"
else
  ORIG="$1"
  NEW_SQ="$2"
  OUT="$3"
  ROOTFS_START_HEX="$4"
  JFFS2_START_HEX="$5"
  NEW_JFFS2="${6:-}"
fi


ROOTFS_START=$((ROOTFS_START_HEX))
JFFS2_START=$((JFFS2_START_HEX))

# sanity checks
if [ ! -f "$ORIG" ]; then echo "Original not found: $ORIG"; exit 2; fi
if [ ! -f "$NEW_SQ" ]; then echo "New squash not found: $NEW_SQ"; exit 2; fi

ORIG_SIZE=$(stat -c%s "$ORIG")
NEW_SQ_SIZE=$(stat -c%s "$NEW_SQ")
MAX_ROOTFS_SIZE=$((JFFS2_START - ROOTFS_START))

echo "Original size: $ORIG_SIZE"
echo "New squashfs size: $NEW_SQ_SIZE"
echo "Allowed squashfs max size: $MAX_ROOTFS_SIZE"

if [ "$NEW_SQ_SIZE" -gt "$MAX_ROOTFS_SIZE" ]; then
  echo "ERROR: new squashfs is too big. Shrink it or reconfigure mksquashfs."
  exit 3
fi

# Extract head (kernel + up to ROOTFS_START)
dd if="$ORIG" of="${OUT}.head" bs=1 count=$ROOTFS_START status=none

# If no new JFFS2 image is provided, extract tail from original (from JFFS2_START to EOF)
if [ -z "$NEW_JFFS2" ]; then
  dd if="$ORIG" of="${OUT}.tail" bs=1 skip=$JFFS2_START status=none
else
  if [ ! -f "$NEW_JFFS2" ]; then
    echo "New JFFS2 image not found: $NEW_JFFS2"
    exit 4
  fi
  cp "$NEW_JFFS2" "${OUT}.tail"
fi

# Build new mtd2: head + new_squash + padding up to jffs2 + tail
cat "${OUT}.head" > "$OUT"
cat "$NEW_SQ" >> "$OUT"

# pad between end of new squash and start of jffs2 with 0xFF (matching erased flash)
CUR=$(( $(stat -c%s "$OUT") ))
if [ "$CUR" -lt "$JFFS2_START" ]; then
  PAD=$((JFFS2_START - CUR))
  printf '\xFF%.0s' $(seq 1 $PAD) >> "$OUT"
fi

# append jffs2 (either original or provided)
cat "${OUT}.tail" >> "$OUT"

# Cleanup
rm -f "${OUT}.head" "${OUT}.tail"

echo "Created $OUT (size: $(stat -c%s "$OUT"))"
if [ -n "$NEW_JFFS2" ]; then
  echo "→ JFFS2 area replaced with: $NEW_JFFS2"
else
  echo "→ Original JFFS2 area preserved."
fi

