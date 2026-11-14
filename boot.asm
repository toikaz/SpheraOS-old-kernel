; ============================================================
;  SpheraOS boot sector  (FAT12, 1.44 MB floppy)
;
;  Finds KERNEL.BIN in the root directory, follows its FAT
;  cluster chain (so the file may be fragmented), loads it at
;  1000:0000 and jumps there.
;  The boot drive number is passed in DL and also stored at
;  0000:0500 (the SpheraOS kernel reads it from there).
;
;  Build: nasm -f bin boot.asm -o boot.bin
; ============================================================
BITS 16
ORG 0x7C00

    jmp short start
    nop

; ---- BIOS parameter block (standard 1.44 MB floppy) ----
OEMLabel          db "SPHEROS "
BytesPerSector    dw 512
SectorsPerCluster db 1
ReservedSectors   dw 1
NumberOfFATs      db 2
RootEntries       dw 224
TotalSectors      dw 2880
MediaDescriptor   db 0xF0
SectorsPerFAT     dw 9
SectorsPerTrack   dw 18
NumberOfHeads     dw 2
HiddenSectors     dd 0
LargeSectors      dd 0
DriveNumber       db 0
Reserved          db 0
BootSignature     db 0x29
VolumeID          dd 0x53504845
VolumeLabel       db "SPHERAOS   "
FileSystem        db "FAT12   "

; ------------------------------------------------------------
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    cld
    mov [drive], dl
    mov [0x0500], dl
    mov si, msg_boot
    call print

    ; where is the root directory / data area?
    movzx ax, byte [NumberOfFATs]
    mul word [SectorsPerFAT]
    add ax, [ReservedSectors]
    mov [rootlba], ax
    mov ax, [RootEntries]
    add ax, 15
    shr ax, 4                    ; root directory size in sectors
    mov cx, ax
    add ax, [rootlba]
    mov [datalba], ax

    ; read the root directory to 0800:0000
    mov ax, [rootlba]
    mov bx, 0x0800
    mov es, bx
    call read_sectors

    ; look for KERNEL.BIN
    mov ax, 0x0800
    mov es, ax
    xor di, di
    mov cx, [RootEntries]
.find:
    cmp byte [es:di], 0
    je near not_found
    push cx
    push di
    mov si, kname
    mov cx, 11
    repe cmpsb
    pop di
    pop cx
    je .found
    add di, 32
    loop .find
    jmp not_found

.found:
    mov ax, [es:di+26]           ; first cluster
    mov [clu], ax

    ; read the FAT to 0800:0000 (the directory is not needed any more)
    mov ax, [ReservedSectors]
    mov cx, [SectorsPerFAT]
    mov bx, 0x0800
    mov es, bx
    call read_sectors
    mov ax, 0x0800
    mov fs, ax                   ; FS -> FAT
    mov ax, 0x1000
    mov es, ax                   ; ES -> kernel destination

.load:
    mov ax, [clu]
    cmp ax, 0x0FF8
    jae .done
    sub ax, 2
    movzx cx, byte [SectorsPerCluster]
    mul cx
    add ax, [datalba]
    call read_sectors            ; ES advances by 20h per sector

    mov bx, [clu]                ; next cluster = FAT12 entry
    mov ax, bx
    shr ax, 1
    add bx, ax
    mov ax, [fs:bx]
    test byte [clu], 1
    jz .even
    shr ax, 4
    jmp .store
.even:
    and ax, 0x0FFF
.store:
    mov [clu], ax
    jmp .load

.done:
    mov dl, [drive]
    jmp 0x1000:0x0000

; ------------------------------------------------------------
; read_sectors: AX = first LBA, CX = count, ES = destination segment
; (ES is advanced by 20h for every sector read, BX is always 0)
; ------------------------------------------------------------
read_sectors:
    push ax
    push cx
    call read_one
    pop cx
    pop ax
    inc ax
    push ax
    mov ax, es
    add ax, 0x20
    mov es, ax
    pop ax
    loop read_sectors
    ret

read_one:                        ; LBA in AX -> ES:0
    mov di, 5
.retry:
    push ax
    xor dx, dx
    div word [SectorsPerTrack]
    inc dl
    mov cl, dl                   ; sector
    xor dx, dx
    div word [NumberOfHeads]
    mov dh, dl                   ; head
    mov ch, al                   ; cylinder (low 8 bits)
    shl ah, 6
    or cl, ah                    ; cylinder (high 2 bits)
    mov dl, [drive]
    xor bx, bx
    mov ax, 0x0201
    int 0x13
    pop ax
    jnc .ok
    push ax
    xor ax, ax
    int 0x13                     ; reset the controller and retry
    pop ax
    dec di
    jnz .retry
    mov si, msg_disk
    jmp fail
.ok:
    ret

not_found:
    mov si, msg_nf
fail:
    call print
    mov si, msg_key
    call print
    xor ax, ax
    int 0x16
    int 0x19

print:
    lodsb
    test al, al
    jz .d
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp print
.d:
    ret

; ------------------------------------------------------------
kname     db "KERNEL  BIN"
msg_boot  db "SpheraOS: loading kernel...", 13, 10, 0
msg_nf    db "KERNEL.BIN not found.", 13, 10, 0
msg_disk  db "Disk read error.", 13, 10, 0
msg_key   db "Press any key to reboot.", 13, 10, 0
drive     db 0
clu       dw 0
rootlba   dw 0
datalba   dw 0

times 510-($-$$) db 0
dw 0xAA55