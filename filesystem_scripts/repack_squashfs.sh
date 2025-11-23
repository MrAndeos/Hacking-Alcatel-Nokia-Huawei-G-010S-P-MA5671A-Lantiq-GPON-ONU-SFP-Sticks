#!/bin/bash

mksquashfs mtd3/ mtd3_new.bin -comp xz -b 262144 -noappend
