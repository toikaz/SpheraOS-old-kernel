#!/bin/bash
# SpheraOS build script
#   1. Assembles boot.asm, kernel.asm, and all *.asm from the root into asm/
#   2. Also assembles any *.asm found inside asm/ (if present)
#   3. Assembles all *.asm from gui/ into .app files
#   4. Creates floppy.img (FAT12 1.44MB), writes boot sector from asm/boot.bin
#   5. Copies files into the image:
#         asm/kernel.bin       -> KERNEL.BIN
#         asm/<name>.bin       -> <NAME>.BIN   (except boot.bin)
#         asm/<name>.app       -> <NAME>.APP   (GUI programs)
#         examples/*           -> <UPPERCASE>
#   6. Launches QEMU
set -e

# Always work from the directory containing this script
cd "$(dirname "$0")"

ASM_DIR=asm
EXAMPLES_DIR=examples
GUI_DIR=gui
IMG=floppy.img

mkdir -p "$ASM_DIR"

# ---- 1. Build phase ----
echo "[*] boot.asm   -> $ASM_DIR/boot.bin"
nasm -f bin boot.asm   -o "$ASM_DIR/boot.bin"

echo "[*] kernel.asm -> $ASM_DIR/kernel.bin"
nasm -f bin kernel.asm -o "$ASM_DIR/kernel.bin"

# Build all other .asm files in the root directory
for src in *.asm; do
    [ -f "$src" ] || continue
    base=$(basename "$src" .asm)
    case "$base" in boot|kernel) continue ;; esac
    echo "[*] $src -> $ASM_DIR/$base.bin"
    nasm -f bin "$src" -o "$ASM_DIR/$base.bin"
done

# Build any .asm files inside the asm/ directory (if present)
for src in "$ASM_DIR"/*.asm; do
    [ -f "$src" ] || continue
    base=$(basename "$src" .asm)
    echo "[*] $src -> $ASM_DIR/$base.bin"
    nasm -f bin "$src" -o "$ASM_DIR/$base.bin"
done

# ---- NEW: Build GUI programs from gui/ directory ----
if [ -d "$GUI_DIR" ]; then
    for src in "$GUI_DIR"/*.asm; do
        [ -f "$src" ] || continue
        base=$(basename "$src" .asm)
        echo "[*] $src -> $ASM_DIR/$base.app"
        # -I flags help nasm find sdk.inc if it's in the root or in gui/
        nasm -f bin -I "$GUI_DIR/" -I . "$src" -o "$ASM_DIR/$base.app"
    done
fi

# ---- 2. Create image ----
echo "[*] Creating $IMG (FAT12, 1.44MB, label: SpheraOS)"
dd if=/dev/zero of="$IMG" bs=512 count=2880 2>/dev/null
mkfs.fat -F 12 -n "SpheraOS" "$IMG" >/dev/null
dd if="$ASM_DIR/boot.bin" of="$IMG" conv=notrunc 2>/dev/null

# ---- 3. Populate image ----
if command -v mcopy >/dev/null 2>&1; then
    # Kernel
    mcopy -o -i "$IMG" "$ASM_DIR/kernel.bin" ::KERNEL.BIN
    echo "[+] KERNEL.BIN"

    # All other .bin files from asm/ (except boot.bin and kernel.bin)
    for f in "$ASM_DIR"/*.bin; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        case "$base" in boot.bin|kernel.bin) continue ;; esac
        name=$(echo "$base" | tr 'a-z' 'A-Z')
        mcopy -o -i "$IMG" "$f" "::$name"
        echo "[+] $name"
    done

    # ---- NEW: Copy GUI .app files ----
    for f in "$ASM_DIR"/*.app; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        name=$(echo "$base" | tr 'a-z' 'A-Z')
        mcopy -o -i "$IMG" "$f" "::$name"
        echo "[+] $name"
    done

    # Everything from examples/
    if [ -d "$EXAMPLES_DIR" ]; then
        for f in "$EXAMPLES_DIR"/*; do
            [ -f "$f" ] || continue
            name=$(basename "$f" | tr 'a-z' 'A-Z')
            mcopy -o -i "$IMG" "$f" "::$name"
            echo "[+] $name"
        done
    fi

    echo
    echo "=== Image contents ==="
    mdir -i "$IMG" ::
else
    echo "[!] mtools not found, falling back to mount (requires sudo)"
    mkdir -p mnt
    sudo mount -o loop "$IMG" mnt

    sudo cp "$ASM_DIR/kernel.bin" mnt/KERNEL.BIN
    echo "[+] KERNEL.BIN"

    for f in "$ASM_DIR"/*.bin; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        case "$base" in boot.bin|kernel.bin) continue ;; esac
        name=$(echo "$base" | tr 'a-z' 'A-Z')
        sudo cp "$f" "mnt/$name"
        echo "[+] $name"
    done

    # ---- NEW: Copy GUI .app files (fallback) ----
    for f in "$ASM_DIR"/*.app; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        name=$(echo "$base" | tr 'a-z' 'A-Z')
        sudo cp "$f" "mnt/$name"
        echo "[+] $name"
    done

    if [ -d "$EXAMPLES_DIR" ]; then
        for f in "$EXAMPLES_DIR"/*; do
            [ -f "$f" ] || continue
            name=$(basename "$f" | tr 'a-z' 'A-Z')
            sudo cp "$f" "mnt/$name"
            echo "[+] $name"
        done
    fi

    echo
    echo "=== Image contents ==="
    ls -la mnt
    sudo umount mnt
fi

# ---- 4. Launch ----
echo
echo "[*] Starting QEMU..."
qemu-system-i386 -drive format=raw,file="$IMG",if=floppy -boot a
