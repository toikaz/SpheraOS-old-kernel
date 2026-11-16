; ============================================================
;  chess.asm — шахматы v5 (консоль 80x25)
;  Build: nasm -f bin asm/chess.asm -o asm/chess.bin
;  Run:   run CHESS.BIN
;  Keys: стрелки, Enter, Esc, R, U, B (bot), C (side), M (hints)
; ============================================================
BITS 16
ORG 0

VIDEO_SEG   equ 0xB800
P_PAWN      equ 1
P_KNIGHT    equ 2
P_BISHOP    equ 3
P_ROOK      equ 4
P_QUEEN     equ 5
P_KING      equ 6
WHITE       equ 0
BLACK       equ 8
CASTLE_WK   equ 0x01
CASTLE_WQ   equ 0x02
CASTLE_BK   equ 0x04
CASTLE_BQ   equ 0x08
VAL_PAWN    equ 100
VAL_KNIGHT  equ 320
VAL_BISHOP  equ 330
VAL_ROOK    equ 500
VAL_QUEEN   equ 900
VAL_KING    equ 20000
BOARD_X     equ 26
BOARD_Y     equ 3

ATTR_NORMAL_W equ 0x0F
ATTR_NORMAL_B equ 0x07
ATTR_CURSOR   equ 0x70
ATTR_SELECT   equ 0x2E
ATTR_LAST     equ 0x17
ATTR_CHECK    equ 0x4E
ATTR_TITLE    equ 0x0E
ATTR_DIM      equ 0x08
ATTR_INFO     equ 0x0B
ATTR_ERR      equ 0x0C

; ============================================================
start:
    mov [start_sp], sp
    mov ax, 0x0003
    int 0x10
    mov ah, 0x01
    mov cx, 0x2607
    int 0x10
    mov byte [bot_on], 0
    mov byte [bot_color], BLACK
    call new_game
.main_loop:
    call draw_all
.wait_input:
    call get_key_nb
    test ax, ax
    jz .maybe_bot
    call handle_key
    jmp .main_loop
.maybe_bot:
    cmp byte [bot_on], 0
    je .wait_input
    mov al, [turn]
    cmp al, [bot_color]
    jne .wait_input
    cmp byte [gameover], 0
    jne .wait_input
    call bot_move
    jmp .main_loop

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
    xor ah, ah
    int 0x1A
    mov [rand_seed], dx
    ret

; ============================================================
get_key_nb:
    mov ah, 1
    int 0x16
    jz .none
    mov ah, 0
    int 0x16
    ret
.none:
    xor ax, ax
    ret

; ============================================================
handle_key:
    cmp ah, 0x01
    je .esc
    cmp al, 'r'
    je .restart
    cmp al, 'R'
    je .restart
    cmp al, 'u'
    je .undo
    cmp al, 'U'
    je .undo
    cmp al, 'm'
    je .hints
    cmp al, 'M'
    je .hints
    cmp al, 'b'
    je .bot
    cmp al, 'B'
    je .bot
    cmp al, 'c'
    je .swap
    cmp al, 'C'
    je .swap
    cmp ah, 0x4B
    je .left
    cmp ah, 0x4D
    je .right
    cmp ah, 0x48
    je .up
    cmp ah, 0x50
    je .down
    cmp ah, 0x1C
    je .enter
    ret
.esc:
    cmp byte [selected], 0xFF
    jne .clear_sel
    mov ax, 0x0003
    int 0x10
    mov sp, [start_sp]
    retf
.clear_sel:
    mov byte [selected], 0xFF
    ret
.left:
    mov al, [cursor]
    and al, 7
    test al, al
    jz .done
    dec byte [cursor]
    ret
.right:
    mov al, [cursor]
    and al, 7
    cmp al, 7
    jae .done
    inc byte [cursor]
    ret
.up:
    cmp byte [cursor], 8
    jb .done
    sub byte [cursor], 8
    ret
.down:
    cmp byte [cursor], 56
    jae .done
    add byte [cursor], 8
    ret
.restart:
    call new_game
    ret
.undo:
    call undo_move
    ret
.hints:
    xor byte [show_hints], 1
    ret
.bot:
    xor byte [bot_on], 1
    cmp byte [bot_on], 0
    je .done
    mov al, [turn]
    xor al, 8
    mov [bot_color], al
.done:
    ret
.swap:
    cmp byte [bot_on], 0
    je .done
    xor byte [bot_color], 8
    ret
.enter:
    cmp byte [gameover], 0
    jne .done
    cmp byte [bot_on], 0
    je .normal
    mov al, [turn]
    cmp al, [bot_color]
    je .done
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
    ret
.try:
    call is_legal_move_test
    test al, al
    jz .bad
    call do_move
    call check_gameover
    ret
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
    ret
.clear:
    mov byte [selected], 0xFF
    ret
.select:
    movzx si, byte [cursor]
    mov al, [board+si]
    test al, al
    jz .done
    mov ah, al
    and ah, 8
    cmp ah, [turn]
    jne .done
    mov al, [cursor]
    mov [selected], al
    ret

; ============================================================
rand:
    push dx
    mov ax, [rand_seed]
    mov dx, 25173
    mul dx
    add ax, 13849
    mov [rand_seed], ax
    pop dx
    ret

; ============================================================
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

; ============================================================
;  check_pawn — переписан с явной проверкой диагоналей
; ============================================================
check_pawn:
    movzx si, byte [move_from]
    movzx di, byte [move_to]
    mov cx, -8
    cmp byte [turn], WHITE
    je .dir
    mov cx, 8
.dir:
    ; ---- прямой ход на 1 ----
    mov ax, si
    add ax, cx
    cmp ax, di
    jne .try_double
    mov al, [board+di]
    test al, al
    jz .ok
    jmp .no
.try_double:
    ; ---- прямой ход на 2 (только с начальной позиции) ----
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
    ; ---- диагональ bx-1 и bx+1 ----
    mov ax, si
    add ax, cx
    mov bx, ax
    ; bx-1 (если столбец bx > 0)
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
    ; bx+1 (если столбец bx < 7)
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

; ============================================================
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

; ============================================================
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

; ============================================================
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

; ============================================================
check_queen:
    call check_rook
    test al, al
    jnz .ok
    call check_bishop
.ok:
    ret

; ============================================================
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

; ============================================================
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

; ============================================================
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

; ============================================================
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

; ============================================================
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
    test byte [castling], CASTLE_WK
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
    test byte [castling], CASTLE_WQ
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
    test byte [castling], CASTLE_BK
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
    test byte [castling], CASTLE_BQ
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

; ============================================================
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

; ============================================================
;  pawn_attacks_sq — с проверкой столбцов (без wrap!)
; ============================================================
pawn_attacks_sq:
    movzx si, byte [move_from]
    movzx di, byte [move_to]
    ; цвет пешки
    mov al, [board+si]
    and al, 8
    ; столбец
    mov bx, si
    and bx, 7
    test al, al
    jnz .black
    ; белая: -9 (если col > 0) или -7 (если col < 7)
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
    ; чёрная: +7 (если col > 0) или +9 (если col < 7)
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

; ============================================================
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
    mov bl, [board+di]
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
    call check_check
    ret

; ============================================================
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

; ============================================================
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

; ============================================================
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

; ============================================================
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

; ============================================================
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

; ============================================================
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

; ============================================================
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

; ============================================================
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

; ============================================================
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
.r:
    ret

; ============================================================
putc:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    mov di, dx
    imul di, di, 160
    shl cx, 1
    add di, cx
    mov cx, VIDEO_SEG
    mov es, cx
    mov ah, bl
    mov [es:di], ax
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

put_str:
.l:
    mov al, [si]
    test al, al
    jz .d
    call putc
    inc cx
    inc si
    jmp .l
.d:
    ret

cls:
    push es
    push di
    push ax
    push cx
    mov ax, VIDEO_SEG
    mov es, ax
    xor di, di
    mov ax, 0x0720
    mov cx, 80*25
    rep stosw
    pop cx
    pop ax
    pop di
    pop es
    ret

; ============================================================
draw_all:
    call cls
    call draw_title
    call draw_board
    call draw_info
    call draw_status
    ret

draw_title:
    mov si, s_title
    mov cx, 2
    mov dx, 0
    mov bl, ATTR_TITLE
    call put_str
    ret

draw_board:
    mov si, s_top
    mov cx, BOARD_X
    mov dx, BOARD_Y
    mov bl, ATTR_DIM
    call put_str
    mov word [r], 0
.row:
    cmp word [r], 8
    jae .bottom
    mov ax, 8
    sub ax, [r]
    add al, '0'
    mov cx, BOARD_X-2
    mov dx, BOARD_Y
    add dx, [r]
    inc dx
    mov bl, ATTR_DIM
    call putc
    mov word [c], 0
.col:
    cmp word [c], 8
    jae .close_row
    call draw_cell
    inc word [c]
    jmp .col
.close_row:
    mov cx, BOARD_X + 32
    mov dx, [r]
    add dx, BOARD_Y
    inc dx
    mov al, '|'
    mov bl, ATTR_DIM
    call putc
    inc word [r]
    jmp .row
.bottom:
    mov si, s_bottom
    mov cx, BOARD_X
    mov dx, BOARD_Y+9
    mov bl, ATTR_DIM
    call put_str
    mov si, s_letters
    mov cx, BOARD_X
    mov dx, BOARD_Y+10
    mov bl, ATTR_DIM
    call put_str
    ret

; ============================================================
draw_cell:
    mov ax, [c]
    shl ax, 2
    add ax, BOARD_X + 1
    mov [cx_save], ax
    mov ax, [r]
    add ax, BOARD_Y + 1
    mov [cy_save], ax
    mov cx, [cx_save]
    dec cx
    mov dx, [cy_save]
    mov al, '|'
    mov bl, ATTR_DIM
    call putc
    mov ax, [r]
    shl ax, 3
    add ax, [c]
    mov si, ax
    mov byte [cur_letter], ' '
    mov al, [board+si]
    test al, al
    jz .no_piece
    push ax
    and al, 7
    call piece_letter
    mov [cur_letter], al
    pop ax
.no_piece:
    mov bl, ATTR_NORMAL_B
    mov al, [board+si]
    test al, al
    jz .attr_ready
    and al, 8
    test al, al
    jz .white_piece
    mov bl, ATTR_NORMAL_B
    jmp .attr_ready
.white_piece:
    mov bl, ATTR_NORMAL_W
.attr_ready:
    mov ax, [r]
    shl ax, 3
    add ax, [c]
    cmp al, [cursor]
    jne .chk_sel
    mov bl, ATTR_CURSOR
    jmp .paint
.chk_sel:
    cmp al, [selected]
    jne .chk_last
    mov bl, ATTR_SELECT
    jmp .paint
.chk_last:
    cmp al, [last_to]
    jne .chk_check
    mov bl, ATTR_LAST
    jmp .paint
.chk_check:
    cmp al, [check_sq]
    jne .paint
    mov bl, ATTR_CHECK
.paint:
    mov cx, [cx_save]
    mov dx, [cy_save]
    mov al, ' '
    call putc
    inc cx
    mov al, [cur_letter]
    call putc
    inc cx
    mov al, ' '
    call putc
    ret

; ============================================================
piece_letter:
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
    mov al, '?'
    ret
.p:
    mov al, 'p'
    ret
.n:
    mov al, 'n'
    ret
.b:
    mov al, 'b'
    ret
.r:
    mov al, 'r'
    ret
.q:
    mov al, 'q'
    ret
.k:
    mov al, 'k'
    ret

; ============================================================
draw_info:
    mov cx, 40
    mov dx, 0
    cmp byte [turn], WHITE
    jne .is_black
    mov si, s_white
    mov bl, ATTR_INFO
    call put_str
    jmp .bot_label
.is_black:
    mov si, s_black
    mov bl, ATTR_INFO
    call put_str
.bot_label:
    cmp byte [bot_on], 0
    je .clr_strat
    mov si, s_bot_on
    mov cx, 60
    mov dx, 0
    mov bl, ATTR_INFO
    call put_str
    cmp byte [bot_color], WHITE
    jne .col_black
    mov si, s_bot_w
    jmp .col_show
.col_black:
    mov si, s_bot_b
.col_show:
    mov cx, 66
    mov dx, 0
    mov bl, ATTR_INFO
    call put_str
    cmp byte [bot_strategy], 0
    je .st_a
    cmp byte [bot_strategy], 1
    je .st_p
    mov si, s_st_r
    jmp .st_show
.st_a:
    mov si, s_st_a
    jmp .st_show
.st_p:
    mov si, s_st_p
.st_show:
    mov cx, 2
    mov dx, 16
    mov bl, ATTR_DIM
    call put_str
    jmp .r
.clr_strat:
    mov cx, 2
    mov dx, 16
    mov ah, ATTR_DIM
.clr_loop:
    push cx
    mov al, ' '
    mov bl, ah
    call putc
    pop cx
    inc cx
    cmp cx, 22
    jb .clr_loop
.r:
    ret

; ============================================================
draw_status:
    mov si, s_help
    mov cx, 2
    mov dx, 15
    mov bl, ATTR_DIM
    call put_str
    mov si, [msg]
    test si, si
    jz .chk
    mov cx, 2
    mov dx, 17
    mov bl, ATTR_ERR
    call put_str
    jmp .done
.chk:
    cmp byte [check_sq], 0xFF
    je .done
    mov si, s_check
    mov cx, 2
    mov dx, 17
    mov bl, ATTR_ERR
    call put_str
.done:
    ret

; ============================================================
s_title    db "SpheraOS Chess", 0
s_white    db "White to move", 0
s_black    db "Black to move", 0
s_check    db "CHECK!", 0
s_mate     db "CHECKMATE!", 0
s_pat      db "STALEMATE - draw", 0
s_bot_on   db "[BOT]", 0
s_bot_w    db " W", 0
s_bot_b    db " B", 0
s_bot      db "Bot thinking...", 0
s_help     db "Arrows Enter R U B=bot C=side M=hints Esc", 0
s_top      db "+---+---+---+---+---+---+---+---+", 0
s_bottom   db "+---+---+---+---+---+---+---+---+", 0
s_letters  db "  a   b   c   d   e   f   g   h", 0
s_st_a     db "AI: attack (loves captures)", 0
s_st_p     db "AI: position (likes center)", 0
s_st_r     db "AI: random (unpredictable)", 0

; ============================================================
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
start_sp    dw 0
r           dw 0
c           dw 0
cx_save     dw 0
cy_save     dw 0
cur_letter  db ' '
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