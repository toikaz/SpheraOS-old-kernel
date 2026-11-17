; ============================================================
;  chess.asm - SpheraOS Chess in the GUI
;  nasm -f bin -I gui/ chess.asm -o asm/chess.app
;  The rules engine is ported from asm/chess.asm; drawing and
;  input use the INT 60h GUI API.  No OS code is modified.
;
;  Arrows = cursor, Enter = select / move, Esc = cancel / close,
;  R = new game, U = undo, M = hints, B = bot, C = bot side.
; ============================================================
BITS 16
ORG 0
%include "sdk.inc"

APP_HEADER "Chess", 252, 164

P_PAWN   equ 1
P_KNIGHT equ 2
P_BISHOP equ 3
P_ROOK   equ 4
P_QUEEN  equ 5
P_KING   equ 6
WHITE    equ 0
BLACK    equ 8
VAL_PAWN   equ 100
VAL_KNIGHT equ 320
VAL_BISHOP equ 330
VAL_ROOK   equ 500
VAL_QUEEN  equ 900
VAL_KING   equ 20000
CELL equ 17
BX0  equ 10
BY0  equ 16

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
    mov byte [bot_on], 0
    mov byte [bot_color], BLACK
    GUI API_TICKS
    mov [rand_seed], ax
    call new_game
    xor al, al
    retf

h_close:
    mov bx, 0
    GUI API_SOUND
    xor al, al
    retf

h_tick:
    ; short beep timer
    cmp byte [sndtimer], 0
    je .nosnd
    dec byte [sndtimer]
    jnz .nosnd
    mov bx, 0
    GUI API_SOUND
.nosnd:
    ; the bot thinks once in a while, not every tick
    cmp byte [bot_on], 0
    je .r0
    cmp byte [gameover], 0
    jne .r0
    mov al, [turn]
    cmp al, [bot_color]
    jne .r0
    inc byte [botdelay]
    cmp byte [botdelay], 10
    jb .r0
    mov byte [botdelay], 0
    call bot_move
    mov al, 1
    retf
.r0:
    xor al, al
    retf

; ------------------------------------------------------------
;  keyboard
; ------------------------------------------------------------
h_key:
    cmp bh, KEY_ESC
    jne .k1
    cmp byte [selected], 0xFF
    jne .clear_sel
    mov bx, 0
    GUI API_SOUND
    GUI API_EXIT
    xor al, al
    retf
.clear_sel:
    mov byte [selected], 0xFF
    jmp .redraw
.k1:
    cmp bl, 'r'
    je .restart
    cmp bl, 'R'
    je .restart
    cmp bl, 'u'
    je .undo
    cmp bl, 'U'
    je .undo
    cmp bl, 'm'
    je .hints
    cmp bl, 'M'
    je .hints
    cmp bl, 'b'
    je .bot
    cmp bl, 'B'
    je .bot
    cmp bl, 'c'
    je .swap
    cmp bl, 'C'
    je .swap
    cmp bh, KEY_LEFT
    jne .kr
    mov al, [cursor]
    and al, 7
    test al, al
    jz .no
    dec byte [cursor]
    jmp .redraw
.kr:
    cmp bh, KEY_RIGHT
    jne .ku
    mov al, [cursor]
    and al, 7
    cmp al, 7
    jae .no
    inc byte [cursor]
    jmp .redraw
.ku:
    cmp bh, KEY_UP
    jne .kd
    cmp byte [cursor], 8
    jb .no
    sub byte [cursor], 8
    jmp .redraw
.kd:
    cmp bh, KEY_DOWN
    jne .enter
    cmp byte [cursor], 56
    jae .no
    add byte [cursor], 8
    jmp .redraw
.enter:
    cmp bh, KEY_ENTER
    jne .no
    cmp bl, ' '
    jne .doenter
.doenter:
    cmp byte [gameover], 0
    jne .no
    cmp byte [bot_on], 0
    je .normal
    mov al, [turn]
    cmp al, [bot_color]
    je .no
.normal:
    cmp byte [selected], 0xFF
    je .select
    mov al, [selected]
    mov [move_from], al
    mov al, [cursor]
    mov [move_to], al
    cmp al, [move_from]
    jne .try
    mov byte [selected], 0xFF
    jmp .redraw
.try:
    call is_legal_move_test
    test al, al
    jz .bad
    call do_move
    call make_beep
    call check_gameover
    cmp byte [gameover], 0
    je .aftermove
    cmp byte [check_sq], 0xFF
    je .aftermove
    mov bx, 400
    GUI API_SOUND
    mov byte [sndtimer], 8
.aftermove:
    jmp .redraw
.bad:
    movzx si, byte [cursor]
    mov al, [board+si]
    test al, al
    jz .clear
    mov ah, al
    and ah, 8
    cmp ah, [turn]
    jne .clear
    mov al, [cursor]
    mov [selected], al
    call build_hints
    jmp .redraw
.clear:
    mov byte [selected], 0xFF
    jmp .redraw
.select:
    movzx si, byte [cursor]
    mov al, [board+si]
    test al, al
    jz .no
    mov ah, al
    and ah, 8
    cmp ah, [turn]
    jne .no
    mov al, [cursor]
    mov [selected], al
    call build_hints
    jmp .redraw
.restart:
    call new_game
    jmp .redraw
.undo:
    call undo_move
    jmp .redraw
.hints:
    xor byte [show_hints], 1
    jmp .redraw
.bot:
    xor byte [bot_on], 1
    mov byte [botdelay], 0
    cmp byte [bot_on], 0
    je .redraw
    mov al, [turn]
    xor al, 8
    mov [bot_color], al
    jmp .redraw
.swap:
    cmp byte [bot_on], 0
    je .no
    xor byte [bot_color], 8
    jmp .redraw
.redraw:
    mov al, 1
    retf
.no:
    xor al, al
    retf

make_beep:
    movzx si, byte [move_to]
    mov al, [board+si]
    test al, al
    jz .quiet
    mov bx, 600
    GUI API_SOUND
    mov byte [sndtimer], 3
    ret
.quiet:
    mov bx, 1200
    GUI API_SOUND
    mov byte [sndtimer], 2
    ret

; precompute legal target squares for the selected piece
build_hints:
    mov di, hints
    mov cx, 64
    xor al, al
    rep stosb
    cmp byte [selected], 0xFF
    je .done
    mov al, [selected]
    mov [move_from], al
    xor dx, dx
.try:
    cmp dx, 64
    jae .done
    cmp dl, [selected]
    je .next
    mov al, dl
    mov [move_to], al
    push dx
    call is_legal_move_test
    pop dx
    test al, al
    jz .next
    movzx bx, dl
    mov byte [hints+bx], 1
.next:
    inc dx
    jmp .try
.done:
    ret

; ============================================================
;  RULES ENGINE  (ported from asm/chess.asm)
; ============================================================
new_game:
    mov di, board
    mov cx, 32
    xor ax, ax
    rep stosw
    mov byte [board+0],  P_ROOK   | BLACK
    mov byte [board+1],  P_KNIGHT | BLACK
    mov byte [board+2],  P_BISHOP | BLACK
    mov byte [board+3],  P_QUEEN  | BLACK
    mov byte [board+4],  P_KING   | BLACK
    mov byte [board+5],  P_BISHOP | BLACK
    mov byte [board+6],  P_KNIGHT | BLACK
    mov byte [board+7],  P_ROOK   | BLACK
    mov cx, 8
    mov bx, 8
.bl:
    mov byte [board+bx], P_PAWN | BLACK
    inc bx
    loop .bl
    mov cx, 8
    mov bx, 48
.wl:
    mov byte [board+bx], P_PAWN | WHITE
    inc bx
    loop .wl
    mov byte [board+56], P_ROOK   | WHITE
    mov byte [board+57], P_KNIGHT | WHITE
    mov byte [board+58], P_BISHOP | WHITE
    mov byte [board+59], P_QUEEN  | WHITE
    mov byte [board+60], P_KING   | WHITE
    mov byte [board+61], P_BISHOP | WHITE
    mov byte [board+62], P_KNIGHT | WHITE
    mov byte [board+63], P_ROOK   | WHITE
    mov byte [turn], WHITE
    mov byte [selected], 0xFF
    mov byte [cursor], 52
    mov byte [check_sq], 0xFF
    mov byte [gameover], 0
    mov byte [last_from], 0xFF
    mov byte [last_to], 0xFF
    mov byte [ep_sq], 0xFF
    mov byte [castling], 0x0F
    mov byte [show_hints], 1
    mov word [hist_count], 0
    mov word [msg], 0
    mov byte [bot_strategy], 0
    mov byte [botdelay], 0
    call build_hints
    ret

rand:
    push dx
    mov ax, [rand_seed]
    mov dx, 25173
    mul dx
    add ax, 13849
    mov [rand_seed], ax
    pop dx
    ret

is_legal_move:
    movzx si, byte [move_from]
    mov al, [board+si]
    test al, al
    jz .no
    mov ah, al
    and ah, 8
    cmp ah, [turn]
    jne .no
    movzx di, byte [move_to]
    mov bl, [board+di]
    test bl, bl
    jz .ok
    mov ah, bl
    and ah, 8
    cmp ah, [turn]
    je .no
.ok:
    and al, 7
    cmp al, P_PAWN
    je .pawn
    cmp al, P_KNIGHT
    je .knight
    cmp al, P_BISHOP
    je .bishop
    cmp al, P_ROOK
    je .rook
    cmp al, P_QUEEN
    je .queen
    cmp al, P_KING
    je .king
.no:
    xor al, al
    ret
.pawn:
    call check_pawn
    ret
.knight:
    call check_knight
    ret
.bishop:
    call check_bishop
    ret
.rook:
    call check_rook
    ret
.queen:
    call check_queen
    ret
.king:
    call check_castle
    test al, al
    jnz .ok_king
    call check_king
.ok_king:
    ret

check_pawn:
    movzx si, byte [move_from]
    movzx di, byte [move_to]
    mov cx, -8
    cmp byte [turn], WHITE
    je .dir
    mov cx, 8
.dir:
    mov ax, si
    add ax, cx
    cmp ax, di
    jne .try_double
    mov al, [board+di]
    test al, al
    jz .ok
    jmp .no
.try_double:
    mov ax, si
    add ax, cx
    add ax, cx
    cmp ax, di
    jne .try_capture
    cmp byte [turn], WHITE
    jne .td_black
    cmp si, 48
    jb .no
    cmp si, 55
    ja .no
    jmp .td_inter
.td_black:
    cmp si, 8
    jb .no
    cmp si, 15
    ja .no
.td_inter:
    mov ax, si
    add ax, cx
    mov bx, ax
    mov al, [board+bx]
    test al, al
    jnz .no
    mov al, [board+di]
    test al, al
    jnz .no
    jmp .ok
.try_capture:
    mov ax, si
    add ax, cx
    mov bx, ax
    mov al, bl
    and al, 7
    test al, al
    jz .try_right
    mov ax, bx
    dec ax
    cmp ax, di
    jne .try_right
    mov al, [board+di]
    test al, al
    jz .ep_left
    mov ah, al
    and ah, 8
    cmp ah, [turn]
    je .no
    jmp .ok
.ep_left:
    mov al, [ep_sq]
    cmp al, [move_to]
    je .ok
    jmp .no
.try_right:
    mov al, bl
    and al, 7
    cmp al, 7
    je .no
    mov ax, bx
    inc ax
    cmp ax, di
    jne .no
    mov al, [board+di]
    test al, al
    jz .ep_right
    mov ah, al
    and ah, 8
    cmp ah, [turn]
    je .no
    jmp .ok
.ep_right:
    mov al, [ep_sq]
    cmp al, [move_to]
    je .ok
    jmp .no
.ok:
    mov al, 1
    ret
.no:
    xor al, al
    ret

check_knight:
    movzx ax, byte [move_from]
    movzx bx, byte [move_to]
    mov cx, ax
    and cx, 7
    mov dx, bx
    and dx, 7
    sub cx, dx
    jns .c1
    neg cx
.c1:
    mov dx, ax
    shr dx, 3
    mov si, bx
    shr si, 3
    sub dx, si
    jns .c2
    neg dx
.c2:
    cmp cx, 1
    jne .m21
    cmp dx, 2
    jne .no
    jmp .ok
.m21:
    cmp cx, 2
    jne .no
    cmp dx, 1
    jne .no
.ok:
    mov al, 1
    ret
.no:
    xor al, al
    ret

check_bishop:
    movzx ax, byte [move_from]
    movzx bx, byte [move_to]
    mov cx, ax
    and cx, 7
    mov dx, bx
    and dx, 7
    sub cx, dx
    jns .c1
    neg cx
.c1:
    mov dx, ax
    shr dx, 3
    mov si, bx
    shr si, 3
    sub dx, si
    jns .c2
    neg dx
.c2:
    cmp cx, dx
    jne .no
    call check_diag_path
    ret
.no:
    xor al, al
    ret

check_rook:
    movzx ax, byte [move_from]
    movzx bx, byte [move_to]
    mov cx, ax
    and cx, 7
    mov dx, bx
    and dx, 7
    cmp cx, dx
    je .vert
    mov cx, ax
    shr cx, 3
    mov dx, bx
    shr dx, 3
    cmp cx, dx
    jne .no
    call check_horiz_path
    ret
.vert:
    call check_vert_path
    ret
.no:
    xor al, al
    ret

check_queen:
    call check_rook
    test al, al
    jnz .ok
    call check_bishop
.ok:
    ret

check_king:
    movzx ax, byte [move_from]
    movzx bx, byte [move_to]
    mov cx, ax
    and cx, 7
    mov dx, bx
    and dx, 7
    sub cx, dx
    jns .c1
    neg cx
.c1:
    mov dx, ax
    shr dx, 3
    mov si, bx
    shr si, 3
    sub dx, si
    jns .c2
    neg dx
.c2:
    cmp cx, 1
    ja .no
    cmp dx, 1
    ja .no
    mov al, 1
    ret
.no:
    xor al, al
    ret

check_diag_path:
    movzx ax, byte [move_from]
    movzx bx, byte [move_to]
    mov cx, ax
    and cx, 7
    mov dx, bx
    and dx, 7
    cmp cx, dx
    jl .right
    mov si, -1
    jmp .dc
.right:
    mov si, 1
.dc:
    mov cx, ax
    shr cx, 3
    mov dx, bx
    shr dx, 3
    cmp cx, dx
    jl .down
    mov di, -8
    jmp .dr
.down:
    mov di, 8
.dr:
    mov dx, si
    add dx, di
    movzx ax, byte [move_from]
.loop:
    add ax, dx
    cmp ax, bx
    je .ok
    mov si, ax
    mov al, [board+si]
    test al, al
    jnz .no
    mov ax, si
    jmp .loop
.ok:
    mov al, 1
    ret
.no:
    xor al, al
    ret

check_horiz_path:
    movzx ax, byte [move_from]
    movzx bx, byte [move_to]
    mov cx, ax
    and cx, 7
    mov dx, bx
    and dx, 7
    cmp cx, dx
    jl .right
    mov si, -1
    jmp .step
.right:
    mov si, 1
.step:
    movzx ax, byte [move_from]
.loop:
    add ax, si
    cmp ax, bx
    je .ok
    mov di, ax
    mov al, [board+di]
    test al, al
    jnz .no
    mov ax, di
    jmp .loop
.ok:
    mov al, 1
    ret
.no:
    xor al, al
    ret

check_vert_path:
    movzx ax, byte [move_from]
    movzx bx, byte [move_to]
    mov cx, ax
    shr cx, 3
    mov dx, bx
    shr dx, 3
    cmp cx, dx
    jl .down
    mov si, -8
    jmp .step
.down:
    mov si, 8
.step:
    movzx ax, byte [move_from]
.loop:
    add ax, si
    cmp ax, bx
    je .ok
    mov di, ax
    mov al, [board+di]
    test al, al
    jnz .no
    mov ax, di
    jmp .loop
.ok:
    mov al, 1
    ret
.no:
    xor al, al
    ret

check_castle:
    movzx si, byte [move_from]
    movzx di, byte [move_to]
    mov al, [board+si]
    mov ah, al
    and ah, 8
    cmp ah, [turn]
    jne .no
    and al, 7
    cmp al, P_KING
    jne .no
    cmp byte [turn], WHITE
    jne .black
    cmp si, 60
    jne .no
    cmp di, 62
    je .wk
    cmp di, 58
    je .wq
    jmp .no
.wk:
    test byte [castling], 0x01
    jz .no
    cmp byte [board+61], 0
    jne .no
    cmp byte [board+62], 0
    jne .no
    cmp byte [board+63], P_ROOK | WHITE
    jne .no
    mov byte [t_sq], 60
    call is_square_attacked
    test al, al
    jnz .no
    mov byte [t_sq], 61
    call is_square_attacked
    test al, al
    jnz .no
    mov byte [t_sq], 62
    call is_square_attacked
    test al, al
    jnz .no
    mov al, 1
    ret
.wq:
    test byte [castling], 0x02
    jz .no
    cmp byte [board+59], 0
    jne .no
    cmp byte [board+58], 0
    jne .no
    cmp byte [board+57], 0
    jne .no
    cmp byte [board+56], P_ROOK | WHITE
    jne .no
    mov byte [t_sq], 60
    call is_square_attacked
    test al, al
    jnz .no
    mov byte [t_sq], 59
    call is_square_attacked
    test al, al
    jnz .no
    mov byte [t_sq], 58
    call is_square_attacked
    test al, al
    jnz .no
    mov al, 1
    ret
.black:
    cmp si, 4
    jne .no
    cmp di, 6
    je .bk
    cmp di, 2
    je .bq
    jmp .no
.bk:
    test byte [castling], 0x04
    jz .no
    cmp byte [board+5], 0
    jne .no
    cmp byte [board+6], 0
    jne .no
    cmp byte [board+7], P_ROOK | BLACK
    jne .no
    mov byte [t_sq], 4
    call is_square_attacked
    test al, al
    jnz .no
    mov byte [t_sq], 5
    call is_square_attacked
    test al, al
    jnz .no
    mov byte [t_sq], 6
    call is_square_attacked
    test al, al
    jnz .no
    mov al, 1
    ret
.bq:
    test byte [castling], 0x08
    jz .no
    cmp byte [board+3], 0
    jne .no
    cmp byte [board+2], 0
    jne .no
    cmp byte [board+1], 0
    jne .no
    cmp byte [board+0], P_ROOK | BLACK
    jne .no
    mov byte [t_sq], 4
    call is_square_attacked
    test al, al
    jnz .no
    mov byte [t_sq], 3
    call is_square_attacked
    test al, al
    jnz .no
    mov byte [t_sq], 2
    call is_square_attacked
    test al, al
    jnz .no
    mov al, 1
    ret
.no:
    xor al, al
    ret

is_square_attacked:
    push bx
    push cx
    push dx
    mov cl, 0
.loop:
    cmp cl, 64
    jae .no
    movzx si, cl
    mov al, [board+si]
    test al, al
    jz .next
    mov ah, al
    and ah, 8
    cmp ah, [turn]
    je .next
    mov [att_from], si
    mov al, [t_sq]
    mov [att_to], al
    push cx
    call piece_attacks_sq
    pop cx
    test al, al
    jnz .yes
.next:
    inc cl
    jmp .loop
.no:
    pop dx
    pop cx
    pop bx
    xor al, al
    ret
.yes:
    pop dx
    pop cx
    pop bx
    mov al, 1
    ret

piece_attacks_sq:
    mov al, [move_from]
    mov [saved_mf], al
    mov al, [move_to]
    mov [saved_mt], al
    mov al, [att_from]
    mov [move_from], al
    mov al, [att_to]
    mov [move_to], al
    movzx si, byte [move_from]
    mov al, [board+si]
    and al, 7
    cmp al, P_PAWN
    je .pawn
    cmp al, P_KNIGHT
    je .kn
    cmp al, P_BISHOP
    je .bi
    cmp al, P_ROOK
    je .ro
    cmp al, P_QUEEN
    je .qu
    cmp al, P_KING
    je .ki
    jmp .restore_no
.pawn:
    call pawn_attacks_sq
    jmp .done
.kn:
    call check_knight
    jmp .done
.bi:
    call check_bishop
    jmp .done
.ro:
    call check_rook
    jmp .done
.qu:
    call check_queen
    jmp .done
.ki:
    call check_king
    jmp .done
.done:
    mov bl, al
    mov al, [saved_mf]
    mov [move_from], al
    mov al, [saved_mt]
    mov [move_to], al
    mov al, bl
    ret
.restore_no:
    mov al, [saved_mf]
    mov [move_from], al
    mov al, [saved_mt]
    mov [move_to], al
    xor al, al
    ret

pawn_attacks_sq:
    movzx si, byte [move_from]
    movzx di, byte [move_to]
    mov al, [board+si]
    and al, 8
    mov bx, si
    and bx, 7
    test al, al
    jnz .black
    test bl, bl
    jz .white_right
    mov ax, si
    sub ax, 9
    cmp ax, di
    je .ok
.white_right:
    cmp bl, 7
    je .no
    mov ax, si
    sub ax, 7
    cmp ax, di
    je .ok
    jmp .no
.black:
    test bl, bl
    jz .black_right
    mov ax, si
    add ax, 7
    cmp ax, di
    je .ok
.black_right:
    cmp bl, 7
    je .no
    mov ax, si
    add ax, 9
    cmp ax, di
    je .ok
    jmp .no
.ok:
    mov al, 1
    ret
.no:
    xor al, al
    ret

do_move:
    mov bx, [hist_count]
    cmp bx, 60
    jae .skip_hist
    shl bx, 1
    mov al, [move_from]
    mov [history+bx], al
    mov al, [move_to]
    mov [history+bx+1], al
    inc word [hist_count]
.skip_hist:
    movzx si, byte [move_from]
    movzx di, byte [move_to]
    mov al, [board+si]
    cmp al, P_PAWN | WHITE
    je .ep_w
    cmp al, P_PAWN | BLACK
    je .ep_b
    jmp .castle_chk
.ep_w:
    mov cl, [ep_sq]
    cmp cl, [move_to]
    jne .castle_chk
    mov bx, di
    add bx, 8
    mov byte [board+bx], 0
    jmp .castle_chk
.ep_b:
    mov cl, [ep_sq]
    cmp cl, [move_to]
    jne .castle_chk
    mov bx, di
    sub bx, 8
    mov byte [board+bx], 0
    jmp .castle_chk
.castle_chk:
    and al, 7
    cmp al, P_KING
    jne .no_castle
    mov ax, di
    sub ax, si
    cmp ax, 2
    je .castle_k
    cmp ax, -2
    je .castle_q
    jmp .no_castle
.castle_k:
    cmp si, 60
    jne .ck_b
    mov al, [board+63]
    mov [board+61], al
    mov byte [board+63], 0
    jmp .no_castle
.ck_b:
    mov al, [board+7]
    mov [board+5], al
    mov byte [board+7], 0
    jmp .no_castle
.castle_q:
    cmp si, 60
    jne .cq_b
    mov al, [board+56]
    mov [board+59], al
    mov byte [board+56], 0
    jmp .no_castle
.cq_b:
    mov al, [board+0]
    mov [board+3], al
    mov byte [board+0], 0
.no_castle:
    mov al, [board+si]
    mov [board+di], al
    mov byte [board+si], 0
    and al, 7
    cmp al, P_PAWN
    jne .no_promo
    mov ax, di
    shr ax, 3
    test ax, ax
    jz .promo
    cmp ax, 7
    jne .no_promo
.promo:
    mov al, [board+di]
    and al, 8
    or al, P_QUEEN
    mov [board+di], al
.no_promo:
    mov al, [move_from]
    cmp al, 60
    jne .nwk
    and byte [castling], 0xFC
.nwk:
    cmp al, 4
    jne .nbk
    and byte [castling], 0xF3
.nbk:
    cmp al, 63
    jne .nr1
    and byte [castling], 0xFE
.nr1:
    cmp al, 56
    jne .nr2
    and byte [castling], 0xFD
.nr2:
    cmp al, 7
    jne .nr3
    and byte [castling], 0xFB
.nr3:
    cmp al, 0
    jne .nr4
    and byte [castling], 0xF7
.nr4:
    mov al, [move_to]
    cmp al, 63
    jne .nrt1
    and byte [castling], 0xFE
.nrt1:
    cmp al, 56
    jne .nrt2
    and byte [castling], 0xFD
.nrt2:
    cmp al, 7
    jne .nrt3
    and byte [castling], 0xFB
.nrt3:
    cmp al, 0
    jne .nrt4
    and byte [castling], 0xF7
.nrt4:
    mov al, [move_from]
    mov [last_from], al
    mov al, [move_to]
    mov [last_to], al
    mov byte [ep_sq], 0xFF
    mov al, [board+di]
    and al, 7
    cmp al, P_PAWN
    jne .no_ep
    mov ax, di
    shr ax, 3
    mov bx, si
    shr bx, 3
    sub ax, bx
    cmp ax, 2
    jne .ne2
    mov ax, di
    sub ax, 8
    mov [ep_sq], al
    jmp .no_ep
.ne2:
    cmp ax, -2
    jne .no_ep
    mov ax, di
    add ax, 8
    mov [ep_sq], al
.no_ep:
    xor byte [turn], 8
    mov byte [selected], 0xFF
    call build_hints
    call check_check
    ret

check_check:
    mov byte [check_sq], 0xFF
    mov cx, 64
    mov bx, 0
.find:
    mov al, [board+bx]
    and al, 7
    cmp al, P_KING
    jne .next
    mov al, [board+bx]
    and al, 8
    cmp al, [turn]
    jne .next
    mov [check_sq], bl
    mov [t_sq], bl
    call is_square_attacked
    test al, al
    jz .not_check
    ret
.not_check:
    mov byte [check_sq], 0xFF
    ret
.next:
    inc bx
    loop .find
    ret

check_gameover:
    call has_any_legal_move
    test al, al
    jnz .cont
    mov byte [gameover], 1
    cmp byte [check_sq], 0xFF
    jne .mate
    mov word [msg], s_pat
    ret
.mate:
    mov word [msg], s_mate
    ret
.cont:
    ret

has_any_legal_move:
    xor cx, cx
.from:
    cmp cx, 64
    jae .no
    mov [move_from], cl
    movzx si, cl
    mov al, [board+si]
    test al, al
    jz .next_from
    mov ah, al
    and ah, 8
    cmp ah, [turn]
    jne .next_from
    xor dx, dx
.to:
    cmp dx, 64
    jae .next_from
    cmp dx, cx
    je .next_to
    mov [move_to], dl
    push cx
    push dx
    call is_legal_move_test
    pop dx
    pop cx
    test al, al
    jnz .yes
.next_to:
    inc dx
    jmp .to
.next_from:
    inc cx
    jmp .from
.no:
    xor al, al
    ret
.yes:
    mov al, 1
    ret

is_legal_move_test:
    call is_legal_move
    test al, al
    jz .r
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    call make_temp_move
    call king_in_check
    mov [tmp_check], al
    call undo_temp_move
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    cmp byte [tmp_check], 0
    jne .in_check
    mov al, 1
    ret
.in_check:
    xor al, al
    ret
.r:
    xor al, al
    ret

make_temp_move:
    mov al, [move_from]
    mov [tmp_mf], al
    mov al, [move_to]
    mov [tmp_mt], al
    movzx si, byte [move_from]
    movzx di, byte [move_to]
    mov al, [board+si]
    mov [tmp_piece], al
    mov al, [board+di]
    mov [tmp_captured], al
    mov al, [board+si]
    mov [board+di], al
    mov byte [board+si], 0
    cmp byte [ep_sq], 0xFF
    je .r
    mov al, [ep_sq]
    cmp al, [tmp_mt]
    jne .r
    mov al, [tmp_piece]
    and al, 7
    cmp al, P_PAWN
    jne .r
    mov al, [tmp_piece]
    and al, 8
    test al, al
    jz .white_ep
    mov bx, di
    sub bx, 8
    jmp .ep_rm
.white_ep:
    mov bx, di
    add bx, 8
.ep_rm:
    mov al, [board+bx]
    mov [tmp_ep_piece], al
    mov byte [board+bx], 0
.r:
    ret

undo_temp_move:
    movzx si, byte [tmp_mf]
    movzx di, byte [tmp_mt]
    mov al, [tmp_piece]
    mov [board+si], al
    mov al, [tmp_captured]
    mov [board+di], al
    cmp byte [ep_sq], 0xFF
    je .r
    mov al, [ep_sq]
    cmp al, [tmp_mt]
    jne .r
    mov al, [tmp_piece]
    and al, 7
    cmp al, P_PAWN
    jne .r
    mov al, [tmp_piece]
    and al, 8
    test al, al
    jz .white_ep
    mov bx, di
    sub bx, 8
    jmp .ep_rm
.white_ep:
    mov bx, di
    add bx, 8
.ep_rm:
    mov al, [tmp_ep_piece]
    mov [board+bx], al
.r:
    ret

king_in_check:
    mov cx, 64
    mov bx, 0
.find:
    mov al, [board+bx]
    and al, 7
    cmp al, P_KING
    jne .next
    mov al, [board+bx]
    and al, 8
    cmp al, [turn]
    jne .next
    mov [t_sq], bl
    call is_square_attacked
    ret
.next:
    inc bx
    loop .find
    xor al, al
    ret

bot_move:
    mov word [msg], s_bot
    call rand
    xor dx, dx
    mov bx, 3
    div bx
    mov [bot_strategy], dl
    mov word [best_score], 0x8000
    mov byte [best_from], 0xFF
    mov byte [best_to], 0xFF
    mov byte [first_from], 0xFF
    mov byte [first_to], 0xFF
    xor cx, cx
.from:
    cmp cx, 64
    jae .apply
    mov [move_from], cl
    movzx si, cl
    mov al, [board+si]
    test al, al
    jz .next_from
    mov ah, al
    and ah, 8
    cmp ah, [bot_color]
    jne .next_from
    xor dx, dx
.to:
    cmp dx, 64
    jae .next_from
    cmp dx, cx
    je .next_to
    mov [move_to], dl
    push cx
    push dx
    call is_legal_move_test
    pop dx
    pop cx
    test al, al
    jz .next_to
    cmp byte [first_from], 0xFF
    jne .not_first
    mov al, [move_from]
    mov [first_from], al
    mov al, [move_to]
    mov [first_to], al
.not_first:
    push cx
    push dx
    cmp byte [bot_strategy], 0
    je .ev_attack
    cmp byte [bot_strategy], 1
    je .ev_position
    call evaluate_move_random
    jmp .ev_done
.ev_attack:
    call evaluate_move_attack
    jmp .ev_done
.ev_position:
    call evaluate_move_position
.ev_done:
    pop dx
    pop cx
    cmp ax, [best_score]
    jle .next_to
    mov [best_score], ax
    mov al, [move_from]
    mov [best_from], al
    mov al, [move_to]
    mov [best_to], al
.next_to:
    inc dx
    jmp .to
.next_from:
    inc cx
    jmp .from
.apply:
    cmp byte [best_from], 0xFF
    jne .have_best
    cmp byte [first_from], 0xFF
    je .r
    mov al, [first_from]
    mov [best_from], al
    mov al, [first_to]
    mov [best_to], al
.have_best:
    cmp byte [best_from], 0xFF
    je .r
    mov al, [best_from]
    mov [move_from], al
    mov al, [best_to]
    mov [move_to], al
    call do_move
    call check_gameover
    cmp byte [gameover], 0
    jne .r
    mov word [msg], 0
.r:
    ret

score_sign:
    cmp byte [bot_color], WHITE
    je .r
    neg ax
.r:
    ret

evaluate_move_attack:
    push bx
    push cx
    push dx
    push si
    push di
    movzx si, byte [move_to]
    mov al, [board+si]
    mov [eval_captured], al
    call make_temp_move
    call evaluate_material
    call score_sign
    mov [eval_score], ax
    call undo_temp_move
    mov al, [eval_captured]
    test al, al
    jz .no_bonus
    and al, 7
    call piece_value
    shl ax, 1
    mov bx, ax
    mov ax, [eval_score]
    add ax, bx
    jmp .done
.no_bonus:
    mov ax, [eval_score]
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

evaluate_move_position:
    push bx
    push cx
    push dx
    push si
    push di
    call make_temp_move
    call evaluate_material
    call score_sign
    mov [eval_score], ax
    call evaluate_centrality
    mov bx, [eval_score]
    add ax, bx
    mov [eval_score], ax
    call undo_temp_move
    mov ax, [eval_score]
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

evaluate_centrality:
    push bx
    push cx
    push si
    xor bx, bx
    xor cx, cx
.loop:
    cmp cx, 64
    jae .done
    mov si, cx
    mov al, [board+si]
    test al, al
    jz .next
    mov ah, al
    and ah, 8
    cmp ah, [bot_color]
    jne .next
    and al, 7
    cmp al, P_KING
    je .next
    cmp al, P_PAWN
    je .next
    mov ax, cx
    cmp ax, 27
    je .c40
    cmp ax, 28
    je .c40
    cmp ax, 35
    je .c40
    cmp ax, 36
    je .c40
    cmp ax, 18
    jb .next
    cmp ax, 45
    ja .next
    mov dx, ax
    and dx, 7
    cmp dx, 2
    jb .next
    cmp dx, 5
    ja .next
    shr ax, 3
    cmp ax, 2
    jb .next
    cmp ax, 5
    ja .next
    add bx, 20
    jmp .next
.c40:
    add bx, 40
.next:
    inc cx
    jmp .loop
.done:
    mov ax, bx
    pop si
    pop cx
    pop bx
    ret

evaluate_move_random:
    push bx
    push cx
    push dx
    push si
    push di
    call make_temp_move
    call evaluate_material
    call score_sign
    mov [eval_score], ax
    call undo_temp_move
    call rand
    xor dx, dx
    mov bx, 200
    div bx
    mov ax, [eval_score]
    add ax, dx
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

evaluate_material:
    push bx
    push cx
    xor bx, bx
    xor cx, cx
    mov si, 0
.loop:
    cmp si, 64
    jae .done
    mov al, [board+si]
    test al, al
    jz .next
    push ax
    and al, 7
    call piece_value
    mov dx, ax
    pop ax
    test al, 8
    jz .white
    add cx, dx
    jmp .next
.white:
    add bx, dx
.next:
    inc si
    jmp .loop
.done:
    mov ax, bx
    sub ax, cx
    pop cx
    pop bx
    ret

piece_value:
    xor ah, ah
    cmp al, P_PAWN
    je .p
    cmp al, P_KNIGHT
    je .n
    cmp al, P_BISHOP
    je .b
    cmp al, P_ROOK
    je .r
    cmp al, P_QUEEN
    je .q
    cmp al, P_KING
    je .k
    xor ax, ax
    ret
.p:
    mov ax, VAL_PAWN
    ret
.n:
    mov ax, VAL_KNIGHT
    ret
.b:
    mov ax, VAL_BISHOP
    ret
.r:
    mov ax, VAL_ROOK
    ret
.q:
    mov ax, VAL_QUEEN
    ret
.k:
    mov ax, VAL_KING
    ret

undo_move:
    cmp word [hist_count], 0
    je .r
    dec word [hist_count]
    mov bx, [hist_count]
    shl bx, 1
    mov al, [history+bx]
    mov [move_from], al
    mov al, [history+bx+1]
    mov [move_to], al
    movzx si, byte [move_from]
    movzx di, byte [move_to]
    mov al, [board+di]
    mov [board+si], al
    mov byte [board+di], 0
    xor byte [turn], 8
    mov byte [selected], 0xFF
    mov byte [check_sq], 0xFF
    mov byte [gameover], 0
    mov word [msg], 0
    call build_hints
.r:
    ret

; ============================================================
;  GUI DRAWING
; ============================================================

; draw a piece token. AL = piece byte, [gpx]/[gpy] = square top-left
draw_piece:
    mov [gpc], al
    and al, 7
    mov [gpt], al
    mov al, [gpc]
    and al, 8
    test al, al
    jz .white
    mov byte [gpcol], 0          ; black pieces
    jmp .color
.white:
    mov byte [gpcol], 15         ; white pieces
.color:
    ; pattern for this piece type
    movzx bx, byte [gpt]
    dec bx
    imul bx, bx, 12
    add bx, patterns
    mov [gpat], bx
    mov byte [grow], 0
.prow:
    cmp byte [grow], 12
    jae .letter
    mov bx, [gpat]
    movzx di, byte [grow]
    mov al, [bx+di]
    test al, al
    jz .nextrow
    mov [gpw], al
    ; x = gpx + (12 - width)/2 + (CELL-12)/2
    mov ax, 12
    movzx bx, byte [gpw]
    sub ax, bx
    shr ax, 1
    add ax, 2                    ; (CELL-12)/2
    add ax, [gpx]
    mov [gx], ax
    movzx ax, byte [grow]
    add ax, 2                    ; (CELL-12)/2
    add ax, [gpy]
    mov [gy], ax
    mov al, [gpcol]
    mov bx, [gx]
    mov cx, [gy]
    movzx dx, byte [gpw]
    mov si, 1
    GUI API_FILL
.nextrow:
    inc byte [grow]
    jmp .prow
.letter:
    movzx bx, byte [gpt]
    dec bx
    mov al, [gletters+bx]
    mov bx, [gpx]
    add bx, (CELL-5)/2
    mov cx, [gpy]
    add cx, (CELL-8)/2+2
    mov dl, [gpcol]
    cmp dl, 15
    jne .darkletter
    mov dl, 1
    jmp .putletter
.darkletter:
    mov dl, 7
.putletter:
    GUI API_CHAR
    ret

h_draw:
    mov al, 1
    GUI API_CLEAR

    ; side panel
    mov al, 8
    mov bx, 160
    mov cx, 4
    mov dx, 92
    mov si, 156
    GUI API_FILL
    mov al, 14
    mov bx, 160
    mov cx, 4
    mov dx, 92
    mov si, 1
    GUI API_FILL

    mov si, s_title
    mov bx, 166
    mov cx, 10
    mov dl, 14
    GUI API_STR

    ; board
    mov word [r], 0
.row:
    cmp word [r], 8
    jae .boarddone
    mov word [c], 0
.col:
    cmp word [c], 8
    jae .nextrow
    ; board square index
    mov ax, [r]
    shl ax, 3
    add ax, [c]
    mov [sq], ax
    ; square position
    mov ax, [c]
    imul ax, ax, CELL
    add ax, BX0
    mov [gpx], ax
    mov ax, [r]
    imul ax, ax, CELL
    add ax, BY0
    mov [gpy], ax
    ; light / dark
    mov ax, [r]
    add ax, [c]
    and ax, 1
    jz .light
    mov al, 6                    ; brown
    jmp .sqcolor
.light:
    mov al, 7                    ; light gray
.sqcolor:
    mov bx, [gpx]
    mov cx, [gpy]
    mov dx, CELL
    mov si, CELL
    GUI API_FILL
    ; last move highlight
    mov ax, [sq]
    cmp ax, [last_from]
    je .last
    cmp ax, [last_to]
    je .last
    jmp .selcheck
.last:
    mov al, 9
    mov bx, [gpx]
    mov cx, [gpy]
    mov dx, CELL
    mov si, CELL
    GUI API_FILL
.selcheck:
    mov ax, [sq]
    cmp ax, [selected]
    jne .checkcheck
    mov al, 3
    mov bx, [gpx]
    mov cx, [gpy]
    mov dx, CELL
    mov si, CELL
    GUI API_FILL
.checkcheck:
    mov ax, [sq]
    cmp ax, [check_sq]
    jne .hintcheck
    mov al, 12
    mov bx, [gpx]
    mov cx, [gpy]
    mov dx, CELL
    mov si, CELL
    GUI API_FILL
.hintcheck:
    cmp byte [show_hints], 0
    je .piece
    movzx bx, byte [sq]
    cmp byte [hints+bx], 0
    je .piece
    mov al, 10
    mov bx, [gpx]
    add bx, CELL/2-2
    mov cx, [gpy]
    add cx, CELL/2-2
    mov dx, 4
    mov si, 4
    GUI API_FILL
.piece:
    movzx si, byte [sq]
    mov al, [board+si]
    test al, al
    jz .nopic
    call draw_piece
.nopic:
    inc word [c]
    jmp .col
.nextrow:
    inc word [r]
    jmp .row
.boarddone:

    ; cursor frame (yellow)
    movzx ax, byte [cursor]
    mov bx, ax
    and bx, 7
    imul bx, bx, CELL
    add bx, BX0
    mov [gpx], bx
    mov bx, ax
    shr bx, 3
    imul bx, bx, CELL
    add bx, BY0
    mov [gpy], bx
    mov al, 14
    mov bx, [gpx]
    mov cx, [gpy]
    mov dx, CELL
    mov si, 1
    GUI API_FILL
    mov bx, [gpx]
    mov cx, [gpy]
    add cx, CELL-1
    mov dx, CELL
    mov si, 1
    GUI API_FILL
    mov bx, [gpx]
    mov cx, [gpy]
    mov dx, 1
    mov si, CELL
    GUI API_FILL
    mov bx, [gpx]
    add bx, CELL-1
    mov cx, [gpy]
    mov dx, 1
    mov si, CELL
    GUI API_FILL

    ; rank labels 8..1
    mov word [r], 0
.labels:
    cmp word [r], 8
    jae .paneltxt
    mov ax, 8
    sub ax, [r]
    add al, '0'
    mov bx, 2
    mov cx, [r]
    imul cx, cx, CELL
    add cx, BY0+4
    mov dl, 8
    GUI API_CHAR
    inc word [r]
    jmp .labels
.paneltxt:
    ; file letters a..h under the board
    mov word [c], 0
.filelabels:
    cmp word [c], 8
    jae .paneltxt2
    mov ax, 'a'
    add al, byte [c]
    mov bx, [c]
    imul bx, bx, CELL
    add bx, BX0+5
    mov cx, BY0+8*CELL+1
    mov dl, 8
    GUI API_CHAR
    inc word [c]
    jmp .filelabels
.paneltxt2:
    ; side panel texts
    mov si, s_turn
    mov bx, 166
    mov cx, 22
    mov dl, 7
    GUI API_STR
    cmp byte [turn], WHITE
    jne .isblack
    mov si, s_white
    mov bx, 166
    mov cx, 32
    mov dl, 15
    GUI API_STR
    jmp .botinfo
.isblack:
    mov si, s_black
    mov bx, 166
    mov cx, 32
    mov dl, 7
    GUI API_STR
.botinfo:
    cmp byte [bot_on], 0
    je .nobot
    mov si, s_bot
    mov bx, 166
    mov cx, 44
    mov dl, 10
    GUI API_STR
    cmp byte [bot_color], WHITE
    jne .botblack
    mov si, s_botw
    jmp .botcolor
.botblack:
    mov si, s_botb
.botcolor:
    mov bx, 166
    mov cx, 54
    mov dl, 10
    GUI API_STR
    jmp .status
.nobot:
    mov si, s_two
    mov bx, 166
    mov cx, 44
    mov dl, 7
    GUI API_STR
.status:
    mov si, [msg]
    test si, si
    jz .checkmsg
    mov bx, 166
    mov cx, 74
    mov dl, 12
    GUI API_STR
    jmp .keys
.checkmsg:
    cmp byte [check_sq], 0xFF
    je .keys
    mov si, s_check
    mov bx, 166
    mov cx, 74
    mov dl, 12
    GUI API_STR
.keys:
    mov si, s_keys1
    mov bx, 166
    mov cx, 104
    mov dl, 7
    GUI API_STR
    mov si, s_keys2
    mov bx, 166
    mov cx, 114
    mov dl, 7
    GUI API_STR
    mov si, s_keys3
    mov bx, 166
    mov cx, 124
    mov dl, 7
    GUI API_STR
    mov si, s_keys4
    mov bx, 166
    mov cx, 134
    mov dl, 7
    GUI API_STR
    xor al, al
    retf

; ------------------------------------------------------------
;  data
; ------------------------------------------------------------
s_title  db "SPHERA CHESS", 0
s_turn   db "TURN", 0
s_white  db "WHITE", 0
s_black  db "BLACK", 0
s_bot    db "BOT:", 0
s_botw   db " White", 0
s_botb   db " Black", 0
s_two    db "2 PLAYERS", 0
s_check  db "CHECK!", 0
s_mate   db "CHECKMATE!", 0
s_pat    db "STALEMATE", 0
s_botmsg db "Bot thinking", 0
s_keys1  db "ARROWS  cursor", 0
s_keys2  db "ENTER   select", 0
s_keys3  db "R new  U undo", 0
s_keys4  db "B bot  M hints", 0

board       times 64 db 0
turn        db 0
selected    db 0xFF
cursor      db 52
check_sq    db 0xFF
gameover    db 0
castling    db 0x0F
ep_sq       db 0xFF
last_from   db 0xFF
last_to     db 0xFF
show_hints  db 1
bot_on      db 0
bot_color   db BLACK
bot_strategy db 0
rand_seed   dw 0
r           dw 0
c           dw 0
move_from   db 0
move_to     db 0
att_from    dw 0
att_to      db 0
t_sq        db 0
saved_mf    db 0
saved_mt    db 0
hist_count  dw 0
history     times 128 db 0
best_score  dw 0
best_from   db 0xFF
best_to     db 0xFF
first_from  db 0xFF
first_to    db 0xFF
eval_score  dw 0
eval_captured db 0
tmp_mf      db 0
tmp_mt      db 0
tmp_piece   db 0
tmp_captured db 0
tmp_ep_piece db 0
tmp_check   db 0
msg         dw 0

hints       times 64 db 0
botdelay    db 0
sndtimer    db 0
sq          dw 0
gpx         dw 0
gpy         dw 0
gx          dw 0
gy          dw 0
gpc         db 0
gpt         db 0
gpcol       db 0
gpw         db 0
grow        db 0
gpat        dw 0

; 12-row piece silhouettes (row width, 0 = empty)
patterns:
; pawn
    db 0,4,6,6,4,6,8,8,6,10,10,0
; rook
    db 0,10,4,6,6,6,6,6,8,12,12,0
; knight
    db 0,4,8,8,10,8,6,8,8,12,12,0
; bishop
    db 0,2,4,6,8,6,8,8,6,12,12,0
; queen
    db 0,2,6,6,10,8,8,8,8,12,12,0
; king
    db 0,4,4,10,6,10,8,8,8,12,12,0

gletters db 'p','n','b','r','q','k'
