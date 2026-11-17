; ============================================================
;  music.asm - little tune player for SpheraOS GUI
;  nasm -f bin -I gui/ music.asm -o asm/music.app
;  1/2/3 = select song, Space = play/pause, Esc = quit.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Music", 200, 140

C5 equ 143
D5 equ 127
EE equ 113
F5 equ 107
G5 equ 95
A5 equ 85
B5 equ 76
C6 equ 71
RR equ 0

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
    cmp ax, MSG_CLOSE
    je near h_close
    xor al, al
    retf

h_init:
    mov byte [song], 0
    mov word [idx], 0
    mov byte [remaining], 0
    mov byte [playing], 0
    mov byte [dcount], 0
    mov word [divv], 0
    mov bx, 0
    GUI API_SOUND
    xor al, al
    retf

h_close:
    mov bx, 0
    GUI API_SOUND
    xor al, al
    retf

h_tick:
    cmp byte [playing], 0
    je .r0
    cmp byte [remaining], 0
    je .fetch
    dec byte [remaining]
    jnz .show
    mov bx, 0
    GUI API_SOUND              ; short gap between notes
    jmp .show
.fetch:
    movzx bx, byte [song]
    shl bx, 1
    mov si, [songt+bx]
    mov di, [songl+bx]
    cmp word [idx], di
    jb .have
    mov word [idx], 0
    mov si, [songt+bx]
.have:
    mov ax, [idx]
    shl ax, 1
    add si, ax
    lodsw
    mov [note], ax
    mov [remaining], al
    mov dl, ah
    xor dh, dh
    shl dx, 4
    mov [divv], dx
    mov bx, dx
    GUI API_SOUND
    inc word [idx]
.show:
    inc byte [dcount]
    cmp byte [dcount], 3
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
    mov bx, 0
    GUI API_SOUND
    GUI API_EXIT
    xor al, al
    retf
.k1:
    cmp bl, '1'
    je .s0
    cmp bl, '2'
    je .s1
    cmp bl, '3'
    je .s2
    cmp bh, KEY_SPACE
    je .toggle
    jmp .no
.s0:
    mov byte [song], 0
    jmp .start
.s1:
    mov byte [song], 1
    jmp .start
.s2:
    mov byte [song], 2
.start:
    mov word [idx], 0
    mov byte [remaining], 0
    mov byte [playing], 1
    jmp .yes
.toggle:
    xor byte [playing], 1
    cmp byte [playing], 0
    jne .yes
    mov bx, 0
    GUI API_SOUND
    jmp .yes
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
    mov cx, 8
    mov dl, 14
    GUI API_STR

    mov si, s_song
    mov bx, 16
    mov cx, 24
    mov dl, 15
    GUI API_STR
    mov al, 15
    mov bx, 58
    mov cx, 24
    xor dx, dx
    mov dl, [song]
    inc dx
    GUI API_NUM

    cmp byte [playing], 0
    je .paused
    mov si, s_play
    mov bx, 16
    mov cx, 40
    mov dl, 10
    GUI API_STR
    jmp .bars
.paused:
    mov si, s_pause
    mov bx, 16
    mov cx, 40
    mov dl, 8
    GUI API_STR

.bars:
    GUI API_TICKS
    mov [tm], ax
    mov byte [bi], 0
.barloop:
    cmp byte [bi], 8
    jae .hint
    mov ax, [tm]
    movzx bx, byte [bi]
    imul bx, bx, 7
    add ax, bx
    xor dx, dx
    mov bp, 17
    div bp
    mov bx, dx
    add bx, 4
    mov [bhgt], bx
    mov ax, 88
    sub ax, bx
    mov [btop], ax
    movzx ax, byte [bi]
    imul ax, ax, 20
    add ax, 16
    mov [bxx], ax
    mov al, 10
    mov bx, [bxx]
    mov cx, [btop]
    mov dx, 16
    mov si, [bhgt]
    GUI API_FILL
    mov al, 15
    mov bx, [bxx]
    mov cx, [btop]
    mov dx, 16
    mov si, 1
    GUI API_FILL
    inc byte [bi]
    jmp .barloop
.hint:
    mov si, s_hint1
    mov bx, 16
    mov cx, 112
    mov dl, 15
    GUI API_STR
    mov si, s_hint2
    mov bx, 16
    mov cx, 122
    mov dl, 8
    GUI API_STR
    xor al, al
    retf

; ------------------------------------------------------------
song    db 0
idx     dw 0
remaining db 0
playing db 0
dcount  db 0
note    dw 0
divv    dw 0
tm      dw 0
bi      db 0
bhgt    dw 0
btop    dw 0
bxx     dw 0

songt   dw song1, song2, song3
songl   dw song1_len, song2_len, song3_len

s_title db "SPHERA TUNES", 0
s_song  db "SONG", 0
s_play  db "PLAY", 0
s_pause db "PAUSE", 0
s_hint1 db "1/2/3 = song   SPACE = play", 0
s_hint2 db "Esc = quit", 0

; --- 1: Twinkle ---------------------------------------------
song1:
        dw (C5<<8)|6
      dw (C5<<8)|6
      dw (G5<<8)|6
      dw (G5<<8)|6
      dw (A5<<8)|6
      dw (A5<<8)|6
      dw (G5<<8)|12

        dw (F5<<8)|6
      dw (F5<<8)|6
      dw (EE<<8)|6
      dw (EE<<8)|6
      dw (D5<<8)|6
      dw (D5<<8)|6
      dw (C5<<8)|12

        dw (G5<<8)|6
      dw (G5<<8)|6
      dw (F5<<8)|6
      dw (F5<<8)|6
      dw (EE<<8)|6
      dw (EE<<8)|6
      dw (D5<<8)|12

        dw (G5<<8)|6
      dw (G5<<8)|6
      dw (F5<<8)|6
      dw (F5<<8)|6
      dw (EE<<8)|6
      dw (EE<<8)|6
      dw (D5<<8)|12

        dw (C5<<8)|6
      dw (C5<<8)|6
      dw (G5<<8)|6
      dw (G5<<8)|6
      dw (A5<<8)|6
      dw (A5<<8)|6
      dw (G5<<8)|12

        dw (F5<<8)|6
      dw (F5<<8)|6
      dw (EE<<8)|6
      dw (EE<<8)|6
      dw (D5<<8)|6
      dw (D5<<8)|6
      dw (C5<<8)|12

song1_end:
song1_len equ (song1_end-song1)/2

; --- 2: up and down the scale -------------------------------
song2:
        dw (C5<<8)|4
      dw (D5<<8)|4
      dw (EE<<8)|4
      dw (F5<<8)|4
      dw (G5<<8)|4
      dw (A5<<8)|4
      dw (B5<<8)|4
      dw (C6<<8)|8

        dw (C6<<8)|4
      dw (B5<<8)|4
      dw (A5<<8)|4
      dw (G5<<8)|4
      dw (F5<<8)|4
      dw (EE<<8)|4
      dw (D5<<8)|4
      dw (C5<<8)|8

        dw (C5<<8)|2
      dw (EE<<8)|2
      dw (G5<<8)|2
      dw (C6<<8)|4
      dw (G5<<8)|2
      dw (EE<<8)|2
      dw (C5<<8)|8

song2_end:
song2_len equ (song2_end-song2)/2

; --- 3: arpeggio --------------------------------------------
song3:
        dw (C5<<8)|3
      dw (EE<<8)|3
      dw (G5<<8)|3
      dw (C6<<8)|6
      dw (G5<<8)|3
      dw (EE<<8)|3

        dw (C5<<8)|3
      dw (EE<<8)|3
      dw (G5<<8)|3
      dw (C6<<8)|6
      dw (G5<<8)|3
      dw (EE<<8)|3

        dw (D5<<8)|3
      dw (F5<<8)|3
      dw (A5<<8)|3
      dw (C6<<8)|6
      dw (A5<<8)|3
      dw (F5<<8)|3

        dw (C5<<8)|3
      dw (EE<<8)|3
      dw (G5<<8)|3
      dw (C6<<8)|12

song3_end:
song3_len equ (song3_end-song3)/2
