#!/bin/bash

mkfs.jffs2 --root=./mtd4 --output=./mtd4_new.bin --eraseblock=64KiB --pad=3342336 --big-endian --cleanmarker=0x0C
