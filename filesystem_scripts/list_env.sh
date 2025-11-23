#!/bin/bash
# list_env.sh — list all variables from a U-Boot environment (with 4-byte CRC)
# Stops reading at the double null terminator.
# Usage: ./list_env.sh mtd1.bin

set -e
FILE="$1"

if [ -z "$FILE" ]; then
    echo "Usage: $0 mtd1.bin"
    exit 1
fi

# Skip first 4 bytes (CRC)
dd if="$FILE" bs=1 skip=4 status=none | \
awk '
    BEGIN { RS=""; ORS="" }
    {
        # Read the entire binary blob
        data=$0
        # Find position of double null (0x00 0x00)
        pos = index(data, "\x00\x00")
        if (pos > 0)
            data = substr(data, 1, pos - 1)
        # Split remaining section by nulls
        n = split(data, arr, "\x00")
        for (i = 1; i <= n; i++)
            if (arr[i] != "")
                print "• " arr[i] "\n"
    }
'
