; ============================================================
;  matrix.asm - falling green code for SpheraOS GUI
;  nasm -f bin -I gui/ matrix.asm -o asm/matrix.app
;  Space = pause, R = restart, Esc = quit.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Matrix", 180, 160

COLS equ 30
ROWS equ 19
TRAIL equ 10

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

h_init:
    call init_game
    xor al, al
    retf

init_game:
    mov word [rseed], 0x0BEEF
    mov byte [paused], 0
    mov byte [c], 0
.init_col:
    cmp byte [c], COLS
    jae .init_done
    movzx di, byte [c]
    movzx si, byte [c]
    shl si, 1
    mov bx, ROWS
    call rnd
    mov [head+si], ax
    mov bx, 3
    call rnd
    inc ax
    mov [spd+di], al
    mov [cnt+di], al
    mov word [r], 0
.init_chars:
    cmp word [r], ROWS
    jae .next_col
    mov ax, [r]
    mov bp, COLS
    mul bp
    movzx bx, byte [c]
    add ax, bx
    mov [tmp], ax
    mov bx, 95
    call rnd
    add ax, 32
    mov di, [tmp]
    mov [cmap+di], al
    inc word [r]
    jmp .init_chars
.next_col:
    inc byte [c]
    jmp .init_col
.init_done:
    ret

h_tick:
    cmp byte [paused], 0
    jne .r0
    mov byte [c], 0
.loop:
    cmp byte [c], COLS
    jae .done
    movzx di, byte [c]
    movzx si, byte [c]
    shl si, 1
    dec byte [cnt+di]
    jnz .next
    mov al, [spd+di]
    mov [cnt+di], al
    inc word [head+si]
    mov ax, [head+si]
    cmp ax, ROWS+10
    jb .shimmer
    mov bx, 10
    call rnd
    neg ax
    mov [head+si], ax
.shimmer:
    mov word [k], 3
.sh:
    mov bx, ROWS
    call rnd
    mov [rr], ax
    mov bx, 95
    call rnd
    add ax, 32
    mov [chr], al
    mov ax, [rr]
    mov bp, COLS
    mul bp
    movzx bx, byte [c]
    add ax, bx
    mov di, ax
    mov al, [chr]
    mov [cmap+di], al
    dec word [k]
    jnz .sh
.next:
    inc byte [c]
    jmp .loop
.done:
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
    cmp bl, 'r'
    je .restart
    cmp bl, 'R'
    jne .no
.restart:
    call init_game
    mov al, 1
    retf
.pause:
    xor byte [paused], 1
    mov al, 1
    retf
.no:
    xor al, al
    retf

h_draw:
    xor al, al
    GUI API_CLEAR
    mov byte [c], 0
.cloop:
    cmp byte [c], COLS
    jae .hint
    movzx si, byte [c]
    shl si, 1
    mov word [k], 0
.kloop:
    mov ax, [k]
    cmp ax, TRAIL
    jae .cnext
    mov ax, [head+si]
    sub ax, word [k]
    mov [rr], ax
    cmp ax, 0
    jl .knext
    cmp ax, ROWS
    jae .knext
    mov ax, [rr]
    mov bp, COLS
    mul bp
    movzx bx, byte [c]
    add ax, bx
    mov [tmp], ax
    mov di, ax
    mov al, [cmap+di]
    mov [chr], al
    ; colour fades along the trail
    cmp word [k], 0
    jne .c1
    mov dl, 15
    jmp .paint
.c1:
    cmp word [k], 2
    ja .c2
    mov dl, 10
    jmp .paint
.c2:
    cmp word [k], 5
    ja .c3
    mov dl, 2
    jmp .paint
.c3:
    mov dl, 8
.paint:
    mov al, [chr]
    movzx bx, byte [c]
    imul bx, bx, 6
    mov cx, [rr]
    imul cx, cx, 8
    GUI API_CHAR
.knext:
    inc word [k]
    jmp .kloop
.cnext:
    inc byte [c]
    jmp .cloop
.hint:
    mov si, s_hint
    xor bx, bx
    mov cx, 152
    mov dl, 8
    GUI API_STR
    xor al, al
    retf

; ------------------------------------------------------------
paused  db 0
rseed   dw 0
c       db 0
k       dw 0
r       dw 0
rr      dw 0
tmp     dw 0
chr     db 0

head    times COLS dw 0
spd     times COLS db 0
cnt     times COLS db 0
cmap    times COLS*ROWS db 0

s_hint  db "SPACE pause R restart Esc quit", 0
