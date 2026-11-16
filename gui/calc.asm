; ============================================================
;  calc.asm - Calculator for SpheraOS GUI (arrow navigation)
;  Build:  nasm -f bin calc.asm -o CALC.APP
;  Copy CALC.APP to the disk, open Files, press Enter on it.
;
;  Keys: Arrows move cursor, Enter press button, Esc exit.
;  Grid: 7 8 9 /  4 5 6 *  1 2 3 -  0 C = +
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Calc", 152, 108

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
    mov word [sel_x], 0
    mov word [sel_y], 0
    call calc_reset
    xor al, al
    retf

calc_reset:
    xor ax, ax
    mov [ent], ax
    mov [acc], ax
    mov [op], al
    mov [ent_new], al
    mov [errf], al
    ret

; ------------------------------------------------------------
; key handling: BL = ascii, BH = scan
; Only arrows + Enter + Esc are handled
; ------------------------------------------------------------
h_key:
    cmp bh, KEY_ESC
    jne .k1
    GUI API_EXIT
    xor al, al
    retf
.k1:
    cmp byte [errf], 0
    je .ok0
    call calc_reset
    mov al, 1
    retf
.ok0:
    cmp bh, KEY_LEFT
    jne .kr
    cmp word [sel_x], 0
    je .nodone
    dec word [sel_x]
    jmp .redraw
.kr:
    cmp bh, KEY_RIGHT
    jne .ku
    cmp word [sel_x], 3
    jae .nodone
    inc word [sel_x]
    jmp .redraw
.ku:
    cmp bh, KEY_UP
    jne .kd
    cmp word [sel_y], 0
    je .nodone
    dec word [sel_y]
    jmp .redraw
.kd:
    cmp bh, KEY_DOWN
    jne .ke
    cmp word [sel_y], 3
    jae .nodone
    inc word [sel_y]
    jmp .redraw
.ke:
    cmp bh, KEY_ENTER
    jne .nodone
    jmp .do_action
.redraw:
    mov al, 1
    retf
.nodone:
    xor al, al
    retf

; ------------------------------------------------------------
; press the currently selected button
; index = sel_y*4 + sel_x, button char = btns_t[index]
; ------------------------------------------------------------
.do_action:
    mov ax, [sel_y]
    shl ax, 2
    add ax, [sel_x]
    mov bx, ax
    ; special buttons
    cmp bx, 13
    je .clr
    cmp bx, 14
    je .equals
    ; get char
    mov al, [btns_t+bx]
    ; digit?
    cmp al, '0'
    jb .op
    cmp al, '9'
    ja .op
    ; ---- digit ----
    sub al, '0'
    xor ah, ah
    mov bx, ax
    ; if fresh after operator/reset — replace ent
    cmp byte [ent_new], 0
    jne .append
    xor ax, ax
    mov [ent], ax
.append:
    cmp word [ent], 3276
    jg .done
    cmp word [ent], -3276
    jl .done
    mov ax, [ent]
    imul ax, ax, 10
    add ax, bx
    mov [ent], ax
    mov byte [ent_new], 1
    jmp .done
.op:
    ; ---- operator ----
    mov cl, 1
    cmp al, '+'
    je .setop
    mov cl, 2
    cmp al, '-'
    je .setop
    mov cl, 3
    cmp al, '*'
    je .setop
    mov cl, 4
.setop:
    cmp byte [ent_new], 0
    je .replace
    cmp byte [op], 0
    jne .chain
    mov ax, [ent]
    mov [acc], ax
    mov byte [ent_new], 0
    jmp .replace
.chain:
    call compute
    jc .divz
    mov byte [ent_new], 0
.replace:
    mov [op], cl
    jmp .done
.clr:
    call calc_reset
    jmp .done
.equals:
    cmp byte [op], 0
    je .done
    call compute
    jc .divz
    mov byte [op], 0
    mov byte [ent_new], 0
    jmp .done
.divz:
    mov byte [errf], 1
.done:
    mov al, 1
    retf

; ------------------------------------------------------------
; compute: acc = acc [op] ent, ent = acc. CF=1 on divide by zero.
; ------------------------------------------------------------
compute:
    mov ax, [acc]
    mov bx, [ent]
    cmp byte [op], 1
    je .add
    cmp byte [op], 2
    je .sub
    cmp byte [op], 3
    je .mul
    test bx, bx
    jz .bad
    cwd
    idiv bx
    jmp .ok
.add:
    add ax, bx
    jmp .ok
.sub:
    sub ax, bx
    jmp .ok
.mul:
    imul bx
.ok:
    mov [acc], ax
    mov [ent], ax
    clc
    ret
.bad:
    stc
    ret

; ------------------------------------------------------------
; draw
; ------------------------------------------------------------
h_draw:
    mov al, 7
    GUI API_CLEAR
    ; display: dark border, white inside
    mov al, 8
    mov bx, 4
    mov cx, 4
    mov dx, 144
    mov si, 16
    GUI API_FILL
    mov al, 15
    mov bx, 5
    mov cx, 5
    mov dx, 142
    mov si, 14
    GUI API_FILL
    cmp byte [errf], 0
    jne .eerr
    mov ax, [ent]
    call itoa
    mov bx, 8
    mov cx, 7
    mov dl, 0
    GUI API_STR
    jmp .btns
.eerr:
    mov si, s_err
    mov bx, 8
    mov cx, 7
    mov dl, 12
    GUI API_STR
.btns:
    mov word [i], 0
.bl:
    mov ax, [i]
    cmp ax, 16
    jae .cursor
    ; col = i & 3, row = i >> 2
    mov bx, ax
    and bx, 3
    imul bx, bx, 36
    add bx, 4
    mov [bt_x], bx
    mov bx, ax
    shr bx, 2
    imul bx, bx, 16
    add bx, 26
    mov [bt_y], bx
    ; outer frame
    mov al, 8
    mov bx, [bt_x]
    mov cx, [bt_y]
    mov dx, 32
    mov si, 12
    GUI API_FILL
    ; inner
    mov bx, [i]
    mov al, [bcol+bx]
    mov bx, [bt_x]
    inc bx
    mov cx, [bt_y]
    inc cx
    mov dx, 30
    mov si, 10
    GUI API_FILL
    ; label color: dark on gray, white on colored
    mov bx, [i]
    mov dl, 15
    cmp byte [bcol+bx], 7
    jne .cc
    mov dl, 0
.cc:
    mov bx, [i]
    mov al, [btns_t+bx]
    mov bx, [bt_x]
    add bx, 12
    mov cx, [bt_y]
    add cx, 2
    GUI API_CHAR
    inc word [i]
    jmp .bl

; ---- cursor: yellow frame around selected button ----
.cursor:
    mov bx, [sel_x]
    imul bx, bx, 36
    add bx, 4
    dec bx
    mov [bt_x], bx
    mov bx, [sel_y]
    imul bx, bx, 16
    add bx, 26
    dec bx
    mov [bt_y], bx
    ; top edge
    mov al, 14
    mov bx, [bt_x]
    mov cx, [bt_y]
    mov dx, 34
    mov si, 1
    GUI API_FILL
    ; bottom edge
    mov al, 14
    mov bx, [bt_x]
    mov cx, [bt_y]
    add cx, 13
    mov dx, 34
    mov si, 1
    GUI API_FILL
    ; left edge
    mov al, 14
    mov bx, [bt_x]
    mov cx, [bt_y]
    mov dx, 1
    mov si, 14
    GUI API_FILL
    ; right edge
    mov al, 14
    mov bx, [bt_x]
    add bx, 33
    mov cx, [bt_y]
    mov dx, 1
    mov si, 14
    GUI API_FILL

.hint:
    mov si, s_hint
    mov bx, 4
    mov cx, 96
    mov dl, 0
    GUI API_STR
    mov al, 1
    retf

; itoa: AX signed -> SI = pointer into dispbuf (asciiz)
itoa:
    push bx
    push cx
    push dx
    push di
    xor cl, cl
    test ax, ax
    jns .p
    mov cl, 1
    neg ax
.p:
    mov di, dispbuf+7
    mov byte [di], 0
    mov bx, 10
.l:
    xor dx, dx
    div bx
    add dl, '0'
    dec di
    mov [di], dl
    test ax, ax
    jnz .l
    test cl, cl
    jz .r
    dec di
    mov byte [di], '-'
.r:
    mov si, di
    pop di
    pop dx
    pop cx
    pop bx
    ret

; ------------------------------------------------------------
; data
; ------------------------------------------------------------
ent      dw 0
acc      dw 0
op       db 0
ent_new  db 0
errf     db 0
i        dw 0
bt_x     dw 0
bt_y     dw 0
sel_x    dw 0
sel_y    dw 0

dispbuf  times 8 db 0
btns_t   db "789/456*123-0C=+"
bcol     db 7,7,7,3, 7,7,7,3, 7,7,7,3, 7,12,9,3
s_err    db "Err", 0
s_hint   db "Arrows Enter Esc", 0