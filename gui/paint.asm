; ============================================================
;  Paint - SpheraOS GUI paint with save/load
;  Build: nasm -f bin paint.asm -o PAINT.APP
;  Does NOT modify gui.asm or sdk.inc
;  Save: raw FAT12 write via BIOS int 13h
;  Load: existing API_LOAD
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Paint", 210, 165

GW        equ 25
GH        equ 17
CELLS     equ GW*GH
GRID_Y    equ 10
FLEN      equ 6+CELLS

FAT_BUF   equ 0x4000
ROOT_BUF  equ 0x6000
SEC_BUF   equ 0x8000
CELLS_MEM equ 0x8400
FILE_BUF  equ 0x8800

main:
    push cs
    pop ds
    push cs
    pop es
    cmp ax, MSG_INIT
    je near h_init
    cmp ax, MSG_KEY
    je near h_key
    cmp ax, MSG_DRAW
    je near h_draw
    xor al, al
    retf

; ============================================================
h_init:
    mov di, CELLS_MEM
    mov cx, CELLS
    xor al, al
    rep stosb
    mov byte [col], 15
    mov word [cx_x], 10
    mov word [cy_y], 8
    mov byte [msg], 0
    push ds
    xor ax, ax
    mov ds, ax
    mov al, [0x500]
    pop ds
    mov [drive], al
    xor al, al
    retf

; ============================================================
h_key:
    cmp bh, KEY_UP
    je .up
    cmp bh, KEY_DOWN
    je .dn
    cmp bh, KEY_LEFT
    je .lf
    cmp bh, KEY_RIGHT
    je .rt
    cmp bl, ' '
    je .paint
    cmp bl, 's'
    je .save
    cmp bl, 'S'
    je .save
    cmp bl, 'l'
    je .load
    cmp bl, 'L'
    je .load
    cmp bl, 'c'
    je .clear
    cmp bl, 'C'
    je .clear
    cmp bl, '1'
    jb .no
    cmp bl, '9'
    ja .no
    mov al, bl
    sub al, '0'
    add al, 8
    mov [col], al
.no:
    xor al, al
    retf
.up:
    cmp word [cy_y], 0
    je .same
    dec word [cy_y]
    jmp .redraw
.dn:
    cmp word [cy_y], GH-1
    jae .same
    inc word [cy_y]
    jmp .redraw
.lf:
    cmp word [cx_x], 0
    je .same
    dec word [cx_x]
    jmp .redraw
.rt:
    cmp word [cx_x], GW-1
    jae .same
    inc word [cx_x]
    jmp .redraw
.same:
    xor al, al
    retf
.redraw:
    mov al, 1
    retf
.paint:
    mov ax, [cy_y]
    mov bx, GW
    mul bx
    add ax, [cx_x]
    mov di, CELLS_MEM
    add di, ax
    mov al, [col]
    mov [di], al
    mov al, 1
    retf
.clear:
    mov di, CELLS_MEM
    mov cx, CELLS
    xor al, al
    rep stosb
    mov byte [msg], 0
    mov al, 1
    retf
.save:
    call do_save
    mov al, 1
    retf
.load:
    call do_load
    mov al, 1
    retf

; ============================================================
h_draw:
    mov al, 1
    GUI API_CLEAR
    mov word [i], 0
.pal:
    cmp word [i], 9
    jae .pal_done
    mov ax, [i]
    mov bx, ax
    shl bx, 3
    add bx, 2
    mov cx, 1
    mov al, byte [i]
    add al, 9
    mov dx, 6
    mov si, 6
    GUI API_FILL
    mov al, 15
    mov bx, [i]
    shl bx, 3
    add bx, 5
    mov cx, 8
    mov dx, [i]
    inc dx
    GUI API_NUM
    inc word [i]
    jmp .pal
.pal_done:
    mov al, [col]
    mov bx, 200
    mov cx, 1
    mov dx, 8
    mov si, 6
    GUI API_FILL
    mov word [iy], 0
.row:
    cmp word [iy], GH
    jae .cursor
    mov word [ix], 0
.col:
    cmp word [ix], GW
    jae .next_row
    mov ax, [iy]
    mov bx, GW
    mul bx
    add ax, [ix]
    mov di, CELLS_MEM
    add di, ax
    mov al, [di]
    test al, al
    jz .next
    mov [cc], al
    mov ax, [ix]
    shl ax, 3
    mov [tx], ax
    mov ax, [iy]
    shl ax, 3
    add ax, GRID_Y
    mov [ty], ax
    mov al, [cc]
    mov bx, [tx]
    mov cx, [ty]
    mov dx, 8
    mov si, 8
    GUI API_FILL
.next:
    inc word [ix]
    jmp .col
.next_row:
    inc word [iy]
    jmp .row
.cursor:
    mov ax, [cx_x]
    shl ax, 3
    mov [tx], ax
    mov ax, [cy_y]
    shl ax, 3
    add ax, GRID_Y
    mov [ty], ax
    mov al, 15
    mov bx, [tx]
    mov cx, [ty]
    mov dx, 8
    mov si, 1
    GUI API_FILL
    mov al, 15
    mov bx, [tx]
    mov cx, [ty]
    add cx, 7
    mov dx, 8
    mov si, 1
    GUI API_FILL
    mov al, 15
    mov bx, [tx]
    mov cx, [ty]
    mov dx, 1
    mov si, 8
    GUI API_FILL
    mov al, 15
    mov bx, [tx]
    add bx, 7
    mov cx, [ty]
    mov dx, 1
    mov si, 8
    GUI API_FILL
    movzx si, byte [msg]
    shl si, 1
    mov si, [msg_tab+si]
    test si, si
    jz .hint
    mov bx, 40
    mov cx, 148
    mov dl, 14
    GUI API_STR
.hint:
    mov si, s_hint1
    mov bx, 40
    mov cx, 156
    mov dl, 15
    GUI API_STR
    mov si, s_hint2
    mov bx, 40
    mov cx, 164
    mov dl, 15
    GUI API_STR
    mov al, 1
    retf

; ============================================================
do_load:
    push cs
    pop es
    mov ax, cs
    mov ds, ax
    mov si, fname
    mov di, FILE_BUF
    mov cx, 512
    GUI API_LOAD
    jc .fail
    cmp ax, 6
    jb .fail
    cmp byte [FILE_BUF+0], 'P'
    jne .fail
    cmp byte [FILE_BUF+1], 'B'
    jne .fail
    cmp byte [FILE_BUF+2], 'M'
    jne .fail
    cmp byte [FILE_BUF+3], '1'
    jne .fail
    mov si, FILE_BUF+6
    mov di, CELLS_MEM
    mov cx, CELLS
    rep movsb
    mov byte [msg], 3
    ret
.fail:
    mov byte [msg], 4
    ret

; ============================================================
do_save:
    push ds
    push es
    push cs
    pop ds
    push cs
    pop es

    mov byte [FILE_BUF+0], 'P'
    mov byte [FILE_BUF+1], 'B'
    mov byte [FILE_BUF+2], 'M'
    mov byte [FILE_BUF+3], '1'
    mov byte [FILE_BUF+4], GW
    mov byte [FILE_BUF+5], GH
    mov si, CELLS_MEM
    mov di, FILE_BUF+6
    mov cx, CELLS
    rep movsb

    call read_bpb
    jc .diskerr

    mov ax, [v_rsvd]
    mov cx, [v_spf]
    mov bx, FAT_BUF
    call read_run
    jc .diskerr

    mov ax, [v_root_lba]
    mov cx, [v_root_secs]
    mov bx, ROOT_BUF
    call read_run
    jc .diskerr

    mov ax, cs
    mov ds, ax
    mov si, fname83
    call find_dirent
    test di, di
    jnz .have_ent
    call find_free_dirent
    jc .noent
    mov ax, cs
    mov ds, ax
    mov si, fname83
    mov cx, 11
.cp:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    loop .cp
    sub di, 11
.have_ent:
    mov [dirent_ptr], di

    ; --- ФИКС: правильный атрибут + чистка timestamps ---
    mov byte [di+11], 0x20
    push di
    add di, 12
    mov cx, 14
    xor al, al
.clr:
    mov [di], al
    inc di
    loop .clr
    pop di
    ; ------------------------------------------------

    mov ax, [di+26]
    cmp ax, 2
    jb .no_free
    call free_chain
.no_free:
    mov word [first_clu], 0
    mov word [prev_clu], 0
    mov word [src_ptr], 0
    mov word [rem_bytes], FLEN
.alloc:
    cmp word [rem_bytes], 0
    je .write_done
    call alloc_cluster
    jc .full
    mov [cur_clu], ax
    cmp word [first_clu], 0
    jne .link
    mov [first_clu], ax
    jmp .eof
.link:
    mov dx, ax
    mov ax, [prev_clu]
    call fat_set
.eof:
    mov ax, [cur_clu]
    mov [prev_clu], ax
    mov dx, 0x0FFF
    call fat_set
    mov ax, [cur_clu]
    sub ax, 2
    mov cx, [v_spc]
    mul cx
    add ax, [v_data_lba]
    mov [cluster_lba], ax
    mov word [sec_cnt], 0
.wr:
    mov ax, [sec_cnt]
    cmp ax, [v_spc]
    jae .alloc
    cmp word [rem_bytes], 0
    je .write_done
    mov di, SEC_BUF
    mov cx, 256
    xor ax, ax
    rep stosw
    mov ax, [rem_bytes]
    cmp ax, 512
    jbe .part
    mov ax, 512
.part:
    mov [copy_len], ax
    mov si, FILE_BUF
    add si, [src_ptr]
    mov di, SEC_BUF
    mov cx, [copy_len]
    rep movsb
    mov ax, [cluster_lba]
    add ax, [sec_cnt]
    mov bx, SEC_BUF
    call write_sector
    jc .diskerr
    mov ax, [copy_len]
    add [src_ptr], ax
    sub [rem_bytes], ax
    inc word [sec_cnt]
    jmp .wr

.write_done:
    mov di, [dirent_ptr]
    mov ax, [first_clu]
    mov [di+26], ax
    mov word [di+28], FLEN
    mov word [di+30], 0
    call flush_fat
    jc .diskerr
    call flush_root
    jc .diskerr
    mov byte [msg], 1
    pop es
    pop ds
    ret

.noent:
    mov byte [msg], 6
    pop es
    pop ds
    ret
.full:
    mov byte [msg], 5
    pop es
    pop ds
    ret
.diskerr:
    mov byte [msg], 2
    pop es
    pop ds
    ret

; ============================================================
read_bpb:
    pusha
    push es
    push cs
    pop es
    xor ax, ax
    mov bx, SEC_BUF
    call read_sector
    jc .fail
    mov al, [SEC_BUF+13]
    xor ah, ah
    test ax, ax
    jnz .a1
    mov ax, 1
.a1:
    mov [v_spc], ax
    mov ax, [SEC_BUF+14]
    mov [v_rsvd], ax
    mov al, [SEC_BUF+16]
    xor ah, ah
    mov [v_nfats], ax
    mov ax, [SEC_BUF+17]
    mov [v_rootent], ax
    mov ax, [SEC_BUF+22]
    mov [v_spf], ax
    mov ax, [SEC_BUF+24]
    mov [v_spt], ax
    mov ax, [SEC_BUF+26]
    mov [v_heads], ax
    mov ax, [v_nfats]
    mul word [v_spf]
    add ax, [v_rsvd]
    mov [v_root_lba], ax
    mov ax, [v_rootent]
    shl ax, 5
    add ax, 511
    mov cl, 9
    shr ax, cl
    mov [v_root_secs], ax
    add ax, [v_root_lba]
    mov [v_data_lba], ax
    pop es
    popa
    clc
    ret
.fail:
    pop es
    popa
    stc
    ret

read_sector:
    pusha
    push es
    push cs
    pop es
    mov [v_lba], ax
    mov cx, 3
.try:
    push cx
    mov ax, [v_lba]
    xor dx, dx
    div word [v_spt]
    inc dx
    mov cl, dl
    xor dx, dx
    div word [v_heads]
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah
    mov dl, [cs:drive]
    mov ax, 0x0201
    int 0x13
    pop cx
    jnc .ok
    push cx
    xor ax, ax
    mov dl, [cs:drive]
    int 0x13
    pop cx
    loop .try
    pop es
    popa
    stc
    ret
.ok:
    pop es
    popa
    clc
    ret

write_sector:
    pusha
    push es
    push cs
    pop es
    mov [v_lba], ax
    mov cx, 3
.try:
    push cx
    mov ax, [v_lba]
    xor dx, dx
    div word [v_spt]
    inc dx
    mov cl, dl
    xor dx, dx
    div word [v_heads]
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah
    mov dl, [cs:drive]
    mov ax, 0x0301
    int 0x13
    pop cx
    jnc .ok
    push cx
    xor ax, ax
    mov dl, [cs:drive]
    int 0x13
    pop cx
    loop .try
    pop es
    popa
    stc
    ret
.ok:
    pop es
    popa
    clc
    ret

read_run:
.l:
    jcxz .done
    push cx
    call read_sector
    pop cx
    jc .fail
    inc ax
    add bx, 512
    dec cx
    jmp .l
.done:
    clc
    ret
.fail:
    stc
    ret

write_run:
.l:
    jcxz .done
    push cx
    call write_sector
    pop cx
    jc .fail
    inc ax
    add bx, 512
    dec cx
    jmp .l
.done:
    clc
    ret
.fail:
    stc
    ret

fat_get:
    push bx
    push cx
    mov bx, ax
    shr bx, 1
    add bx, ax
    add bx, FAT_BUF
    mov cx, [bx]
    test al, 1
    jz .even
    shr cx, 4
    jmp .done
.even:
    and cx, 0x0FFF
.done:
    mov ax, cx
    pop cx
    pop bx
    ret

fat_set:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    shr bx, 1
    add bx, ax
    add bx, FAT_BUF
    mov cx, [bx]
    and dx, 0x0FFF
    test al, 1
    jz .even
    and cx, 0x000F
    shl dx, 4
    or cx, dx
    jmp .st
.even:
    and cx, 0xF000
    or cx, dx
.st:
    mov [bx], cx
    pop dx
    pop cx
    pop bx
    pop ax
    ret

find_free_cluster:
    push cx
    push dx
    mov cx, 2
.l:
    cmp cx, 0x0FF0
    jae .full
    mov ax, cx
    call fat_get
    test ax, ax
    jz .got
    inc cx
    jmp .l
.got:
    mov ax, cx
    pop dx
    pop cx
    ret
.full:
    xor ax, ax
    pop dx
    pop cx
    ret

alloc_cluster:
    push dx
    call find_free_cluster
    test ax, ax
    jz .full
    mov dx, 0x0FFF
    call fat_set
    clc
    pop dx
    ret
.full:
    stc
    pop dx
    ret

free_chain:
    push ax
    push dx
.l:
    cmp ax, 2
    jb .done
    cmp ax, 0x0FF8
    jae .done
    push ax
    call fat_get
    mov dx, ax
    pop ax
    push dx
    xor dx, dx
    call fat_set
    pop ax
    jmp .l
.done:
    pop dx
    pop ax
    ret

find_dirent:
    mov di, ROOT_BUF
    mov cx, 224
.l:
    mov al, [di]
    test al, al
    jz .nf
    cmp al, 0xE5
    je .next
    test byte [di+11], 0x08
    jnz .next
    push si
    push di
    push cx
    mov cx, 11
.cmp:
    mov al, [si]
    cmp al, [di]
    jne .mm
    inc si
    inc di
    loop .cmp
    pop cx
    pop di
    pop si
    jmp .found
.mm:
    pop cx
    pop di
    pop si
.next:
    add di, 32
    loop .l
.nf:
    xor di, di
.found:
    ret

find_free_dirent:
    mov di, ROOT_BUF
    mov cx, 224
.l:
    mov al, [di]
    test al, al
    jz .got
    cmp al, 0xE5
    je .got
    add di, 32
    loop .l
    xor di, di
    stc
    ret
.got:
    clc
    ret

flush_fat:
    pusha
    mov ax, [v_rsvd]
    mov [v_lba], ax
    mov cx, [v_nfats]
.copy:
    push cx
    mov ax, [v_lba]
    mov cx, [v_spf]
    mov bx, FAT_BUF
    call write_run
    pop cx
    jc .err
    mov ax, [v_spf]
    add [v_lba], ax
    dec cx
    jnz .copy
    popa
    clc
    ret
.err:
    popa
    stc
    ret

flush_root:
    pusha
    mov ax, [v_root_lba]
    mov cx, [v_root_secs]
    mov bx, ROOT_BUF
    call write_run
    jc .err
    popa
    clc
    ret
.err:
    popa
    stc
    ret

; ============================================================
fname     db "PAINT   SAV"
fname83   db "PAINT   SAV"

msg_tab:
    dw 0, s_saved, s_sfail, s_loaded, s_lfail, s_fulldisk, s_fulldir

s_saved     db "Saved.", 0
s_sfail     db "Save error!", 0
s_loaded    db "Loaded.", 0
s_lfail     db "Load error!", 0
s_fulldisk  db "Disk full!", 0
s_fulldir   db "Dir full!", 0
s_hint1     db "1-9=color Space=paint", 0
s_hint2     db "S=save L=load C=clear", 0

cx_x       dw 10
cy_y       dw 8
col        db 15
msg        db 0
drive      db 0
i          dw 0
ix         dw 0
iy         dw 0
tx         dw 0
ty         dw 0
cc         db 0
dirent_ptr dw 0
first_clu  dw 0
prev_clu   dw 0
cur_clu    dw 0
src_ptr    dw 0
rem_bytes  dw 0
copy_len   dw 0
cluster_lba dw 0
sec_cnt    dw 0

v_lba       dw 0
v_spc       dw 1
v_rsvd      dw 1
v_nfats     dw 2
v_rootent   dw 224
v_spf       dw 9
v_spt       dw 18
v_heads     dw 2
v_root_lba  dw 0
v_root_secs dw 0
v_data_lba  dw 0
