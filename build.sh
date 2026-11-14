#!/bin/bash
# SpheraOS build script: boot.asm (your loader) + kernel.asm -> floppy.img -> QEMU
set -e

nasm -f bin boot.asm   -o boot.bin
nasm -f bin kernel.asm -o kernel.bin

dd if=/dev/zero of=floppy.img bs=512 count=2880 2>/dev/null
mkfs.fat -F 12 -n "MYOS" floppy.img
dd if=boot.bin of=floppy.img conv=notrunc 2>/dev/null

if command -v mcopy >/dev/null 2>&1; then
    # no sudo needed (package: mtools)
    mcopy -i floppy.img kernel.bin ::KERNEL.BIN
    for f in examples/*.plb; do
        mcopy -i floppy.img "$f" "::$(basename "$f" | tr a-z A-Z)"
    done
    mdir -i floppy.img ::
else
    mkdir -p mnt
    sudo mount -o loop floppy.img mnt
    sudo cp kernel.bin mnt/KERNEL.BIN
    for f in examples/*.plb; do
        sudo cp "$f" "mnt/$(basename "$f" | tr a-z A-Z)"
    done
    ls mnt
    sudo umount mnt
fi

qemu-system-i386 -drive format=raw,file=floppy.img,if=floppy -boot a
