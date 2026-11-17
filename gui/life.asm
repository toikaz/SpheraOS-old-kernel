; ============================================================
;  life.asm - Conway's Game of Life for SpheraOS GUI
;  nasm -f bin -I gui/ life.asm -o asm/life.app
;  Arrows = cursor, Enter = toggle cell, Space = pause,
;  R = random field, C = clear, +/- = speed.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Life", 288, 152

COLS  equ 36
ROWS  equ 18
NCELL equ COLS*ROWS

entry:
    push cs
    pop ds
    push cs
    pop es
    cmp ax, MSG_INIT
    je near h_init
    cmp ax, MSG_TICK
    je near h_tick
    cmp ax, MSG_KEY
    je near h_key
    cmp ax, MSG_DRAW
    je near h_draw
    xor al, al
    retf

h_init:
    mov word [gen], 0
    mov byte [paused], 0
    mov byte [speed], 3
    mov byte [tickc], 0
    mov byte [cur], 0
    mov byte [curx], COLS/2
    mov byte [cury], ROWS/2
    call randomize
    xor al, al
    retf

; fill g1 with random cells, g2 with zeros
randomize:
    mov di, g1
    mov cx, NCELL
.r:
    mov bx, 2
    GUI API_RND
    mov [di], al
    inc di
    loop .r
    mov di, g2
    mov cx, NCELL
    xor al, al
    rep stosb
    call count_pop
    ret

clear_all:
    mov di, g1
    mov cx, NCELL
    xor al, al
    rep stosb
    mov di, g2
    mov cx, NCELL
    rep stosb
    mov word [gen], 0
    mov word [pnum], 0
    mov byte [cur], 0
    ret

count_pop:
    mov si, g1
    cmp byte [cur], 0
    je .src
    mov si, g2
.src:
    mov cx, NCELL
    xor bx, bx
.l:
    cmp byte [si], 0
    je .n
    inc bx
.n:
    inc si
    loop .l
    mov [pnum], bx
    ret

; ------------------------------------------------------------
; one generation: source -> destination, then swap buffers
; ------------------------------------------------------------
step:
    cmp byte [cur], 0
    jne .s2
    mov word [srcp], g1
    mov word [dstp], g2
    jmp .sc
.s2:
    mov word [srcp], g2
    mov word [dstp], g1
.sc:
    mov word [pnum], 0
    mov word [gy], 0
.yl:
    cmp word [gy], ROWS
    jae .ydone
    mov word [gx], 0
.xl:
    cmp word [gx], COLS
    jae .xdone
    ; index of current cell
    mov ax, [gy]
    mov bp, COLS
    mul bp
    add ax, [gx]
    mov [idx], ax

    ; count the 8 neighbours
    mov byte [nb], 0
    mov word [dy_], -1
.dyl:
    mov word [dx_], -1
.dxl:
    mov bx, [gx]
    add bx, [dx_]
    cmp bx, 0
    jl .nn
    cmp bx, COLS
    jge .nn
    mov di, [gy]
    add di, [dy_]
    cmp di, 0
    jl .nn
    cmp di, ROWS
    jge .nn
    cmp bx, [gx]
    jne .nchk
    cmp di, [gy]
    je .nn
.nchk:
    mov ax, di
    mov bp, COLS
    mul bp
    add ax, bx
    mov di, [srcp]
    add di, ax
    cmp byte [di], 0
    je .nn
    inc byte [nb]
.nn:
    inc word [dx_]
    cmp word [dx_], 1
    jle .dxl
    inc word [dy_]
    cmp word [dy_], 1
    jle .dyl

    ; life rules
    mov di, [srcp]
    add di, [idx]
    mov al, [di]
    mov dl, 0
    test al, al
    jz .dead
    cmp byte [nb], 2
    je .alive
    cmp byte [nb], 3
    je .alive
    jmp .put
.dead:
    cmp byte [nb], 3
    jne .put
.alive:
    mov dl, 1
.put:
    mov di, [dstp]
    add di, [idx]
    mov [di], dl
    test dl, dl
    jz .npop
    inc word [pnum]
.npop:
    inc word [gx]
    jmp .xl
.xdone:
    inc word [gy]
    jmp .yl
.ydone:
    inc word [gen]
    xor byte [cur], 1
    ret

; ------------------------------------------------------------
h_tick:
    cmp byte [paused], 0
    jne .r0
    inc byte [tickc]
    mov al, [speed]
    cmp byte [tickc], al
    jb .r0
    mov byte [tickc], 0
    call step
    mov al, 1
    retf
.r0:
    xor al, al
    retf

h_key:
    cmp bh, KEY_ESC
    jne .k1
    GUI API_EXIT
    xor al, al
    retf
.k1:
    cmp bh, KEY_SPACE
    jne .k2
    xor byte [paused], 1
    jmp .yes
.k2:
    cmp bl, 'r'
    je .rnd
    cmp bl, 'R'
    je .rnd
    cmp bl, 'c'
    je .clr
    cmp bl, 'C'
    je .clr
    cmp bh, KEY_LEFT
    jne .kr
    cmp byte [curx], 0
    je .no
    dec byte [curx]
    jmp .yes
.kr:
    cmp bh, KEY_RIGHT
    jne .ku
    cmp byte [curx], COLS-1
    jae .no
    inc byte [curx]
    jmp .yes
.ku:
    cmp bh, KEY_UP
    jne .kd
    cmp byte [cury], 0
    je .no
    dec byte [cury]
    jmp .yes
.kd:
    cmp bh, KEY_DOWN
    jne .ke
    cmp byte [cury], ROWS-1
    jae .no
    inc byte [cury]
    jmp .yes
.ke:
    cmp bh, KEY_ENTER
    je .toggle
    cmp bl, '+'
    je .faster
    cmp bl, '='
    je .faster
    cmp bl, '-'
    je .slower
    jmp .no
.rnd:
    call randomize
    jmp .yes
.clr:
    call clear_all
    jmp .yes
.faster:
    cmp byte [speed], 18
    jae .no
    inc byte [speed]
    jmp .yes
.slower:
    cmp byte [speed], 1
    jbe .no
    dec byte [speed]
    jmp .yes
.toggle:
    movzx ax, byte [cury]
    mov bp, COLS
    mul bp
    movzx bx, byte [curx]
    add ax, bx
    mov di, ax
    mov si, g1
    cmp byte [cur], 0
    je .tg2
    mov si, g2
.tg2:
    add si, di
    cmp byte [si], 0
    je .set1
    mov byte [si], 0
    jmp .yes
.set1:
    mov byte [si], 1
    jmp .yes
.yes:
    mov al, 1
    retf
.no:
    xor al, al
    retf

; ------------------------------------------------------------
h_draw:
    xor al, al
    GUI API_CLEAR

    mov si, s_gen
    mov bx, 4
    mov cx, 1
    mov dl, 7
    GUI API_STR
    mov al, 7
    mov bx, 32
    mov cx, 1
    mov dx, [gen]
    GUI API_NUM

    mov si, s_pop
    mov bx, 90
    mov cx, 1
    mov dl, 7
    GUI API_STR
    mov al, 7
    mov bx, 126
    mov cx, 1
    mov dx, [pnum]
    GUI API_NUM

    mov si, s_spd
    mov bx, 176
    mov cx, 1
    mov dl, 8
    GUI API_STR
    mov al, 8
    mov bx, 218
    mov cx, 1
    xor dx, dx
    mov dl, [speed]
    GUI API_NUM

    cmp byte [paused], 0
    je .grid
    mov si, s_pause
    mov bx, 240
    mov cx, 1
    mov dl, 14
    GUI API_STR

.grid:
    mov word [yy], 0
.yrow:
    cmp word [yy], ROWS
    jae .cursor
    mov word [xx], 0
.xcol:
    cmp word [xx], COLS
    jae .xend
    mov ax, [yy]
    mov bp, COLS
    mul bp
    add ax, [xx]
    mov si, g1
    cmp byte [cur], 0
    je .sg2
    mov si, g2
.sg2:
    add si, ax
    cmp byte [si], 0
    je .ncell
    mov ax, [xx]
    shl ax, 3
    mov [px], ax
    mov ax, [yy]
    shl ax, 3
    add ax, 8
    mov [py], ax
    mov al, 10
    mov bx, [px]
    mov cx, [py]
    mov dx, 7
    mov si, 7
    GUI API_FILL
.ncell:
    inc word [xx]
    jmp .xcol
.xend:
    inc word [yy]
    jmp .yrow

.cursor:
    mov al, 14
    movzx ax, byte [curx]
    shl ax, 3
    mov [px], ax
    movzx ax, byte [cury]
    shl ax, 3
    add ax, 8
    mov [py], ax
    mov bx, [px]
    mov cx, [py]
    mov dx, 8
    mov si, 1
    GUI API_FILL
    mov bx, [px]
    mov cx, [py]
    add cx, 7
    mov dx, 8
    mov si, 1
    GUI API_FILL
    mov bx, [px]
    mov cx, [py]
    mov dx, 1
    mov si, 8
    GUI API_FILL
    mov bx, [px]
    add bx, 7
    mov cx, [py]
    mov dx, 1
    mov si, 8
    GUI API_FILL
    xor al, al
    retf

; ------------------------------------------------------------
; data
; ------------------------------------------------------------
gen     dw 0
pnum    dw 0
paused  db 0
speed   db 3
tickc   db 0
cur     db 0
curx    db 0
cury    db 0
idx     dw 0
gx      dw 0
gy      dw 0
dx_     dw 0
dy_     dw 0
nb      db 0
srcp    dw 0
dstp    dw 0
px      dw 0
py      dw 0
xx      dw 0
yy      dw 0

s_gen   db "GEN:", 0
s_pop   db "POP:", 0
s_spd   db "SPD", 0
s_pause db "PAUSE", 0

g1      times NCELL db 0
g2      times NCELL db 0
