; ============================================================
;  mines.asm - Minesweeper for SpheraOS GUI
;  Build:  nasm -f bin mines.asm -o MINES.APP
;  Copy MINES.APP to the disk, open Files, press Enter on it.
;
;  Keys: Arrows = cursor, Enter/O = open, Space/F = flag,
;        Esc = exit (to start a new game, exit and relaunch).
;  Field 9x9, 10 mines. Mines are placed after the first
;  open, so the first click is always safe.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Mines", 140, 144

COLS   equ 9
ROWS   equ 9
NMINES equ 10
CSZ    equ 12                 ; cell size in pixels
GX     equ 16                 ; grid origin x (centered)
GY     equ 14                 ; grid origin y
NC     equ COLS*ROWS

main:
    push cs
    pop ds
    cmp ax, MSG_INIT
    je h_init
    cmp ax, MSG_KEY
    je h_key
    cmp ax, MSG_DRAW
    je h_draw
    xor al, al
    retf

h_init:
    call reset_game
    xor al, al
    retf

reset_game:
    xor ax, ax
    mov di, minef
    mov cx, NC
    rep stosb
    mov di, openf
    mov cx, NC
    rep stosb
    mov word [curx], 4
    mov word [cury], 4
    mov byte [started], 0
    mov byte [dead], 0
    mov byte [won], 0
    mov word [opened], 0
    ret

; ------------------------------------------------------------
; key handling: BL = ascii, BH = scan
; ------------------------------------------------------------
h_key:
    cmp bh, KEY_ESC
    jne .a
    GUI API_EXIT
    xor al, al
    retf
.a:
    cmp bh, KEY_UP
    jne .b
    cmp word [cury], 0
    je .r
    dec word [cury]
    jmp .r
.b:
    cmp bh, KEY_DOWN
    jne .c
    cmp word [cury], ROWS-1
    jae .r
    inc word [cury]
    jmp .r
.c:
    cmp bh, KEY_LEFT
    jne .d
    cmp word [curx], 0
    je .r
    dec word [curx]
    jmp .r
.d:
    cmp bh, KEY_RIGHT
    jne .e
    cmp word [curx], COLS-1
    jae .r
    inc word [curx]
    jmp .r
.e:
    cmp bh, KEY_ENTER
    je .open
    cmp bl, 'o'
    je .open
    cmp bl, 'O'
    je .open
    cmp bl, ' '
    je .flag
    cmp bl, 'f'
    je .flag
    cmp bl, 'F'
    je .flag
.r:
    mov al, 1
    retf

.flag:
    cmp byte [dead], 0
    jne .r
    cmp byte [won], 0
    jne .r
    mov ax, [cury]
    imul ax, ax, COLS
    add ax, [curx]
    mov si, ax
    cmp byte [openf+si], 1
    je .r
    cmp byte [openf+si], 2
    je .unf
    mov byte [openf+si], 2
    jmp .r
.unf:
    mov byte [openf+si], 0
    jmp .r

.open:
    cmp byte [dead], 0
    jne .r
    cmp byte [won], 0
    jne .r
    mov ax, [cury]
    imul ax, ax, COLS
    add ax, [curx]
    mov si, ax
    cmp byte [openf+si], 0
    jne .r
    cmp byte [started], 0
    jne .st
    call place_mines            ; SI = excluded (first) cell
    mov byte [started], 1
.st:
    cmp byte [minef+si], 0
    je .safe
    mov byte [dead], 1
    mov byte [openf+si], 1
    jmp .r
.safe:
    call flood
    mov ax, NC - NMINES
    cmp word [opened], ax
    jne .r
    mov byte [won], 1
    jmp .r

; ------------------------------------------------------------
; mines
; ------------------------------------------------------------
; place_mines: SI = cell to exclude
place_mines:
    mov [pm_excl], si
    mov word [pm_cnt], NMINES
.try:
    cmp word [pm_cnt], 0
    je .done
    mov bx, NC
    GUI API_RND                 ; AX = 0..NC-1
    cmp ax, [pm_excl]
    je .try
    mov di, ax
    cmp byte [minef+di], 0
    jne .try
    mov byte [minef+di], 1
    dec word [pm_cnt]
    jmp .try
.done:
    ret

; count_mines: SI = index -> AX = mines in the 8 neighbours
count_mines:
    push bx
    push cx
    push dx
    push si
    mov ax, si
    xor dx, dx
    mov bx, COLS
    div bx                      ; AX = row, DX = col
    mov [cm_row], ax
    mov [cm_col], dx
    xor ax, ax
    mov word [cm_dy], -1
.dy:
    mov word [cm_dx], -1
.dx:
    mov bx, [cm_row]
    add bx, [cm_dy]
    cmp bx, 0
    jl .nx
    cmp bx, ROWS
    jge .nx
    imul bx, bx, COLS
    mov dx, [cm_col]
    add dx, [cm_dx]
    cmp dx, 0
    jl .nx
    cmp dx, COLS
    jge .nx
    add bx, dx
    cmp byte [minef+bx], 0
    je .nx
    inc ax
.nx:
    inc word [cm_dx]
    cmp word [cm_dx], 1
    jle .dx
    inc word [cm_dy]
    cmp word [cm_dy], 1
    jle .dy
    pop si
    pop dx
    pop cx
    pop bx
    ret

; flood: reveal from SI (iterative, own stack at [stk])
flood:
    pusha
    mov word [stkp], 0
    mov bx, si
    call fpush
.f:
    cmp word [stkp], 0
    je .done
    call fpop
    mov si, bx
    cmp byte [openf+si], 0
    jne .f
    cmp byte [minef+si], 0
    jne .f
    mov byte [openf+si], 1
    inc word [opened]
    call count_mines
    test ax, ax
    jnz .f                      ; a number stops the expansion
    mov ax, si
    xor dx, dx
    mov bx, COLS
    div bx
    mov [f_row], ax
    mov [f_col], dx
    mov word [f_dy], -1
.dy:
    mov word [f_dx], -1
.dx:
    mov bx, [f_row]
    add bx, [f_dy]
    cmp bx, 0
    jl .nx
    cmp bx, ROWS
    jge .nx
    imul bx, bx, COLS
    mov dx, [f_col]
    add dx, [f_dx]
    cmp dx, 0
    jl .nx
    cmp dx, COLS
    jge .nx
    add bx, dx
    call fpush
.nx:
    inc word [f_dx]
    cmp word [f_dx], 1
    jle .dx
    inc word [f_dy]
    cmp word [f_dy], 1
    jle .dy
    jmp .f
.done:
    popa
    ret

fpush:                          ; BX = cell index
    mov di, [stkp]
    cmp di, 1000
    jae .r
    mov [stk+di], bx
    add di, 2
    mov [stkp], di
.r:
    ret

fpop:                           ; -> BX
    mov di, [stkp]
    sub di, 2
    mov [stkp], di
    mov bx, [stk+di]
    ret

; ------------------------------------------------------------
; draw
; ------------------------------------------------------------
h_draw:
    xor al, al
    GUI API_CLEAR
    ; count flags
    xor ax, ax
    mov [flagc], ax
    mov si, 0
.fc:
    cmp si, NC
    jae .fcd
    cmp byte [openf+si], 2
    jne .fcn
    inc word [flagc]
.fcn:
    inc si
    jmp .fc
.fcd:
    ; mines left
    mov si, s_mines
    mov bx, 4
    mov cx, 4
    mov dl, 15
    GUI API_STR
    mov ax, NMINES
    sub ax, [flagc]
    mov dx, ax
    mov al, 15
    mov bx, 40
    mov cx, 4
    GUI API_NUM
    ; state text
    cmp byte [dead], 0
    jne .boom
    cmp byte [won], 0
    jne .win
    jmp .grid
.boom:
    mov si, s_boom
    mov bx, 60
    mov cx, 4
    mov dl, 12
    GUI API_STR
    jmp .grid
.win:
    mov si, s_win
    mov bx, 52
    mov cx, 4
    mov dl, 14
    GUI API_STR
.grid:
    mov word [iy], 0
.gr:
    mov word [ix], 0
.gc:
    mov ax, [iy]
    imul ax, ax, COLS
    add ax, [ix]
    mov si, ax                  ; SI = cell index
    mov bx, [ix]
    imul bx, bx, CSZ
    add bx, GX
    mov [bt_x], bx
    mov bx, [iy]
    imul bx, bx, CSZ
    add bx, GY
    mov [bt_y], bx
    cmp byte [openf+si], 2
    je .fl
    cmp byte [openf+si], 1
    je .openc
    ; hidden: show mines after death
    cmp byte [dead], 0
    je .hid
    cmp byte [minef+si], 0
    jne .mine
.hid:
    mov al, 8
    mov bx, [bt_x]
    mov cx, [bt_y]
    mov dx, CSZ
    mov si, CSZ
    GUI API_FILL
    jmp .next
.mine:
    mov al, 0
    mov bx, [bt_x]
    mov cx, [bt_y]
    mov dx, CSZ
    mov si, CSZ
    GUI API_FILL
    mov al, '*'
    mov bx, [bt_x]
    add bx, 3
    mov cx, [bt_y]
    add cx, 2
    mov dl, 12
    GUI API_CHAR
    jmp .next
.fl:
    mov al, 4
    mov bx, [bt_x]
    mov cx, [bt_y]
    mov dx, CSZ
    mov si, CSZ
    GUI API_FILL
    mov al, 'F'
    mov bx, [bt_x]
    add bx, 3
    mov cx, [bt_y]
    add cx, 2
    mov dl, 15
    GUI API_CHAR
    jmp .next
.openc:
    cmp byte [minef+si], 0
    jne .mine
    mov [bt_i], si
    mov al, 15
    mov bx, [bt_x]
    mov cx, [bt_y]
    mov dx, CSZ
    mov si, CSZ
    GUI API_FILL
    mov si, [bt_i]
    call count_mines
    test ax, ax
    jz .next
    mov [bt_n], ax
    dec ax
    mov di, ax
    mov al, [ncol+di]
    mov bx, [bt_x]
    add bx, 3
    mov cx, [bt_y]
    add cx, 2
    mov dx, [bt_n]
    GUI API_NUM
.next:
    inc word [ix]
    cmp word [ix], COLS
    jb .gc
    inc word [iy]
    cmp word [iy], ROWS
    jb .gr
    ; cursor frame (yellow)
    mov bx, [curx]
    imul bx, bx, CSZ
    add bx, GX
    mov [bt_x], bx
    mov bx, [cury]
    imul bx, bx, CSZ
    add bx, GY
    mov [bt_y], bx
    mov al, 14
    mov bx, [bt_x]
    mov cx, [bt_y]
    mov dx, CSZ
    mov si, 1
    GUI API_FILL
    mov al, 14
    mov bx, [bt_x]
    mov cx, [bt_y]
    add cx, CSZ-1
    mov dx, CSZ
    mov si, 1
    GUI API_FILL
    mov al, 14
    mov bx, [bt_x]
    mov cx, [bt_y]
    mov dx, 1
    mov si, CSZ
    GUI API_FILL
    mov al, 14
    mov bx, [bt_x]
    add bx, CSZ-1
    mov cx, [bt_y]
    mov dx, 1
    mov si, CSZ
    GUI API_FILL
    ; hints
    mov si, s_open
    mov bx, 8
    mov cx, 126
    mov dl, 8
    GUI API_STR
    mov si, s_new
    mov bx, 8
    mov cx, 135
    mov dl, 8
    GUI API_STR
    mov al, 1
    retf

; ------------------------------------------------------------
; data
; ------------------------------------------------------------
minef    times NC db 0         ; 1 = mine
openf    times NC db 0         ; 0 hidden, 1 open, 2 flagged
stk      times 512 dw 0        ; flood fill stack

curx     dw 4
cury     dw 4
started  db 0
dead     db 0
won      db 0
opened   dw 0
flagc    dw 0
stkp     dw 0
pm_excl  dw 0
pm_cnt   dw 0
f_row    dw 0
f_col    dw 0
f_dy     dw 0
f_dx     dw 0
cm_row   dw 0
cm_col   dw 0
cm_dy    dw 0
cm_dx    dw 0
ix       dw 0
iy       dw 0
bt_x     dw 0
bt_y     dw 0
bt_n     dw 0
bt_i     dw 0

ncol     db 1, 2, 4, 1, 4, 3, 8, 7
s_mines  db "Mines:", 0
s_boom   db "BOOM!", 0
s_win    db "YOU WIN!", 0
s_open   db "Enter=open Space=flag", 0
s_new    db "Esc=quit", 0