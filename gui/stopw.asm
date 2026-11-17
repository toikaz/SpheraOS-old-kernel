; ============================================================
;  stopwatch.asm - stopwatch with lap times for SpheraOS GUI
;  nasm -f bin -I gui/ stopwatch.asm -o asm/stopwatch.app
;  Space = start/stop, L = lap, R = reset, Esc = quit.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Stopwatch", 160, 112

NMAX equ 8

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

; AX = ticks -> SI = "MM:SS.HH" asciiz
fmt_time:
    push bx
    push cx
    push dx
    push di
    mov di, tbuf
    mov bx, 55
    mul bx                      ; DX:AX = ticks * 55
    mov bx, 10
    div bx                      ; AX = hundredths
    xor dx, dx
    mov bx, 6000
    div bx                      ; AX = minutes, DX = rest
    call put2
    mov byte [di], ':'
    inc di
    mov ax, dx
    xor dx, dx
    mov bx, 100
    div bx                      ; AX = seconds, DX = hundredths
    call put2
    mov byte [di], '.'
    inc di
    mov ax, dx
    call put2
    mov byte [di], 0
    mov si, tbuf
    pop di
    pop dx
    pop cx
    pop bx
    ret

put2:                           ; AL = 0..99 -> two digits at DI
    xor ah, ah
    mov bl, 10
    div bl
    add al, '0'
    mov [di], al
    inc di
    mov al, ah
    add al, '0'
    mov [di], al
    inc di
    ret

h_init:
    mov word [ticks], 0
    mov byte [running], 0
    mov byte [nlaps], 0
    xor al, al
    retf

h_tick:
    cmp byte [running], 0
    je .r0
    inc word [ticks]
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
    je .startstop
    cmp bl, 'l'
    je .lap
    cmp bl, 'L'
    je .lap
    cmp bl, 'r'
    je .reset
    cmp bl, 'R'
    jne .no
.reset:
    mov word [ticks], 0
    mov byte [running], 0
    mov byte [nlaps], 0
    jmp .yes
.startstop:
    xor byte [running], 1
    jmp .yes
.lap:
    cmp byte [running], 0
    je .no
    movzx bx, byte [nlaps]
    cmp bx, NMAX
    jae .no
    mov ax, [ticks]
    shl bx, 1
    add bx, laps
    mov [bx], ax
    inc byte [nlaps]
.yes:
    mov al, 1
    retf
.no:
    xor al, al
    retf

h_draw:
    mov al, 1
    GUI API_CLEAR

    mov si, s_title
    mov bx, 40
    mov cx, 4
    mov dl, 14
    GUI API_STR

    mov ax, [ticks]
    call fmt_time
    mov bx, 40
    mov cx, 20
    mov dl, 15
    GUI API_STR

    cmp byte [running], 0
    je .stopped
    mov si, s_run
    mov bx, 104
    mov cx, 20
    mov dl, 10
    GUI API_STR
    jmp .laps
.stopped:
    mov si, s_stop
    mov bx, 104
    mov cx, 20
    mov dl, 8
    GUI API_STR

.laps:
    mov si, s_laps
    mov bx, 8
    mov cx, 36
    mov dl, 15
    GUI API_STR
    mov byte [li], 0
.lloop:
    cmp byte [li], NMAX
    jae .hint
    movzx bx, byte [li]
    cmp bl, [nlaps]
    jae .hint
    shl bx, 1
    add bx, laps
    mov ax, [bx]
    call fmt_time
    movzx ax, byte [li]
    imul ax, ax, 8
    add ax, 36
    mov cx, ax
    mov bx, 56
    mov dl, 10
    GUI API_STR
    inc byte [li]
    jmp .lloop
.hint:
    mov si, s_hint
    mov bx, 4
    mov cx, 104
    mov dl, 8
    GUI API_STR
    xor al, al
    retf

; ------------------------------------------------------------
ticks   dw 0
running db 0
nlaps   db 0
li      db 0
tbuf    times 12 db 0
laps    times NMAX dw 0

s_title db "STOPWATCH", 0
s_run   db "RUN", 0
s_stop  db "STOP", 0
s_laps  db "LAPS", 0
s_hint  db "SPACE go  L lap  R reset", 0
