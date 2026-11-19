; ============================================================
;  pong.asm - Pong for SpheraOS GUI
;  Build :  nasm -f bin -I gui/ gui/pong.asm -o asm/pong.app
;  Copy it to the disk as PONG.APP, open Files, Enter on it.
;
;  Keys : Up / Down ... move your paddle (left side)
;         Space ...... pause / resume
;         R .......... new game
;         Esc ........ quit
;  The CPU plays the right paddle. First to 7 points wins.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

W          equ 240          ; client width  (pixels)
H          equ 160          ; client height (pixels)
PAD_W      equ 4            ; paddle size
PAD_H      equ 28
PAD_MARGIN equ 6
PLX        equ PAD_MARGIN           ; player paddle x  (left)
CPX        equ W-PAD_MARGIN-PAD_W   ; cpu paddle x     (right)
BALL       equ 4            ; ball size
BALL_SPD   equ 3            ; ball speed, pixels per tick
CPU_SPD    equ 2            ; cpu paddle speed
PLAYER_SPD equ 6            ; player paddle step per key
WINSCORE   equ 7

APP_HEADER "Pong", W, H

; ------------------------------------------------------------
;  entry: offset 20h, a far-called message handler
;  AX = message, BL = ascii, BH = scan
; ------------------------------------------------------------
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

; ============================================================
;  MSG_INIT
; ============================================================
h_init:
    call reset_game
    xor al, al
    retf

; ---- reset_game: fresh match (also used by the R key) -------
reset_game:
    mov bx, 0                   ; make sure the speaker is off
    GUI API_SOUND
    mov byte [paused], 0
    mov byte [over], 0
    mov word [snd], 0
    mov word [scoreL], 0
    mov word [scoreR], 0
    call center_paddles
    call new_ball
    ret

center_paddles:
    mov ax, H
    sub ax, PAD_H
    shr ax, 1
    mov [pyL], ax
    mov [pyR], ax
    ret

; new_ball: put the ball in the middle, pick a random direction
new_ball:
    mov ax, W
    sub ax, BALL
    shr ax, 1
    mov [balx], ax
    mov ax, H
    sub ax, BALL
    shr ax, 1
    mov [baly], ax

    mov bx, 2                   ; horizontal direction
    GUI API_RND
    test ax, ax
    jz .left
    mov word [balvx], BALL_SPD
    jmp .v
.left:
    mov word [balvx], -BALL_SPD
.v:
    mov bx, 2                   ; vertical direction
    GUI API_RND
    test ax, ax
    jz .up
    mov word [balvy], BALL_SPD
    jmp .r
.up:
    mov word [balvy], -BALL_SPD
.r:
    ret

; ============================================================
;  MSG_TICK  -  the "game clock", ~18.2 times per second
; ============================================================
h_tick:
    cmp word [snd], 0           ; short beep timer
    je .nob
    dec word [snd]
    jnz .nob
    mov bx, 0
    GUI API_SOUND
.nob:
    cmp byte [over], 0
    jne .idle
    cmp byte [paused], 0
    jne .idle
    call move_cpu
    call move_ball
    mov al, 1                   ; ask for a redraw
    retf
.idle:
    xor al, al
    retf

; beep: BX = tone divisor, keep it on for a few ticks
beep:
    GUI API_SOUND
    mov word [snd], 3
    ret

; ---- cpu paddle follows the ball, slowly -------------------
move_cpu:
    mov ax, [baly]
    add ax, BALL/2              ; ball centre
    sub ax, PAD_H/2             ; wanted paddle top
    mov dx, [pyR]
    sub ax, dx                  ; how far off are we?
    cmp ax, 3
    jg .down
    cmp ax, -3
    jl .up
    ret
.down:
    mov ax, [pyR]
    add ax, CPU_SPD
    call clamp_padR
    ret
.up:
    mov ax, [pyR]
    sub ax, CPU_SPD
    call clamp_padR
    ret

; clamp_padL / clamp_padR: AX = wanted top, keep it on the field
clamp_padL:
    test ax, ax
    jns .p
    xor ax, ax
.p:
    cmp ax, H-PAD_H
    jbe .ok
    mov ax, H-PAD_H
.ok:
    mov [pyL], ax
    ret

clamp_padR:
    test ax, ax
    jns .p
    xor ax, ax
.p:
    cmp ax, H-PAD_H
    jbe .ok
    mov ax, H-PAD_H
.ok:
    mov [pyR], ax
    ret

; ---- ball: move, bounce, score -----------------------------
move_ball:
    mov ax, [balx]
    add ax, [balvx]
    mov [balx], ax
    mov ax, [baly]
    add ax, [balvy]
    mov [baly], ax

    cmp word [baly], 0          ; top wall
    jge .ntop
    mov word [baly], 0
    neg word [balvy]
    mov bx, 4000
    call beep
.ntop:
    mov ax, H                   ; bottom wall
    sub ax, BALL
    cmp [baly], ax
    jle .nbot
    mov [baly], ax
    neg word [balvy]
    mov bx, 4000
    call beep
.nbot:

    ; ---- player paddle (left) ----
    cmp word [balvx], 0
    jge .pcpu                   ; only when travelling left
    mov ax, [balx]
    cmp ax, PLX+PAD_W
    ja .pcpu
    mov cx, ax
    add cx, BALL
    cmp cx, PLX
    jb .pcpu
    mov ax, [baly]
    add ax, BALL
    cmp ax, [pyL]
    jbe .pcpu
    mov ax, [pyL]
    add ax, PAD_H
    cmp [baly], ax
    jae .pcpu
    mov dx, [pyL]
    call hit_left
.pcpu:

    ; ---- cpu paddle (right) ----
    cmp word [balvx], 0
    jle .score                  ; only when travelling right
    mov ax, [balx]
    add ax, BALL
    cmp ax, CPX
    jb .score
    mov ax, CPX
    add ax, PAD_W
    cmp [balx], ax
    jae .score
    mov ax, [baly]
    add ax, BALL
    cmp ax, [pyR]
    jbe .score
    mov ax, [pyR]
    add ax, PAD_H
    cmp [baly], ax
    jae .score
    mov dx, [pyR]
    call hit_right

.score:
    cmp word [balx], 0          ; past the left wall: cpu scores
    jge .chkR
    inc word [scoreR]
    mov bx, 2000
    call beep
    call check_win
    call new_ball
    ret
.chkR:
    mov ax, W
    sub ax, BALL
    cmp [balx], ax              ; past the right wall: player scores
    jle .done
    inc word [scoreL]
    mov bx, 2000
    call beep
    call check_win
    call new_ball
.done:
    ret

; ---- paddle hits ----
; hit_left / hit_right: DX = paddle top.  Push the ball back out and
; set the bounce angle from where on the paddle it was struck.
hit_left:
    mov word [balx], PLX+PAD_W
    mov word [balvx], BALL_SPD
    jmp do_angle
hit_right:
    mov word [balx], CPX-BALL
    mov word [balvx], -BALL_SPD
do_angle:
    mov ax, [baly]
    add ax, BALL/2
    mov cx, dx
    add cx, PAD_H/2
    sub ax, cx                  ; ball centre - paddle centre
    mov cx, 5
    cwd
    idiv cx
    cmp ax, 4                   ; clamp the angle
    jle .c1
    mov ax, 4
.c1:
    cmp ax, -4
    jge .c2
    mov ax, -4
.c2:
    test ax, ax
    jnz .st
    mov ax, 1                   ; never perfectly flat after a hit
.st:
    mov [balvy], ax
    mov bx, 3000
    call beep
    ret

check_win:
    cmp word [scoreL], WINSCORE
    jae .win
    cmp word [scoreR], WINSCORE
    jae .win
    ret
.win:
    mov byte [over], 1
    mov bx, 0
    GUI API_SOUND
    ret

; ============================================================
;  MSG_KEY
; ============================================================
h_key:
    cmp bh, KEY_ESC
    jne .k1
    mov bx, 0
    GUI API_SOUND
    GUI API_EXIT
    xor al, al
    retf
.k1:
    cmp byte [over], 0
    je .play
    cmp bh, KEY_SPACE
    je .restart
    cmp bh, KEY_ENTER
    je .restart
    cmp bl, 'r'
    je .restart
    cmp bl, 'R'
    je .restart
    jmp .no
.restart:
    call reset_game
    jmp .yes
.play:
    cmp bh, KEY_UP
    jne .kd
    mov ax, [pyL]
    sub ax, PLAYER_SPD
    call clamp_padL
    jmp .yes
.kd:
    cmp bh, KEY_DOWN
    jne .ks
    mov ax, [pyL]
    add ax, PLAYER_SPD
    call clamp_padL
    jmp .yes
.ks:
    cmp bh, KEY_SPACE
    jne .kr
    xor byte [paused], 1
    jmp .yes
.kr:
    cmp bl, 'r'
    je .restart
    cmp bl, 'R'
    je .restart
.no:
    xor al, al
    retf
.yes:
    mov al, 1
    retf

; ============================================================
;  MSG_DRAW
; ============================================================
h_draw:
    xor al, al                  ; black field
    GUI API_CLEAR

    mov word [yy], 0            ; dashed centre line
.cd:
    mov ax, [yy]
    cmp ax, H
    jae .pads
    mov al, 8
    mov bx, W/2-1
    mov cx, [yy]
    mov dx, 2
    mov si, 5
    GUI API_FILL
    add word [yy], 10
    jmp .cd
.pads:
    mov al, 10                  ; player paddle
    mov bx, PLX
    mov cx, [pyL]
    mov dx, PAD_W
    mov si, PAD_H
    GUI API_FILL

    mov al, 12                  ; cpu paddle
    mov bx, CPX
    mov cx, [pyR]
    mov dx, PAD_W
    mov si, PAD_H
    GUI API_FILL

    mov al, 15                  ; ball
    mov bx, [balx]
    mov cx, [baly]
    test bx, bx
    jns .bx
    xor bx, bx
.bx:
    test cx, cx
    jns .by
    xor cx, cx
.by:
    mov dx, BALL
    mov si, BALL
    GUI API_FILL

    mov al, 10                  ; scores
    mov bx, 70
    mov cx, 6
    mov dx, [scoreL]
    GUI API_NUM

    mov al, 12
    mov bx, 156
    mov cx, 6
    mov dx, [scoreR]
    GUI API_NUM

    cmp byte [over], 0
    je .notover
    mov si, s_lose
    cmp word [scoreL], WINSCORE
    jb .show
    mov si, s_win
.show:
    mov bx, 36
    mov cx, 70
    mov dl, 14
    GUI API_STR
    jmp .hint
.notover:
    cmp byte [paused], 0
    je .hint
    mov si, s_pause
    mov bx, 96
    mov cx, 70
    mov dl, 14
    GUI API_STR
.hint:
    mov si, s_hint
    mov bx, 4
    mov cx, H-9
    mov dl, 8
    GUI API_STR
    xor al, al
    retf

; ============================================================
;  data
; ============================================================
paused  db 0
over    db 0
snd     dw 0
scoreL  dw 0
scoreR  dw 0
pyL     dw 0
pyR     dw 0
balx    dw 0
baly    dw 0
balvx   dw 0
balvy   dw 0
yy      dw 0

s_win   db "YOU WIN!  R = new", 0
s_lose  db "CPU WINS  R = new", 0
s_pause db "PAUSED", 0
s_hint  db "Up/Down  Space Pause  R New", 0
