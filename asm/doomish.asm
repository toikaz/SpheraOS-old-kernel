; ============================================================
;  DOOMISH.BIN - a tiny 3D raycaster shooter (a parody) for SpheraOS
;  W/S or Up/Down move, A/D strafe, Left/Right turn,
;  Space or Ctrl fire, ESC quit.      VGA 320x200, 256 colours
;  Build: nasm -f bin doomish.asm -o DOOMISH.BIN     run: run /GAMES/DOOMISH.BIN
; ============================================================
BITS 16
ORG 0

NLEVELS equ 4                 ; levels in the campaign
LV_SIZE equ 300               ; level record: map 256 + start/count 8 + 9 enemies 36
MAXEN   equ 9
TURN    equ 650
SPEED   equ 34

start:
    cld
    mov ax, cs
    mov ds, ax
    xor ax, ax
    mov es, ax
    mov ax, [es:0x24]
    mov [old9], ax
    mov ax, [es:0x26]
    mov [old9+2], ax
    mov ax, 0x1130
    mov bh, 3
    int 0x10
    mov [fontseg], es
    mov [fontoff], bp
    mov ax, 0x0013
    int 0x10
    mov ax, 0xA000
    mov es, ax
    call setpal
    xor ax, ax
    int 0x1A
    mov [seed], dx
    call title
    cli
    xor ax, ax
    mov es, ax
    mov word [es:0x24], kbd_isr
    mov [es:0x26], cs
    sti
    mov ax, 0xA000
    mov es, ax
.new:
    call initlevel
.frame:
    call getticks
    mov [ftick], ax
    call update
    cmp byte [state], 0
    jne .over
    call render
    call sprites
    call gun
    call hud
.sync:
    call getticks
    cmp ax, [ftick]
    jne .nf
    sti
    hlt
    jmp .sync
.nf:
    cmp byte [keys+1], 0
    je .frame
    jmp .exit
.over:
    call render
    call sprites
    call gun
    call hud
    call endscreen
.wk:
    sti
    hlt
    cmp byte [keys+1], 0
    jne .exit
    cmp byte [keys+0x1C], 0
    jne .nextlv
    cmp byte [keys+0x13], 0
    je .wk
    cmp byte [state], 2
    jne .restart
    cmp byte [level], NLEVELS-1
    jne .restart
    mov byte [level], 0          ; won the last level: start the campaign over
.restart:
    mov byte [fresh], 1
    jmp .new
.nextlv:
    cmp byte [state], 2
    jne .wk
    cmp byte [level], NLEVELS-1
    jae .wk
    inc byte [level]
    mov byte [fresh], 0          ; keep health and ammo between levels
    jmp .new
.exit:
    cli
    xor ax, ax
    mov es, ax
    mov ax, [old9]
    mov [es:0x24], ax
    mov ax, [old9+2]
    mov [es:0x26], ax
    sti
    mov ax, 0x0003
    int 0x10
.fl:
    mov ah, 1
    int 0x16
    jz .fd
    xor ah, ah
    int 0x16
    jmp .fl
.fd:
    retf

kbd_isr:
    push ax
    push bx
    push ds
    mov ax, cs
    mov ds, ax
    in al, 0x60
    cmp al, 0xE0
    je .done
    mov bl, al
    and bl, 0x7F
    xor bh, bh
    test al, 0x80
    jnz .up
    mov byte [keys+bx], 1
    jmp .done
.up:
    mov byte [keys+bx], 0
.done:
    mov al, 0x20
    out 0x20, al
    pop ds
    pop bx
    pop ax
    iret

getticks:
    push cx
    push dx
    xor ax, ax
    int 0x1A
    mov ax, dx
    pop dx
    pop cx
    ret

initlevel:
    ; load level [level] from level_tab: map -> map buffer, then the header and enemies
    mov al, [level]
    xor ah, ah
    mov bx, LV_SIZE
    mul bx
    mov si, level_tab
    add si, ax
    push es
    mov ax, cs
    mov es, ax
    mov di, map
    mov cx, 256
    rep movsb
    pop es
    lodsw
    mov [px], ax
    lodsw
    mov [py], ax
    lodsw
    mov [pa16], ax
    lodsw
    mov [nen], ax
    mov byte [state], 0
    mov word [kills], 0
    mov byte [flash], 0
    mov byte [cool], 0
    mov byte [hurt], 0
    mov byte [bob], 0
    cmp byte [fresh], 0
    je .keep
    mov word [hp], 100
    mov word [ammo], 60
    mov byte [fresh], 0
.keep:
    mov di, keys
    mov cx, 128
    xor al, al
.z:
    mov [di], al
    inc di
    loop .z
    mov di, enemies
    mov cx, [nen]
    jcxz .edone
.e:
    lodsw
    mov [di], ax
    lodsw
    mov [di+2], ax
    mov byte [di+4], 3
    mov byte [di+5], 1
    mov byte [di+6], 0
    mov word [di+8], 0
    add di, 16
    loop .e
.edone:
    mov al, [nen]
    add al, '0'
    mov [s_of+1], al
    mov al, [level]
    add al, '1'
    mov [s_lv+3], al
    ret

cellat:                         ; BX=x(8.8) CX=y(8.8) -> AL = map value
    push di
    mov al, ch
    xor ah, ah
    shl ax, 4
    mov di, ax
    mov al, bh
    xor ah, ah
    add di, ax
    mov al, [map+di]
    pop di
    ret

move:
    mov ax, [px]
    add ax, [mvx]
    mov [nx], ax
    mov bx, ax
    cmp word [mvx], 0
    jl .m1
    add bx, 48
    jmp .c1
.m1:
    sub bx, 48
.c1:
    mov cx, [py]
    call cellat
    test al, al
    jnz .skx
    mov ax, [nx]
    mov [px], ax
.skx:
    mov ax, [py]
    add ax, [mvy]
    mov [ny], ax
    mov cx, ax
    cmp word [mvy], 0
    jl .m2
    add cx, 48
    jmp .c2
.m2:
    sub cx, 48
.c2:
    mov bx, [px]
    call cellat
    test al, al
    jnz .done
    mov ax, [ny]
    mov [py], ax
.done:
    ret

update:
    cmp byte [keys+0x4B], 0
    je .nl
    sub word [pa16], TURN
.nl:
    cmp byte [keys+0x4D], 0
    je .nr
    add word [pa16], TURN
.nr:
    mov bx, [pa16]
    mov bl, bh
    xor bh, bh
    mov [pidx], bx
    shl bx, 1
    mov ax, [sintab+bx]
    mov [dsin], ax
    mov bx, [pidx]
    add bl, 64
    shl bx, 1
    mov ax, [sintab+bx]
    mov [dcos], ax
    mov word [mvx], 0
    mov word [mvy], 0
    mov al, [keys+0x11]
    or al, [keys+0x48]
    jz .nf
    mov ax, [dcos]
    imul ax, ax, SPEED
    sar ax, 8
    add [mvx], ax
    mov ax, [dsin]
    imul ax, ax, SPEED
    sar ax, 8
    add [mvy], ax
.nf:
    mov al, [keys+0x1F]
    or al, [keys+0x50]
    jz .nb
    mov ax, [dcos]
    imul ax, ax, SPEED
    sar ax, 8
    sub [mvx], ax
    mov ax, [dsin]
    imul ax, ax, SPEED
    sar ax, 8
    sub [mvy], ax
.nb:
    cmp byte [keys+0x20], 0
    je .nsr
    mov ax, [dsin]
    imul ax, ax, SPEED
    sar ax, 8
    sub [mvx], ax
    mov ax, [dcos]
    imul ax, ax, SPEED
    sar ax, 8
    add [mvy], ax
.nsr:
    cmp byte [keys+0x1E], 0
    je .nsl
    mov ax, [dsin]
    imul ax, ax, SPEED
    sar ax, 8
    add [mvx], ax
    mov ax, [dcos]
    imul ax, ax, SPEED
    sar ax, 8
    sub [mvy], ax
.nsl:
    mov ax, [mvx]
    or ax, [mvy]
    jz .still
    inc byte [bob]
.still:
    call move
    cmp byte [cool], 0
    je .cn
    dec byte [cool]
.cn:
    cmp byte [flash], 0
    je .fl
    dec byte [flash]
.fl:
    cmp byte [hurt], 0
    je .hu
    dec byte [hurt]
.hu:
    mov al, [keys+0x39]
    or al, [keys+0x1D]
    jz .nofire
    cmp byte [cool], 0
    jne .nofire
    cmp word [ammo], 0
    jle .nofire
    dec word [ammo]
    mov byte [flash], 4
    mov byte [cool], 7
    call shoot
.nofire:
    mov si, enemies
    mov cx, [nen]
.en:
    cmp byte [si+5], 0
    je near .nxt
    mov ax, [px]
    sub ax, [si]
    mov [ent_dx], ax
    mov ax, [py]
    sub ax, [si+2]
    mov [edy], ax
    mov bx, [ent_dx]
    test bx, bx
    jns .a1
    neg bx
.a1:
    mov ax, [edy]
    test ax, ax
    jns .a2
    neg ax
.a2:
    add bx, ax
    cmp bx, 2200
    ja near .nxt
    cmp bx, 200
    jb .attack
    mov ax, [si]
    cmp word [ent_dx], 0
    jl .xm
    add ax, 9
    mov bx, ax
    add bx, 40
    jmp .xc
.xm:
    sub ax, 9
    mov bx, ax
    sub bx, 40
.xc:
    push cx
    mov cx, [si+2]
    call cellat
    pop cx
    test al, al
    jnz .ty
    mov [si], bx
    cmp word [ent_dx], 0
    jl .xs1
    sub word [si], 40
    jmp .ty
.xs1:
    add word [si], 40
.ty:
    mov ax, [si+2]
    cmp word [edy], 0
    jl .ym
    add ax, 9
    mov dx, ax
    add dx, 40
    jmp .yc
.ym:
    sub ax, 9
    mov dx, ax
    sub dx, 40
.yc:
    push cx
    mov bx, [si]
    mov cx, dx
    call cellat
    pop cx
    test al, al
    jnz .nxt
    mov [si+2], dx
    cmp word [edy], 0
    jl .ys1
    sub word [si+2], 40
    jmp .nxt
.ys1:
    add word [si+2], 40
    jmp .nxt
.attack:
    cmp byte [si+6], 0
    je .bite
    dec byte [si+6]
    jmp .nxt
.bite:
    mov byte [si+6], 9
    mov byte [hurt], 6
    sub word [hp], 7
    cmp word [hp], 0
    jg .nxt
    mov word [hp], 0
    mov byte [state], 1
.nxt:
    add si, 16
    dec cx
    jnz near .en
    ret

shoot:
    mov word [best], 0xFFFF
    mov word [bestp], 0
    mov si, enemies
    mov cx, [nen]
.l:
    cmp byte [si+5], 0
    je .n
    mov ax, [si+8]
    test ax, ax
    jz .n
    mov bx, [si+10]
    sub bx, 160
    jns .p
    neg bx
.p:
    mov dx, [si+12]
    shr dx, 1
    cmp dx, 6
    jae .w
    mov dx, 6
.w:
    cmp bx, dx
    ja .n
    cmp ax, [zbuf+320]
    jae .n
    cmp ax, [best]
    jae .n
    mov [best], ax
    mov [bestp], si
.n:
    add si, 16
    dec cx
    jnz .l
    mov si, [bestp]
    test si, si
    jz .r
    dec byte [si+4]
    jnz .r
    mov byte [si+5], 0
    inc word [kills]
    push ax
    mov ax, [nen]
    cmp [kills], ax
    pop ax
    jb .r
    mov byte [state], 2
.r:
    ret

endscreen:
    mov word [tsc], 3
    cmp byte [state], 2
    je .win
    mov si, s_dead
    mov bx, 70
    mov cx, 60
    mov dl, 128
    call text
    jmp .more
.win:
    cmp byte [level], NLEVELS-1
    je .final
    mov si, s_win
    mov bx, 40
    mov cx, 60
    mov dl, 140
    call text
    mov word [tsc], 1
    mov si, s_next
    mov bx, 56
    mov cx, 124
    mov dl, 140
    call text
    jmp .more
.final:
    mov si, s_all
    mov bx, 52
    mov cx, 60
    mov dl, 140
    call text
.more:
    mov word [tsc], 1
    mov si, s_again
    mov bx, 72
    mov cx, 100
    mov dl, 131
    call text
    ret

title:
    xor bx, bx
    xor cx, cx
    mov dx, 320
    mov si, 200
    mov al, 137
    call fillrect
    mov word [tsc], 5
    mov si, s_title
    mov bx, 22
    mov cx, 34
    mov dl, 129
    call text
    mov bx, 18
    mov cx, 30
    mov dl, 128
    call text
    mov word [tsc], 1
    mov si, s_sub
    mov bx, 48
    mov cx, 86
    mov dl, 140
    call text
    mov si, s_k1
    mov bx, 40
    mov cx, 120
    mov dl, 138
    call text
    mov si, s_k2
    mov bx, 40
    mov cx, 134
    mov dl, 138
    call text
    mov si, s_press
    mov bx, 80
    mov cx, 164
    mov dl, 131
    call text
    xor ax, ax
    int 0x16
    ret

; ---------------------------------------------------------------
; palette
; ---------------------------------------------------------------
setpal:
    mov si, paltab
.l:
    lodsb
    cmp al, 0xFF
    je .ramps
    mov dx, 0x3C8
    out dx, al
    inc dx
    lodsb
    out dx, al
    lodsb
    out dx, al
    lodsb
    out dx, al
    jmp .l
.ramps:
    mov si, ramptab
.rl:
    lodsb
    cmp al, 0xFF
    je .done
    mov [rs], al
    lodsb
    mov [rm], al
    lodsb
    mov [rr], al
    lodsb
    mov [rg], al
    lodsb
    mov [rb], al
    mov dx, 0x3C8
    mov al, [rs]
    out dx, al
    inc dx
    xor bx, bx
.ri:
    mov al, [rr]
    call rcomp
    out dx, al
    mov al, [rg]
    call rcomp
    out dx, al
    mov al, [rb]
    call rcomp
    out dx, al
    inc bx
    cmp bx, 16
    jb .ri
    jmp .rl
.done:
    ret

rcomp:                          ; AL = component, BX = step 0..15, [rm] mode -> AL
    xor ah, ah
    cmp byte [rm], 0
    jne .up
    mov cx, 16
    sub cx, bx
    imul ax, cx
    shr ax, 4
    ret
.up:
    mov cx, bx
    add cx, 3
    imul ax, cx
    imul ax, ax, 14
    shr ax, 8
    ret

; ---------------------------------------------------------------
; drawing helpers
; ---------------------------------------------------------------
fillrect:                       ; BX=x CX=y DX=w SI=h AL=colour (ES=A000)
    pusha
    push ax
    mov ax, cx
    shl ax, 6
    mov di, ax
    shl ax, 2
    add di, ax
    add di, bx
    pop ax
.row:
    push di
    mov cx, dx
    rep stosb
    pop di
    add di, 320
    dec si
    jnz .row
    popa
    ret

text:                           ; DS:SI asciiz, BX=x CX=y, DL=colour, [tsc]=scale
    pusha
    mov [tcol], dl
.ch:
    lodsb
    test al, al
    jz .done
    push si
    push bx
    push cx
    xor ah, ah
    shl ax, 3
    add ax, [fontoff]
    mov si, ax
    mov fs, [fontseg]
    mov di, 8
.rw:
    mov ah, [fs:si]
    inc si
    push bx
    mov bp, 8
.bt:
    shl ah, 1
    jnc .nb
    push ax
    push si
    push di
    push bp
    mov al, [tcol]
    mov dx, [tsc]
    mov si, dx
    call fillrect
    pop bp
    pop di
    pop si
    pop ax
.nb:
    add bx, [tsc]
    dec bp
    jnz .bt
    pop bx
    add cx, [tsc]
    dec di
    jnz .rw
    pop cx
    pop bx
    pop si
    mov ax, 8
    mul word [tsc]
    add bx, ax
    jmp .ch
.done:
    popa
    ret

itoa:                           ; AX -> DI asciiz
    pusha
    mov bx, 10
    xor cx, cx
.d:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .d
.o:
    pop ax
    add al, '0'
    mov [di], al
    inc di
    loop .o
    mov byte [di], 0
    popa
    ret

; ---------------------------------------------------------------
; raycaster
; ---------------------------------------------------------------
mkdelta:                        ; AX = ray component (8.8) -> AX = |1/c| (8.8, capped)
    test ax, ax
    jns .p
    neg ax
.p:
    cmp ax, 4
    jb .big
    mov bx, ax
    mov dx, 1
    xor ax, ax
    div bx
    ret
.big:
    mov ax, 0x4000
    ret

render:
    pusha
    xor cx, cx
.col:
    mov [col], cx
    mov ax, cx
    sub ax, 160
    imul ax, ax, 51
    mov [coloff], ax
    add ax, [pa16]
    mov bl, ah
    xor bh, bh
    mov [ridx], bx
    shl bx, 1
    mov ax, [sintab+bx]
    mov [rdy], ax
    mov bx, [ridx]
    add bl, 64
    shl bx, 1
    mov ax, [sintab+bx]
    mov [ray_dx], ax
    mov ax, [ray_dx]
    call mkdelta
    mov [ddx], ax
    mov ax, [rdy]
    call mkdelta
    mov [ddy], ax
    mov ax, [py]
    mov al, ah
    xor ah, ah
    shl ax, 4
    mov si, ax
    mov ax, [px]
    mov al, ah
    xor ah, ah
    add si, ax
    mov ax, [px]
    and ax, 255
    mov bx, ax
    cmp word [ray_dx], 0
    jl .xneg
    mov word [stx], 1
    mov bx, 256
    sub bx, ax
    jmp .xs
.xneg:
    mov word [stx], -1
.xs:
    mov ax, [ddx]
    mul bx
    mov al, ah
    mov ah, dl
    mov [sdx], ax
    mov ax, [py]
    and ax, 255
    mov bx, ax
    cmp word [rdy], 0
    jl .yneg
    mov word [sty], 16
    mov bx, 256
    sub bx, ax
    jmp .ys
.yneg:
    mov word [sty], -16
.ys:
    mov ax, [ddy]
    mul bx
    mov al, ah
    mov ah, dl
    mov [sdy], ax
    mov bx, [sdx]
    mov dx, [sdy]
.dda:
    cmp bx, dx
    jae .ystep
    add bx, [ddx]
    add si, [stx]
    mov byte [side], 0
    jmp .chk
.ystep:
    add dx, [ddy]
    add si, [sty]
    mov byte [side], 1
.chk:
    mov al, [map+si]
    test al, al
    jz .dda
    mov [wtype], al
    cmp byte [side], 0
    jne .tY
    sub bx, [ddx]
    mov ax, bx
    jmp .gt
.tY:
    sub dx, [ddy]
    mov ax, dx
.gt:
    mov [tdist], ax
    cmp byte [side], 0
    jne .wy
    mov ax, [tdist]
    imul word [rdy]
    mov al, ah
    mov ah, dl
    add ax, [py]
    jmp .wu
.wy:
    mov ax, [tdist]
    imul word [ray_dx]
    mov al, ah
    mov ah, dl
    add ax, [px]
.wu:
    and ax, 255
    shr ax, 2
    mov [ucol], al
    mov bx, [coloff]
    mov bl, bh
    xor bh, bh
    add bl, 64
    shl bx, 1
    mov ax, [sintab+bx]
    imul word [tdist]
    mov al, ah
    mov ah, dl
    cmp ax, 40
    jae .dok
    mov ax, 40
.dok:
    mov [dist], ax
    mov bx, [col]
    shl bx, 1
    mov [zbuf+bx], ax
    mov bx, [dist]
    mov ax, 40960
    xor dx, dx
    div bx
    cmp ax, 1000
    jbe .lh
    mov ax, 1000
.lh:
    mov [lineh], ax
    shr ax, 1
    mov bx, 80
    sub bx, ax
    mov [top], bx
    mov ax, [dist]
    shr ax, 7
    cmp byte [side], 0
    je .sh1
    add ax, 2
.sh1:
    cmp ax, 12
    jbe .sh2
    mov ax, 12
.sh2:
    mov [shade], al
    mov al, [wtype]
    shl al, 4
    mov [wbase], al
    mov al, [shade]
    inc al
    add al, 80
    mov [mcol], al
    mov di, [col]
    xor si, si
    mov bx, [top]
    test bx, bx
    jns .t1
    xor bx, bx
.t1:
    cmp bx, 160
    jbe .t2
    mov bx, 160
.t2:
    mov [ytop], bx
.cl:
    cmp si, [ytop]
    jae .wall
    mov al, [fctab+si]
    mov [es:di], al
    add di, 320
    inc si
    jmp .cl
.wall:
    mov bx, [top]
    add bx, [lineh]
    cmp bx, 160
    jbe .b1
    mov bx, 160
.b1:
    mov [ybot], bx
    mov ax, 16384
    xor dx, dx
    div word [lineh]
    mov [tstep], ax
    mov word [tv], 0
    mov bx, [top]
    test bx, bx
    jns .nt
    neg bx
    mul bx
    mov [tv], ax
.nt:
.wl:
    cmp si, [ybot]
    jae .floor
    mov ax, [tv]
    mov bl, ah
    test bl, 15
    jz .mortar
    mov al, bl
    shr al, 4
    and al, 3
    mov dl, al
    mov al, [ucol]
    test dl, 1
    jz .nof
    add al, 32
.nof:
    and al, 63
    test al, 31
    jz .mortar
    shr al, 5
    add al, al
    add al, dl
    and al, 3
    add al, [shade]
    add al, [wbase]
    jmp .put
.mortar:
    mov al, [mcol]
.put:
    mov [es:di], al
    add di, 320
    mov ax, [tstep]
    add [tv], ax
    inc si
    jmp .wl
.floor:
    cmp si, 160
    jae .next
    mov al, [fctab+si]
    mov [es:di], al
    add di, 320
    inc si
    jmp .floor
.next:
    mov cx, [col]
    inc cx
    cmp cx, 320
    jb near .col
    popa
    ret

; ---------------------------------------------------------------
; enemy sprites (billboards, z-buffered)
; ---------------------------------------------------------------
sprites:
    pusha
    mov word [eptr], enemies
    push ax
    mov ax, [nen]
    mov [ecnt], ax
    pop ax
.e:
    mov si, [eptr]
    mov word [si+8], 0
    cmp byte [si+5], 0
    je near .skip
    mov ax, [si]
    sub ax, [px]
    mov [sdx2], ax
    mov ax, [si+2]
    sub ax, [py]
    mov [sdy2], ax
    mov ax, [sdx2]
    imul word [dcos]
    mov bx, ax
    mov cx, dx
    mov ax, [sdy2]
    imul word [dsin]
    add ax, bx
    adc dx, cx
    mov al, ah
    mov ah, dl
    mov [sdep], ax
    mov ax, [sdy2]
    imul word [dcos]
    mov bx, ax
    mov cx, dx
    mov ax, [sdx2]
    imul word [dsin]
    sub bx, ax
    sbb cx, dx
    mov al, bh
    mov ah, cl
    mov [ssid], ax
    cmp word [sdep], 64
    jl near .skip
    mov ax, [ssid]
    mov dx, 160
    imul dx
    idiv word [sdep]
    add ax, 160
    mov [ssx], ax
    mov ax, 28672
    xor dx, dx
    div word [sdep]
    cmp ax, 160
    jbe .sz
    mov ax, 160
.sz:
    cmp ax, 4
    jb near .skip
    mov [ssz], ax
    mov ax, [sdep]
    mov [si+8], ax
    mov ax, [ssx]
    mov [si+10], ax
    mov ax, [ssz]
    mov [si+12], ax
    shr ax, 1
    mov bx, [ssx]
    sub bx, ax
    mov [sleft], bx
    mov dx, 84
    sub dx, ax
    mov [stop], dx
    mov ax, 4096
    xor dx, dx
    div word [ssz]
    mov [vstep], ax
    mov ax, [stop]
    add ax, [ssz]
    cmp ax, 160
    jbe .re
    mov ax, 160
.re:
    mov [srowend], ax
    xor cx, cx
.col:
    cmp cx, [ssz]
    jae near .skip
    mov bx, [sleft]
    add bx, cx
    js near .nc
    cmp bx, 320
    jae .nc
    mov di, bx
    shl di, 1
    mov ax, [sdep]
    cmp ax, [zbuf+di]
    jae .nc
    push cx
    mov ax, cx
    shl ax, 4
    xor dx, dx
    div word [ssz]
    mov [su], ax
    mov dx, [stop]
    mov word [sv], 0
    test dx, dx
    jns .ys
    mov ax, dx
    neg ax
    mul word [vstep]
    mov [sv], ax
    xor dx, dx
.ys:
    mov ax, dx
    shl ax, 6
    mov di, ax
    shl ax, 2
    add di, ax
    add di, bx
.row:
    cmp dx, [srowend]
    jae .rd
    mov ax, [sv]
    mov al, ah
    xor ah, ah
    cmp ax, 15
    jbe .vok
    mov ax, 15
.vok:
    shl ax, 4
    add ax, [su]
    mov si, ax
    mov al, [sprite+si]
    test al, al
    jz .tr
    mov [es:di], al
.tr:
    add di, 320
    mov ax, [vstep]
    add [sv], ax
    inc dx
    jmp .row
.rd:
    pop cx
.nc:
    inc cx
    jmp .col
.skip:
    add word [eptr], 16
    dec word [ecnt]
    jnz near .e
    popa
    ret

; ---------------------------------------------------------------
; weapon, HUD, minimap
; ---------------------------------------------------------------
gun:
    pusha
    mov al, [bob]
    shr al, 3
    and al, 1
    shl al, 1
    xor ah, ah
    mov [gbob], ax
    cmp byte [flash], 0
    je .nf
    add word [gbob], 5
.nf:
    mov bx, 150
    mov cx, 112
    add cx, [gbob]
    mov dx, 20
    mov si, 50
    mov al, 137
    call fillrect
    add bx, 2
    mov dx, 4
    mov al, 138
    call fillrect
    mov bx, 130
    mov cx, 138
    add cx, [gbob]
    mov dx, 60
    mov si, 24
    mov al, 137
    call fillrect
    mov si, 3
    mov al, 138
    call fillrect
    mov bx, 146
    mov cx, 126
    add cx, [gbob]
    mov dx, 28
    mov si, 6
    mov al, 136
    call fillrect
    cmp byte [flash], 0
    je .done
    mov bx, 138
    mov cx, 92
    add cx, [gbob]
    mov dx, 44
    mov si, 22
    mov al, 133
    call fillrect
    mov bx, 146
    add cx, 4
    mov dx, 28
    mov si, 14
    mov al, 130
    call fillrect
    mov bx, 154
    add cx, 4
    mov dx, 12
    mov si, 6
    mov al, 131
    call fillrect
.done:
    popa
    ret

hud:
    pusha
    xor bx, bx
    mov cx, 160
    mov dx, 320
    mov si, 40
    mov al, 136
    call fillrect
    mov si, 2
    mov al, 138
    call fillrect
    cmp byte [hurt], 0
    je .nh
    xor bx, bx
    xor cx, cx
    mov dx, 320
    mov si, 4
    mov al, 128
    call fillrect
    mov cx, 156
    call fillrect
    xor cx, cx
    mov dx, 4
    mov si, 160
    call fillrect
    mov bx, 316
    call fillrect
.nh:
    mov word [tsc], 1
    mov si, s_health
    mov bx, 10
    mov cx, 166
    mov dl, 131
    call text
    mov si, s_ammo
    mov bx, 96
    mov cx, 166
    mov dl, 131
    call text
    mov si, s_kills
    mov bx, 230
    mov cx, 166
    mov dl, 131
    call text
    mov word [tsc], 2
    mov ax, [hp]
    mov di, numbuf
    call itoa
    mov si, numbuf
    mov bx, 10
    mov cx, 178
    mov dl, 128
    cmp word [hp], 40
    jb .hc
    mov dl, 139
.hc:
    call text
    mov ax, [ammo]
    mov di, numbuf
    call itoa
    mov si, numbuf
    mov bx, 96
    mov cx, 178
    mov dl, 130
    call text
    mov ax, [kills]
    mov di, numbuf
    call itoa
    mov si, numbuf
    mov bx, 230
    mov cx, 178
    mov dl, 140
    call text
    mov word [tsc], 1
    mov si, s_of
    mov bx, 254
    mov cx, 186
    mov dl, 138
    call text
    mov si, s_lv
    mov bx, 200
    mov cx, 186
    mov dl, 131
    call text
    ; face
    mov bx, 150
    mov cx, 166
    mov dx, 24
    mov si, 28
    mov al, 134
    call fillrect
    mov bx, 155
    mov cx, 172
    mov dx, 4
    mov si, 4
    mov al, 132
    call fillrect
    mov bx, 165
    call fillrect
    mov bx, 155
    mov cx, 184
    mov dx, 14
    mov si, 2
    mov al, 132
    cmp word [hp], 60
    jae .mouth
    mov cx, 186
    mov al, 135
.mouth:
    call fillrect
    cmp word [hp], 50
    jae .nb
    mov bx, 152
    mov cx, 168
    mov dx, 6
    mov si, 3
    mov al, 135
    call fillrect
    mov bx, 166
    mov cx, 178
    call fillrect
.nb:
    cmp word [hp], 25
    jae .map
    mov bx, 158
    mov cx, 174
    mov dx, 8
    mov si, 2
    mov al, 135
    call fillrect
.map:
    ; minimap
    xor si, si
    mov word [mrow], 0
.mr:
    mov word [mcolx], 0
.mc:
    mov ax, [mrow]
    shl ax, 4
    add ax, [mcolx]
    mov bx, ax
    mov al, [map+bx]
    mov ah, 137
    test al, al
    jz .mcol
    shl al, 4
    add al, 5
    mov ah, al
.mcol:
    mov al, ah
    mov bx, [mcolx]
    mov dx, bx
    shl bx, 1
    add bx, dx
    add bx, 4
    mov cx, [mrow]
    mov dx, cx
    shl cx, 1
    add cx, dx
    add cx, 4
    mov dx, 3
    mov si, 3
    call fillrect
    inc word [mcolx]
    cmp word [mcolx], 16
    jb .mc
    inc word [mrow]
    cmp word [mrow], 16
    jb .mr
    mov ax, [px]
    mov dx, 3
    mul dx
    mov al, ah
    mov ah, dl
    add ax, 4
    mov bx, ax
    mov ax, [py]
    mov dx, 3
    mul dx
    mov al, ah
    mov ah, dl
    add ax, 4
    mov cx, ax
    mov dx, 2
    mov si, 2
    mov al, 130
    call fillrect
    mov word [eptr], enemies
    push ax
    mov ax, [nen]
    mov [ecnt], ax
    pop ax
.me:
    mov si, [eptr]
    cmp byte [si+5], 0
    je .mn
    mov ax, [si]
    mov dx, 3
    mul dx
    mov al, ah
    mov ah, dl
    add ax, 4
    mov bx, ax
    mov ax, [si+2]
    mov dx, 3
    mul dx
    mov al, ah
    mov ah, dl
    add ax, 4
    mov cx, ax
    mov dx, 2
    mov si, 2
    mov al, 128
    call fillrect
.mn:
    add word [eptr], 16
    dec word [ecnt]
    jnz .me
    popa
    ret

; ---------------------------------------------------------------
; data
; ---------------------------------------------------------------
sintab:
    dw 0, 6, 13, 19, 25, 31, 38, 44, 50, 56, 62, 68, 74, 80, 86, 92
    dw 98, 104, 109, 115, 121, 126, 132, 137, 142, 147, 152, 157, 162, 167, 172, 177
    dw 181, 185, 190, 194, 198, 202, 206, 209, 213, 216, 220, 223, 226, 229, 231, 234
    dw 237, 239, 241, 243, 245, 247, 248, 250, 251, 252, 253, 254, 255, 255, 256, 256
    dw 256, 256, 256, 255, 255, 254, 253, 252, 251, 250, 248, 247, 245, 243, 241, 239
    dw 237, 234, 231, 229, 226, 223, 220, 216, 213, 209, 206, 202, 198, 194, 190, 185
    dw 181, 177, 172, 167, 162, 157, 152, 147, 142, 137, 132, 126, 121, 115, 109, 104
    dw 98, 92, 86, 80, 74, 68, 62, 56, 50, 44, 38, 31, 25, 19, 13, 6
    dw 0, -6, -13, -19, -25, -31, -38, -44, -50, -56, -62, -68, -74, -80, -86, -92
    dw -98, -104, -109, -115, -121, -126, -132, -137, -142, -147, -152, -157, -162, -167, -172, -177
    dw -181, -185, -190, -194, -198, -202, -206, -209, -213, -216, -220, -223, -226, -229, -231, -234
    dw -237, -239, -241, -243, -245, -247, -248, -250, -251, -252, -253, -254, -255, -255, -256, -256
    dw -256, -256, -256, -255, -255, -254, -253, -252, -251, -250, -248, -247, -245, -243, -241, -239
    dw -237, -234, -231, -229, -226, -223, -220, -216, -213, -209, -206, -202, -198, -194, -190, -185
    dw -181, -177, -172, -167, -162, -157, -152, -147, -142, -137, -132, -126, -121, -115, -109, -104
    dw -98, -92, -86, -80, -74, -68, -62, -56, -50, -44, -38, -31, -25, -19, -13, -6
map:
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 3, 0, 0, 0, 1
    db 1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 1
    db 1, 0, 0, 2, 0, 0, 0, 4, 4, 0, 0, 3, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 3, 3, 0, 0, 4, 0, 0, 0, 2, 2, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1
    db 1, 0, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 4, 0, 0, 0, 0, 3, 3, 3, 0, 0, 0, 0, 0, 1
    db 1, 0, 4, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 1
    db 1, 0, 4, 0, 0, 0, 0, 0, 0, 3, 0, 0, 4, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 1
    db 1, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 4, 0, 1
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
sprite:
    db 0, 0, 130, 130, 0, 0, 0, 0, 0, 0, 0, 0, 130, 130, 0, 0
    db 0, 0, 130, 133, 130, 0, 0, 0, 0, 0, 0, 130, 133, 130, 0, 0
    db 0, 0, 0, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 0, 0, 0
    db 0, 0, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 0, 0
    db 0, 128, 128, 128, 128, 128, 131, 131, 131, 131, 128, 128, 128, 128, 128, 0
    db 0, 128, 128, 128, 128, 131, 131, 130, 130, 131, 131, 128, 128, 128, 128, 0
    db 0, 128, 128, 128, 131, 131, 130, 130, 132, 132, 130, 131, 128, 128, 128, 0
    db 0, 128, 128, 128, 131, 130, 130, 132, 132, 132, 130, 130, 131, 128, 128, 0
    db 0, 128, 128, 128, 131, 130, 130, 132, 132, 132, 130, 130, 131, 128, 128, 0
    db 0, 128, 128, 128, 128, 131, 131, 130, 130, 131, 131, 128, 128, 128, 128, 0
    db 0, 128, 128, 128, 128, 128, 131, 131, 131, 131, 128, 128, 128, 128, 128, 0
    db 0, 129, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 129, 0
    db 0, 0, 129, 128, 131, 128, 131, 128, 131, 128, 131, 128, 131, 129, 0, 0
    db 0, 0, 129, 129, 128, 128, 128, 128, 128, 128, 128, 128, 129, 129, 0, 0
    db 0, 0, 0, 129, 129, 129, 129, 129, 129, 129, 129, 129, 129, 0, 0, 0
    db 0, 0, 0, 0, 129, 129, 129, 129, 129, 129, 129, 129, 0, 0, 0, 0
fctab:
    db 96, 96, 96, 96, 96, 96, 97, 97, 97, 97, 97, 98, 98, 98, 98, 98
    db 99, 99, 99, 99, 99, 99, 100, 100, 100, 100, 100, 101, 101, 101, 101, 101
    db 102, 102, 102, 102, 102, 103, 103, 103, 103, 103, 103, 104, 104, 104, 104, 104
    db 105, 105, 105, 105, 105, 106, 106, 106, 106, 106, 107, 107, 107, 107, 107, 107
    db 108, 108, 108, 108, 108, 109, 109, 109, 109, 109, 110, 110, 110, 110, 110, 111
    db 127, 126, 126, 126, 126, 126, 125, 125, 125, 125, 125, 124, 124, 124, 124, 124
    db 123, 123, 123, 123, 123, 123, 122, 122, 122, 122, 122, 121, 121, 121, 121, 121
    db 120, 120, 120, 120, 120, 119, 119, 119, 119, 119, 119, 118, 118, 118, 118, 118
    db 117, 117, 117, 117, 117, 116, 116, 116, 116, 116, 115, 115, 115, 115, 115, 115
    db 114, 114, 114, 114, 114, 113, 113, 113, 113, 113, 112, 112, 112, 112, 112, 112
etab:
    dw 3456, 640, 3456, 1920, 1664, 2944, 3456, 2944
    dw 1408, 1408, 2432, 2176, 640, 3456
; ---- level table: 4 records of 300 bytes (map 256, start x/y/angle, count, 9 enemies)
level_tab:
; level 1
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 3, 0, 0, 0, 1
    db 1, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 1
    db 1, 0, 0, 2, 0, 0, 0, 4, 4, 0, 0, 3, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 3, 3, 0, 0, 4, 0, 0, 0, 2, 2, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1
    db 1, 0, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 4, 0, 0, 0, 0, 3, 3, 3, 0, 0, 0, 0, 0, 1
    db 1, 0, 4, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 1
    db 1, 0, 4, 0, 0, 0, 0, 0, 0, 3, 0, 0, 4, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 1
    db 1, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 4, 0, 1
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    dw 384, 384, 0x1800, 7
    dw 3456, 640, 3456, 1920, 1664, 2944
    dw 3456, 2944, 1408, 1408, 2432, 2176
    dw 640, 3456, 0, 0, 0, 0

; level 2
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 3, 4, 0, 0, 0, 0, 0, 0, 4, 4, 0, 0, 1
    db 1, 0, 0, 3, 3, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 4, 4, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 4, 3, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 1
    db 1, 0, 0, 4, 4, 0, 0, 0, 0, 0, 0, 3, 3, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    dw 384, 384, 0x0000, 9
    dw 1664, 640, 1408, 3712, 640, 2688
    dw 640, 2944, 2688, 3712, 1920, 1408
    dw 3200, 3712, 2432, 384, 640, 3456

; level 3
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    db 1, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 1
    db 1, 2, 2, 0, 3, 3, 3, 3, 3, 0, 2, 2, 2, 0, 4, 1
    db 1, 0, 3, 0, 0, 0, 0, 0, 4, 0, 3, 0, 3, 0, 4, 1
    db 1, 0, 2, 4, 2, 2, 4, 0, 3, 0, 2, 0, 4, 0, 4, 1
    db 1, 0, 0, 0, 0, 0, 2, 0, 4, 0, 3, 0, 0, 0, 4, 1
    db 1, 0, 2, 0, 4, 3, 4, 0, 3, 0, 2, 3, 2, 4, 4, 1
    db 1, 0, 4, 0, 3, 0, 0, 0, 4, 0, 2, 0, 0, 0, 4, 1
    db 1, 0, 2, 0, 2, 0, 3, 4, 2, 0, 2, 0, 4, 0, 3, 1
    db 1, 0, 3, 0, 4, 0, 0, 0, 2, 0, 2, 0, 3, 0, 3, 1
    db 1, 0, 3, 0, 2, 4, 4, 0, 3, 0, 3, 0, 4, 0, 3, 1
    db 1, 0, 3, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 2, 1
    db 1, 0, 3, 2, 3, 0, 2, 3, 4, 4, 2, 3, 4, 0, 3, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 1
    db 1, 2, 4, 2, 3, 4, 2, 3, 2, 3, 4, 3, 2, 4, 3, 1
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    dw 384, 384, 0x0000, 8
    dw 1920, 2688, 1408, 2432, 1152, 896
    dw 3456, 1152, 640, 1408, 3456, 896
    dw 2432, 384, 2944, 1152, 0, 0

; level 4
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    db 1, 0, 3, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 2, 1
    db 1, 0, 2, 2, 3, 0, 2, 0, 2, 2, 4, 0, 3, 0, 2, 1
    db 1, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 2, 0, 4, 1
    db 1, 3, 2, 3, 4, 0, 3, 3, 3, 2, 4, 0, 2, 0, 2, 1
    db 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 3, 0, 2, 1
    db 1, 4, 4, 4, 2, 0, 4, 0, 4, 0, 4, 0, 4, 0, 2, 1
    db 1, 0, 0, 0, 0, 0, 2, 0, 3, 0, 3, 0, 0, 0, 2, 1
    db 1, 0, 3, 4, 2, 4, 2, 0, 3, 0, 4, 0, 4, 0, 3, 1
    db 1, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 2, 0, 2, 1
    db 1, 0, 3, 0, 2, 0, 3, 0, 4, 0, 3, 4, 4, 0, 3, 1
    db 1, 0, 4, 0, 2, 0, 4, 0, 4, 0, 0, 0, 0, 0, 2, 1
    db 1, 0, 4, 0, 4, 0, 4, 3, 4, 0, 3, 3, 4, 0, 4, 1
    db 1, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 1
    db 1, 2, 2, 4, 3, 2, 3, 2, 3, 4, 3, 2, 2, 4, 2, 1
    db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    dw 384, 384, 0x0000, 9
    dw 1408, 3200, 1920, 2432, 896, 2688
    dw 896, 3200, 2432, 384, 1664, 3456
    dw 3456, 3200, 2432, 3456, 1408, 2432


level   db 0                 ; current level (0-based)
nen     dw 7                 ; enemies in this level
fresh   db 1                 ; 1 = full health and ammo on the next load
s_next  db "ENTER: next level", 0
s_all   db "ALL CLEAR", 0
s_title db "DOOMISH", 0
s_sub   db "a tiny parody for SpheraOS", 0
s_k1    db "W/S move  A/D strafe  arrows turn", 0
s_k2    db "SPACE / CTRL fire     ESC quit", 0
s_press db "Press any key", 0
s_dead  db "YOU DIED", 0
s_win   db "LEVEL CLEAR", 0
s_again db "R: restart   ESC: quit", 0
s_health db "HEALTH", 0
s_ammo  db "AMMO", 0
s_kills db "KILLS", 0
s_of    db "/0", 0
s_lv    db "LV 1", 0
paltab:
    db 0, 0, 0, 0
    db 128, 58, 8, 8
    db 129, 30, 0, 0
    db 130, 63, 56, 8
    db 131, 63, 63, 63
    db 132, 2, 2, 2
    db 133, 60, 32, 6
    db 134, 58, 44, 34
    db 135, 45, 0, 0
    db 136, 20, 20, 22
    db 137, 10, 10, 12
    db 138, 36, 36, 40
    db 139, 10, 50, 10
    db 140, 63, 52, 12
    db 0xFF
ramptab:
    db 16, 0, 50, 18, 12
    db 32, 0, 38, 38, 42
    db 48, 0, 16, 40, 16
    db 64, 0, 14, 26, 52
    db 80, 0, 30, 30, 34
    db 96, 1, 16, 20, 44
    db 112, 1, 40, 30, 22
    db 0xFF

absolute 0x3000
old9    resw 2
fontseg resw 1
fontoff resw 1
seed    resw 1
ftick   resw 1
px      resw 1
py      resw 1
pa16    resw 1
pidx    resw 1
dcos    resw 1
dsin    resw 1
mvx     resw 1
mvy     resw 1
nx      resw 1
ny      resw 1
hp      resw 1
ammo    resw 1
kills   resw 1
ent_dx     resw 1
edy     resw 1
best    resw 1
bestp   resw 1
tsc     resw 1
col     resw 1
coloff  resw 1
ridx    resw 1
ray_dx     resw 1
rdy     resw 1
ddx     resw 1
ddy     resw 1
stx     resw 1
sty     resw 1
sdx     resw 1
sdy     resw 1
tdist   resw 1
dist    resw 1
lineh   resw 1
top     resw 1
ytop    resw 1
ybot    resw 1
tstep   resw 1
tv      resw 1
gbob    resw 1
sdx2    resw 1
sdy2    resw 1
sdep    resw 1
ssid    resw 1
ssx     resw 1
ssz     resw 1
sleft   resw 1
stop    resw 1
vstep   resw 1
srowend resw 1
su      resw 1
sv      resw 1
eptr    resw 1
ecnt    resw 1
mrow    resw 1
mcolx   resw 1
state   resb 1
flash   resb 1
cool    resb 1
hurt    resb 1
bob     resb 1
side    resb 1
wtype   resb 1
wbase   resb 1
shade   resb 1
mcol    resb 1
ucol    resb 1
tcol    resb 1
rs      resb 1
rm      resb 1
rr      resb 1
rg      resb 1
rb      resb 1
numbuf  resb 8
keys    resb 128
enemies resb 144
zbuf    resb 640
