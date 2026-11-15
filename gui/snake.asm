; ============================================================
;  snake.asm - Snake for SpheraOS GUI
;  nasm -f bin snake.asm -o snake.app   (copy to disk as SNAKE.APP)
;  Arrows = steer, Space/Enter = restart, Esc = quit.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Snake", 160, 128

COLS   equ 20
ROWS   equ 14
MAXLEN equ 200

entry:                          ; offset 20h
    push cs
    pop ds
    cmp ax, MSG_DRAW
    je near do_draw
    cmp ax, MSG_TICK
    je near do_tick
    cmp ax, MSG_KEY
    je near do_key
    cmp ax, MSG_INIT
    jne .out
    call new_game
.out:
    xor al, al
    retf

do_tick:
    inc byte [cnt]
    cmp byte [cnt], 2           ; one step every 2 ticks (~9 per second)
    jb .r
    mov byte [cnt], 0
    cmp byte [dead], 0
    jne .r
    call step
.r:
    mov al, 1
    retf

do_key:
    cmp bh, KEY_ESC
    jne .k0
    GUI API_EXIT
    jmp .r
.k0:
    cmp byte [dead], 0
    je .play
    cmp bh, KEY_SPACE
    je .restart
    cmp bh, KEY_ENTER
    jne .r
.restart:
    call new_game
    jmp .r
.play:
    cmp bh, KEY_UP
    jne .k1
    cmp byte [diry], 1
    je .r
    mov byte [ndirx], 0
    mov byte [ndiry], -1
    jmp .r
.k1:
    cmp bh, KEY_DOWN
    jne .k2
    cmp byte [diry], -1
    je .r
    mov byte [ndirx], 0
    mov byte [ndiry], 1
    jmp .r
.k2:
    cmp bh, KEY_LEFT
    jne .k3
    cmp byte [dirx], 1
    je .r
    mov byte [ndirx], -1
    mov byte [ndiry], 0
    jmp .r
.k3:
    cmp bh, KEY_RIGHT
    jne .r
    cmp byte [dirx], -1
    je .r
    mov byte [ndirx], 1
    mov byte [ndiry], 0
.r:
    mov al, 1
    retf

new_game:
    mov word [len], 3
    mov byte [snx], 10
    mov byte [sny], 7
    mov byte [snx+1], 9
    mov byte [sny+1], 7
    mov byte [snx+2], 8
    mov byte [sny+2], 7
    mov byte [dirx], 1
    mov byte [diry], 0
    mov byte [ndirx], 1
    mov byte [ndiry], 0
    mov byte [dead], 0
    mov word [score], 0
    mov byte [cnt], 0
    call place_food
    ret

; put the food on a random free cell
place_food:
    mov cx, 30
.t:
    mov bx, COLS
    GUI API_RND
    mov [fx], al
    mov bx, ROWS
    GUI API_RND
    mov [fy], al
    call on_snake
    jnc .ok
    loop .t
.ok:
    ret

; CF=1 if (fx,fy) is on the snake
on_snake:
    push cx
    xor si, si
    mov cx, [len]
.l:
    mov al, [snx+si]
    cmp al, [fx]
    jne .n
    mov al, [sny+si]
    cmp al, [fy]
    jne .n
    pop cx
    stc
    ret
.n:
    inc si
    loop .l
    pop cx
    clc
    ret

; advance the snake one cell
step:
    mov al, [ndirx]
    mov [dirx], al
    mov al, [ndiry]
    mov [diry], al
    mov bl, [snx]
    add bl, [dirx]
    mov bh, [sny]
    add bh, [diry]
    cmp bl, COLS                ; negative wraps to 255 -> also a wall hit
    jae near .die
    cmp bh, ROWS
    jae near .die
    mov cx, [len]               ; bumped into itself?
    xor si, si
.c:
    cmp bl, [snx+si]
    jne .nc
    cmp bh, [sny+si]
    je near .die
.nc:
    inc si
    loop .c
    mov byte [ate], 0           ; ate the food?
    cmp bl, [fx]
    jne .mv
    cmp bh, [fy]
    jne .mv
    mov byte [ate], 1
    add word [score], 10
    cmp word [len], MAXLEN-1
    jae .mv
    inc word [len]
.mv:
    mov si, [len]               ; shift the body, put the new head in front
    dec si
.sh:
    test si, si
    jz .hd
    mov al, [snx+si-1]
    mov [snx+si], al
    mov al, [sny+si-1]
    mov [sny+si], al
    dec si
    jmp .sh
.hd:
    mov [snx], bl
    mov [sny], bh
    cmp byte [ate], 0
    je .r
    call place_food
.r:
    ret
.die:
    mov byte [dead], 1
    ret

do_draw:
    xor al, al                  ; black board
    GUI API_CLEAR

    mov al, 8                   ; separator under the score line
    xor bx, bx
    mov cx, 14
    mov dx, 160
    mov si, 1
    GUI API_FILL

    mov al, [fx]                ; food
    xor ah, ah
    shl ax, 3
    mov bx, ax
    mov al, [fy]
    xor ah, ah
    shl ax, 3
    add ax, 16
    mov cx, ax
    mov dx, 7
    mov si, 7
    mov al, 12
    GUI API_FILL

    xor di, di                  ; snake
.s:
    cmp di, [len]
    jae .sd
    mov al, [snx+di]
    xor ah, ah
    shl ax, 3
    mov bx, ax
    mov al, [sny+di]
    xor ah, ah
    shl ax, 3
    add ax, 16
    mov cx, ax
    mov dx, 7
    mov si, 7
    mov al, 10
    test di, di
    jnz .col
    mov al, 14                  ; head is yellow
.col:
    GUI API_FILL
    inc di
    jmp .s
.sd:
    mov si, s_score
    mov bx, 4
    mov cx, 3
    mov dl, 15
    GUI API_STR
    mov al, 14
    mov bx, 52
    mov cx, 3
    mov dx, [score]
    GUI API_NUM
    cmp byte [dead], 0
    je .done
    mov si, s_over
    mov bx, 12
    mov cx, 60
    mov dl, 12
    GUI API_STR
.done:
    xor al, al
    retf

cnt     db 0
dead    db 0
ate     db 0
dirx    db 1
diry    db 0
ndirx   db 1
ndiry   db 0
fx      db 0
fy      db 0
len     dw 3
score   dw 0
s_score db "Score", 0
s_over  db "Game over - Space", 0
snx     times MAXLEN db 0
sny     times MAXLEN db 0
