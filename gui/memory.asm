; ============================================================
;  memory.asm - pairs / concentration game for SpheraOS GUI
;  nasm -f bin -I gui/ memory.asm -o asm/memory.app
;  Arrows = move, Enter/Space = flip a card, R = restart,
;  Esc = quit.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Memory", 152, 116

N equ 16

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

shuffle:
    mov word [rseed], 0x6666
    mov si, cards
    mov cx, N
    xor bx, bx
.fill:
    mov al, bl
    shr al, 1
    mov [si], al
    inc si
    inc bx
    loop .fill
    mov word [ci], N-1
.shloop:
    cmp word [ci], 0
    je .done
    mov bx, [ci]
    inc bx
    call rnd                    ; AX = 0..ci
    mov [r], ax
    mov bx, [ci]
    mov al, [cards+bx]
    mov [tmp], al
    mov bx, [r]
    mov al, [cards+bx]
    mov di, [ci]
    mov [cards+di], al
    mov bx, [r]
    mov al, [tmp]
    mov [cards+bx], al
    dec word [ci]
    jmp .shloop
.done:
    ret

init_game:
    call shuffle
    mov di, shown
    mov cx, N
    xor al, al
    rep stosb
    mov byte [cursor], 0
    mov byte [first], 255
    mov byte [second], 255
    mov byte [matched], 0
    mov word [tries], 0
    mov byte [delay], 0
    mov byte [state], 0
    ret

h_init:
    call init_game
    xor al, al
    retf

h_tick:
    cmp byte [delay], 0
    je .r0
    dec byte [delay]
    jnz .redraw
    mov al, [first]
    cmp al, 255
    je .hide2
    movzx di, al
    cmp byte [shown+di], 2
    je .hide2
    mov byte [shown+di], 0
.hide2:
    mov al, [second]
    cmp al, 255
    je .clear
    movzx di, al
    cmp byte [shown+di], 2
    je .clear
    mov byte [shown+di], 0
.clear:
    mov byte [first], 255
    mov byte [second], 255
.redraw:
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
    cmp bl, 'r'
    je .new
    cmp bl, 'R'
    je .new
    cmp byte [state], 1
    je .no
    cmp byte [delay], 0
    jne .no
    cmp bh, KEY_LEFT
    jne .kr
    movzx ax, byte [cursor]
    and ax, 3
    jz .no
    dec byte [cursor]
    jmp .yes
.kr:
    cmp bh, KEY_RIGHT
    jne .ku
    movzx ax, byte [cursor]
    and ax, 3
    cmp ax, 3
    je .no
    inc byte [cursor]
    jmp .yes
.ku:
    cmp bh, KEY_UP
    jne .kd
    cmp byte [cursor], 3
    jb .no
    sub byte [cursor], 4
    jmp .yes
.kd:
    cmp bh, KEY_DOWN
    jne .flip
    cmp byte [cursor], 12
    jae .no
    add byte [cursor], 4
    jmp .yes
.flip:
    cmp bh, KEY_ENTER
    jne .sp
    jmp .do
.sp:
    cmp bh, KEY_SPACE
    jne .no
.do:
    movzx di, byte [cursor]
    cmp byte [shown+di], 0
    jne .no
    mov byte [shown+di], 1
    mov al, [first]
    cmp al, 255
    jne .two
    mov al, [cursor]
    mov [first], al
    jmp .yes
.two:
    mov al, [cursor]
    mov [second], al
    inc word [tries]
    movzx bx, byte [first]
    movzx di, bl
    mov al, [cards+di]
    mov [tmp], al
    movzx di, byte [cursor]
    mov al, [cards+di]
    cmp al, [tmp]
    jne .miss
    ; match
    movzx di, byte [first]
    mov byte [shown+di], 2
    movzx di, byte [cursor]
    mov byte [shown+di], 2
    mov byte [first], 255
    mov byte [second], 255
    add byte [matched], 2
    cmp byte [matched], N
    jne .yes
    mov byte [state], 1
    jmp .yes
.miss:
    mov byte [delay], 22
    jmp .yes
.new:
    call init_game
.yes:
    mov al, 1
    retf
.no:
    xor al, al
    retf

h_draw:
    mov al, 1
    GUI API_CLEAR
    mov word [i], 0
.cardloop:
    cmp word [i], N
    jae .status
    mov ax, [i]
    xor dx, dx
    mov bp, 4
    div bp                      ; AX = row, DX = col
    mov [ccol], dx
    mov [crow], ax
    mov ax, [ccol]
    imul ax, ax, 36
    add ax, 4
    mov [cx_], ax
    mov ax, [crow]
    imul ax, ax, 22
    add ax, 4
    mov [cy_], ax
    mov di, [i]
    mov al, [shown+di]
    test al, al
    jnz .faceup
    ; back of the card
    mov al, 8
    mov bx, [cx_]
    mov cx, [cy_]
    mov dx, 34
    mov si, 20
    GUI API_FILL
    mov al, '?'
    mov bx, [cx_]
    add bx, 15
    mov cx, [cy_]
    add cx, 6
    mov dl, 15
    GUI API_CHAR
    jmp .frame
.faceup:
    mov al, [cards+di]
    mov [pid], al
    cmp byte [shown+di], 2
    je .dim
    movzx bx, byte [pid]
    mov al, [paircol+bx]
    jmp .fillcard
.dim:
    mov al, 8
.fillcard:
    mov [fcol], al
    mov bx, [cx_]
    mov cx, [cy_]
    mov dx, 34
    mov si, 20
    GUI API_FILL
    movzx bx, byte [pid]
    mov al, [paircol+bx]
    mov bx, [cx_]
    add bx, 15
    mov cx, [cy_]
    add cx, 6
    mov dl, 15
    GUI API_CHAR
.frame:
    movzx ax, byte [cursor]
    cmp ax, [i]
    jne .nextcard
    mov al, 14
    mov bx, [cx_]
    mov cx, [cy_]
    mov dx, 34
    mov si, 1
    GUI API_FILL
    mov bx, [cx_]
    mov cx, [cy_]
    add cx, 19
    mov dx, 34
    mov si, 1
    GUI API_FILL
    mov bx, [cx_]
    mov cx, [cy_]
    mov dx, 1
    mov si, 20
    GUI API_FILL
    mov bx, [cx_]
    add bx, 33
    mov cx, [cy_]
    mov dx, 1
    mov si, 20
    GUI API_FILL
.nextcard:
    inc word [i]
    jmp .cardloop

.status:
    mov si, s_tries
    mov bx, 4
    mov cx, 96
    mov dl, 15
    GUI API_STR
    mov al, 15
    mov bx, 40
    mov cx, 96
    mov dx, [tries]
    GUI API_NUM
    cmp byte [state], 1
    je .win
    mov si, s_pairs
    mov bx, 84
    mov cx, 96
    mov dl, 15
    GUI API_STR
    mov al, 15
    mov bx, 128
    mov cx, 96
    xor dx, dx
    mov dl, [matched]
    shr dl, 1
    GUI API_NUM
    jmp .hint
.win:
    mov si, s_win
    mov bx, 84
    mov cx, 96
    mov dl, 14
    GUI API_STR
.hint:
    mov si, s_hint
    mov bx, 4
    mov cx, 106
    mov dl, 8
    GUI API_STR
    xor al, al
    retf

; ------------------------------------------------------------
rseed   dw 0
ci      dw 0
r       dw 0
tmp     db 0
i       dw 0
ccol    dw 0
crow    dw 0
cx_     dw 0
cy_     dw 0
pid     db 0
fcol    db 0
cursor  db 0
first   db 0
second  db 0
matched db 0
tries   dw 0
delay   db 0
state   db 0

cards   times N db 0
shown   times N db 0

paircol db 4, 2, 3, 14, 5, 9, 12, 10
s_tries db "TRIES", 0
s_pairs db "PAIRS", 0
s_win   db "YOU WIN!", 0
s_hint  db "ARROWS move  ENTER flip  R restart", 0
