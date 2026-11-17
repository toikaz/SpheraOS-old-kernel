; ============================================================
;  sierpin.asm - Sierpinski triangle by the chaos game
;  nasm -f bin -I gui/ sierpin.asm -o asm/sierpin.app
;  Space = pause, C = clear, 1/2/3 = palette, +/- = speed,
;  Esc = quit.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Sierpins", 200, 160

W   equ 200
H   equ 160
BSZ equ W*H

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

rnd:                            ; BX = n -> AX = 0..n-1
    mov ax, [rseed]
    mov dx, 25173
    mul dx
    add ax, 13849
    mov [rseed], ax
    shr ax, 4
    test bx, bx
    jz .r
    xor dx, dx
    div bx
    mov ax, dx
.r:
    ret

clear_bm:
    mov di, bm
    mov cx, BSZ
    xor al, al
    rep stosb
    mov word [cxp], W/2
    mov word [cyp], H/2
    ret

h_init:
    mov word [rseed], 0x5555
    mov word [iters], 200
    mov byte [paused], 0
    mov byte [pal], 0
    mov byte [dcount], 0
    call clear_bm
    xor al, al
    retf

h_tick:
    cmp byte [paused], 0
    jne .r0
    mov cx, [iters]
.plot:
    mov bx, 3
    call rnd
    mov [vi], ax
    mov si, ax
    shl si, 1
    mov ax, [cxp]
    add ax, [vtx+si]
    shr ax, 1
    mov [cxp], ax
    mov ax, [cyp]
    add ax, [vty+si]
    shr ax, 1
    mov [cyp], ax
    mov ax, [cyp]
    mov bp, W
    mul bp
    add ax, [cxp]
    mov [bmoff], ax
    mov di, ax
    movzx bx, byte [vi]
    movzx ax, byte [pal]
    imul ax, ax, 3
    add bx, ax
    mov al, [palettes+bx]
    mov [bm+di], al
    loop .plot
    ; repaint every second tick to keep the redraw cost low
    inc byte [dcount]
    cmp byte [dcount], 2
    jb .r0
    mov byte [dcount], 0
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
    je .pause
    cmp bl, 'c'
    je .clr
    cmp bl, 'C'
    je .clr
    cmp bl, '1'
    je .p0
    cmp bl, '2'
    je .p1
    cmp bl, '3'
    je .p2
    cmp bl, '+'
    je .fast
    cmp bl, '='
    je .fast
    cmp bl, '-'
    je .slow
    jmp .no
.pause:
    xor byte [paused], 1
    jmp .yes
.clr:
    call clear_bm
    jmp .yes
.p0:
    mov byte [pal], 0
    jmp .yes
.p1:
    mov byte [pal], 1
    jmp .yes
.p2:
    mov byte [pal], 2
    jmp .yes
.fast:
    cmp word [iters], 800
    jae .no
    add word [iters], 100
    jmp .yes
.slow:
    cmp word [iters], 50
    jbe .no
    sub word [iters], 100
.yes:
    mov al, 1
    retf
.no:
    xor al, al
    retf

h_draw:
    xor al, al
    GUI API_CLEAR
    mov word [bio], 0
.scan:
    cmp word [bio], BSZ
    jae .hint
    mov bx, [bio]
    mov al, [bm+bx]
    test al, al
    jz .nextpix
    mov ax, [bio]
    xor dx, dx
    mov bp, W
    div bp                      ; AX = y, DX = x
    mov [pyy], ax
    mov [pxx], dx
    mov al, [bm+bx]
    mov bx, [pxx]
    mov cx, [pyy]
    GUI API_PIX
.nextpix:
    inc word [bio]
    jmp .scan
.hint:
    mov si, s_hint
    mov bx, 4
    mov cx, 152
    mov dl, 15
    GUI API_STR
    xor al, al
    retf

; ------------------------------------------------------------
rseed   dw 0
cxp     dw 0
cyp     dw 0
vi      dw 0
iters   dw 0
pal     db 0
paused  db 0
dcount  db 0
bmoff   dw 0
bio     dw 0
pxx     dw 0
pyy     dw 0

vtx     dw 100, 4, 195
vty     dw 4, 155, 155

palettes db 2, 10, 14          ; green
         db 1, 9, 15            ; blue
         db 4, 12, 14           ; fire

s_hint  db "SPACE pause C clear +/- speed", 0

bm      times BSZ db 0
