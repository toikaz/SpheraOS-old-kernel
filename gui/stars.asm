; ============================================================
;  stars.asm - flying through a starfield for SpheraOS GUI
;  nasm -f bin -I gui/ stars.asm -o asm/stars.app
;  Space = pause, +/- = speed, R = restart, Esc = quit.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Stars", 200, 150

NSTARS equ 90
SCX   equ 100
SCY   equ 75

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
    mov word [rseed], 0x1234
    mov byte [speed], 3
    mov byte [paused], 0
    mov word [bidx], 0
.spawnall:
    cmp word [bidx], NSTARS
    jae .done
    mov bx, [bidx]
    call spawn
    inc word [bidx]
    jmp .spawnall
.done:
    xor al, al
    retf

; own small random generator: BX = n -> AX = 0..n-1
rnd:
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

; spawn the star whose byte index is in BX
spawn:
    push bx
    shl bx, 1                   ; word index
    mov si, bx
    mov bx, 241
    call rnd
    sub ax, 120
    mov [sx+si], ax
    mov bx, 181
    call rnd
    sub ax, 90
    mov [sy+si], ax
    mov bx, 255
    call rnd
    inc ax
    pop si                      ; SI = byte index
    mov di, si
    mov [sz+di], al
    mov byte [lx+di], 255
    call recalc
    jc .off
    ret
.off:
    mov byte [lx+si], 255
    ret

; recalc: SI = word index, DI = byte index -> updates nx/ny, CF if offscreen
recalc:
    mov ax, [sx+si]
    mov bx, 100
    imul bx                     ; DX:AX = sx*100
    mov cx, 0
    mov cl, [sz+di]
    cwd
    idiv cx
    add ax, SCX
    mov [tmpnx], ax

    mov ax, [sy+si]
    mov bx, 100
    imul bx
    cwd
    idiv cx
    add ax, SCY
    mov [tmpny], ax

    cmp word [tmpnx], 0
    jl .off
    cmp word [tmpnx], 199
    ja .off
    cmp word [tmpny], 0
    jl .off
    cmp word [tmpny], 149
    ja .off
    mov ax, [tmpnx]
    mov [nx+di], al
    mov ax, [tmpny]
    mov [ny+di], al
    clc
    ret
.off:
    stc
    ret

h_tick:
    cmp byte [paused], 0
    jne .r0
    mov word [bidx], 0
.loop:
    cmp word [bidx], NSTARS
    jae .done
    mov si, [bidx]
    shl si, 1                   ; word index
    mov di, [bidx]              ; byte index
    ; remember the last screen position
    mov al, [nx+di]
    mov [lx+di], al
    mov al, [ny+di]
    mov [ly+di], al
    ; move towards the viewer
    mov al, [sz+di]
    sub al, [speed]
    cmp al, 1
    ja .alive
    mov bx, [bidx]              ; BX = byte index
    call spawn                  ; fresh star
    jmp .next
.alive:
    mov [sz+di], al
    call recalc
    jnc .next
    mov byte [lx+di], 255
.next:
    inc word [bidx]
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
    mov bx, 0
    GUI API_SOUND
    GUI API_EXIT
    xor al, al
    retf
.k1:
    cmp bh, KEY_SPACE
    jne .k2
    xor byte [paused], 1
    jmp .yes
.k2:
    cmp bl, '+'
    je .fast
    cmp bl, '='
    je .fast
    cmp bl, '-'
    je .slow
    cmp bl, 'r'
    je .restart
    cmp bl, 'R'
    jne .no
.restart:
    mov word [rseed], 0x1234
    mov word [bidx], 0
.rs:
    cmp word [bidx], NSTARS
    jae .yes
    mov bx, [bidx]
    call spawn
    inc word [bidx]
    jmp .rs
.fast:
    cmp byte [speed], 8
    jae .no
    inc byte [speed]
    jmp .yes
.slow:
    cmp byte [speed], 1
    jbe .no
    dec byte [speed]
.yes:
    mov al, 1
    retf
.no:
    xor al, al
    retf

h_draw:
    xor al, al
    GUI API_CLEAR
    mov word [bidx], 0
.d:
    cmp word [bidx], NSTARS
    jae .hint
    mov di, [bidx]
    ; colour depends on depth
    mov al, [sz+di]
    cmp al, 50
    jb .c15
    cmp al, 110
    jb .c9
    mov al, 7
    jmp .col
.c15:
    mov al, 15
    jmp .col
.c9:
    mov al, 9
.col:
    mov [scol], al
    cmp byte [lx+di], 255
    je .cur
    ; halfway point of the trail
    mov al, [lx+di]
    xor ah, ah
    mov bl, [nx+di]
    xor bh, bh
    add ax, bx
    shr ax, 1
    mov [tpx], al
    mov al, [ly+di]
    xor ah, ah
    mov bl, [ny+di]
    xor bh, bh
    add ax, bx
    shr ax, 1
    mov [tpy], al
    mov al, [scol]
    xor bx, bx
    mov bl, [tpx]
    xor cx, cx
    mov cl, [tpy]
    GUI API_PIX
    ; older position, dimmer
    mov al, 8
    xor bx, bx
    mov bl, [lx+di]
    xor cx, cx
    mov cl, [ly+di]
    GUI API_PIX
.cur:
    mov al, [scol]
    xor bx, bx
    mov bl, [nx+di]
    xor cx, cx
    mov cl, [ny+di]
    GUI API_PIX
    inc word [bidx]
    jmp .d
.hint:
    mov si, s_hint
    mov bx, 4
    mov cx, 142
    mov dl, 14
    GUI API_STR
    xor al, al
    retf

; ------------------------------------------------------------
speed   db 3
paused  db 0
rseed   dw 0
bidx    dw 0
tmpnx   dw 0
tmpny   dw 0
tpx     dw 0
tpy     dw 0
scol    db 0

sx      times NSTARS dw 0
sy      times NSTARS dw 0
sz      times NSTARS db 0
nx      times NSTARS db 0
ny      times NSTARS db 0
lx      times NSTARS db 0
ly      times NSTARS db 0

s_hint  db "SPACE pause +/- speed R restart", 0
