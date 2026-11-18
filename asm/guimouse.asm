; ============================================================
;  SpheraOS GUI  -  gui.asm   (v4)
;  16-bit real mode, VGA 320x200x256, FAT12 (read + write)
;
;  Build:  nasm -f bin gui.asm -o gui.bin
;  Run:    "run gui.bin"   (keep gui.bin smaller than 24 KB)
;
;  Keys:  F1 Files  F2 Clock  F3 Tasks  F4 Notes  F8 Setup
;  Mouse:  click = focus window / select row in Files & Setup,
;          second click on a row opens the file,
;          drag the title bar to move a window,
;          click the [x] box to close, taskbar button to focus.
;         F5 maximize / restore the focused window
;         F6 move mode  (arrows move, Enter = done)
;         F7 size mode  (arrows resize, Enter = done)
;         Tab = next window   F10 = close window   Esc = exit
;  Files : Up/Down, Enter opens (*.APP starts a program)
;  Notes : a text editor.  Arrows/Home/End/PgUp/PgDn move,
;          Backspace/Del/Enter edit, Ctrl+S save, Ctrl+N new.
;          The view scrolls left/right/up/down with the cursor.
;  Setup : Up/Down pick, Left/Right = +-1, PgUp/PgDn = +-16,
;          S or Enter = save to GUI.CFG
;
;  GUI programs (*.APP): see sdk.inc (INT 60h API).
; ============================================================
BITS 16
ORG 0

; ---- memory layout inside the GUI segment --------------------
; 0000..5FFF  code + data
; 6000..7FFF  Notes text buffer (max 8 KB)
; 8000..9BFF  root directory (224 entries)
; A000..B7FF  FAT (max 12 sectors)
; B800..B9FF  boot sector copy
; BA00..BFFF  disk bounce buffer (DMA-safe), stack at FFF0

FBUF      equ 0xA000    ; сдвигаем текст на 40 КБ
FMAX      equ 8192
ROOT_BUF  equ 0xC000
FAT_BUF   equ 0xE000
SECBUF    equ 0xF400
BOUNCE0   equ 0xF600
VIDEO     equ 0xA000
API_VEC   equ 0x60
API_N     equ 12
MAXWIN    equ 8
WSHIFT    equ 5                 ; window record = 32 bytes
WSTEP     equ 8                 ; move / size step in pixels
WMIN      equ 56
HMIN      equ 40

; ---- layout metrics -------------------------------------------
CW        equ 6                 ; character cell width  (glyph 5x7)
ROW_H     equ 8                 ; character cell height
TITLE_H   equ 9                 ; title bar height
TASKBAR_Y equ 189               ; top of the taskbar
CONT_Y    equ 12                ; first text line inside a window
ROW0      equ 21                ; first list row inside a window
STATUS_H  equ 10                ; Notes status bar height

; window record (32 bytes)
W_USED    equ 0
W_TYPE    equ 1
W_X       equ 2
W_Y       equ 4
W_W       equ 6
W_H       equ 8
W_SEL     equ 10                ; selection / top line
W_TICK    equ 12
W_SEG     equ 14                ; program segment (apps)
W_XOFF    equ 16                ; horizontal scroll (Notes)
W_SX      equ 18                ; saved geometry for F5
W_SY      equ 20
W_SW      equ 22
W_SH      equ 24
W_MAX     equ 26
WSZ       equ 32

T_FILES   equ 1
T_CLOCK   equ 2
T_TASKS   equ 3
T_NOTE    equ 4
T_APP     equ 5
T_SET     equ 6

; ============================================================
;  Entry point (offset 0)
; ============================================================
start:
    pusha
    push ds
    push es
    push fs
    push gs
    mov [cs:old_ss], ss         ; CS override: DS still belongs to the caller
    mov [cs:old_sp], sp
    mov ax, cs
    mov ds, ax
    mov ss, ax
    mov sp, 0xFFF0
    cld
    sti

    xor ax, ax
    mov gs, ax                  ; GS = BIOS data area / IVT
    mov dl, [gs:0x500]          ; boot drive (stored by boot.asm)
    mov [drive], dl
    mov ax, [gs:0x46C]
    mov [seed], ax

    call choose_bb
    call choose_bounce
    call mount
    call load_cfg

    cli                         ; hook INT 60h (GUI program API)
    mov ax, [gs:API_VEC*4]
    mov [old_v_off], ax
    mov ax, [gs:API_VEC*4+2]
    mov [old_v_seg], ax
    mov word [gs:API_VEC*4], api_int
    mov [gs:API_VEC*4+2], cs
    sti

    mov ax, 0x0013              ; 320x200, 256 colors
    int 0x10
    xor ax, ax
    mov gs, ax

    call mouse_init             ; PS/2 mouse (polled through the 8042)

    mov al, T_FILES
    call open_win

    mov ax, [gs:0x46C]
    mov [last_tick], ax
    mov byte [last_sec], 0xFF
    mov byte [dirty], 1
    call redraw

main_loop:
    call poll_mouse             ; PS/2 mouse: collect packets, move the cursor
    call handle_mouse           ; buttons: click / drag / close / select
    mov ah, 0x01
    int 0x16
    jnz .key
    mov ax, [gs:0x46C]          ; timer tick (18.2 Hz)
    cmp ax, [last_tick]
    jne .tick
    jmp .paint
.tick:
    mov [last_tick], ax
    call tick_all
    call check_clock
.paint:
    cmp byte [dirty], 0
    je main_loop
    call redraw
    jmp main_loop
.key:
    mov ah, 0x00
    int 0x16                    ; AL = ascii, AH = scan
    mov word [msgp], 0
    call handle_key
    mov byte [dirty], 1
    jmp .paint

exit_gui:
    xor cx, cx                  ; tell every GUI program it is closing
.cl:
    cmp cx, MAXWIN
    jae .done
    mov ax, cx
    shl ax, WSHIFT
    add ax, wins
    mov si, ax
    cmp byte [si+W_USED], 0
    je .nx
    cmp byte [si+W_TYPE], T_APP
    jne .nx
    mov ax, 4                   ; MSG_CLOSE
    call call_app
.nx:
    inc cx
    jmp .cl
.done:
    in al, 0x61                 ; speaker off
    and al, 0xFC
    out 0x61, al
    xor ax, ax
    mov gs, ax
    cli
    mov ax, [old_v_off]
    mov [gs:API_VEC*4], ax
    mov ax, [old_v_seg]
    mov [gs:API_VEC*4+2], ax
    sti
    cmp byte [wrote], 0         ; we changed the disk: make the kernel
    je .nocache                 ; forget its cached FAT / root directory
    mov ax, 0x1000              ; KSEG
    mov es, ax
    mov al, [drive]
    cmp al, [es:0xA000]         ; kernel bdrive must match
    jne .nocache
    cmp byte [es:0xA001], 1     ; dir_ok
    ja .nocache
    cmp byte [es:0xA002], 1     ; fat_ok
    ja .nocache
    mov word [es:0xA001], 0     ; dir_ok = fat_ok = 0
.nocache:
    call mouse_off              ; PS/2 mouse off
    mov ax, 0x0003
    int 0x10
    mov ss, [old_ss]
    mov sp, [old_sp]
    pop gs
    pop fs
    pop es
    pop ds
    popa
    retf

; ============================================================
;  Scheduler
; ============================================================
tick_all:
    mov word [ti2], 0
.l:
    mov ax, [ti2]
    cmp ax, MAXWIN
    jae near .d
    shl ax, WSHIFT
    add ax, wins
    mov si, ax
    cmp byte [si+W_USED], 0
    je near .n
    inc word [si+W_TICK]
    mov al, [si+W_TYPE]
    cmp al, T_TASKS
    jne .a
    mov byte [dirty], 1
.a:
    cmp al, T_APP
    jne .n
    mov ax, 1                   ; MSG_TICK
    call call_app
    cmp byte [app_ret], 0
    je .nr
    mov byte [dirty], 1
.nr:
    cmp byte [close_req], 0
    je .n
    mov byte [close_req], 0
    call kill_window
    mov byte [dirty], 1
.n:
    inc word [ti2]
    jmp .l
.d:
    ret

check_clock:
    mov ah, 0x02
    int 0x1A
    jc .r
    cmp dh, [last_sec]
    je .r
    mov [last_sec], dh
    mov byte [dirty], 1
.r:
    ret

; ============================================================
;  Keyboard
; ============================================================
handle_key:                     ; AH = scan code, AL = ascii
    mov [last_key], ax
    mov dl, [quit_warn]
    mov [warn_prev], dl
    mov byte [quit_warn], 0
    cmp byte [wmode], 0
    jne near wmode_key
    cmp ah, 0x01                ; Esc
    je near .esc
    cmp ah, 0x3B                ; F1
    jne .k2
    mov al, T_FILES
    jmp open_win
.k2:
    cmp ah, 0x3C                ; F2
    jne .k3
    mov al, T_CLOCK
    jmp open_win
.k3:
    cmp ah, 0x3D                ; F3
    jne .k4
    mov al, T_TASKS
    jmp open_win
.k4:
    cmp ah, 0x3E                ; F4
    jne .k5
    mov al, T_NOTE
    jmp open_win
.k5:
    cmp ah, 0x3F                ; F5 maximize
    jne .k6
    jmp toggle_max
.k6:
    cmp ah, 0x40                ; F6 move
    jne .k7
    mov al, 1
    jmp wmode_start
.k7:
    cmp ah, 0x41                ; F7 size
    jne .k8
    mov al, 2
    jmp wmode_start
.k8:
    cmp ah, 0x42                ; F8 setup
    jne .k9
    mov al, T_SET
    jmp open_win
.k9:
    cmp ah, 0x44                ; F10 close
    jne .k10
    jmp close_focus
.k10:
    cmp ah, 0x0F                ; Tab
    jne .k11
    jmp focus_next
.k11:
    mov si, [focus]
    test si, si
    jz .r
    movzx bx, byte [si+W_TYPE]
    cmp bx, T_FILES
    jne .k12
    jmp files_key
.k12:
    cmp bx, T_NOTE
    jne .k13
    jmp note_key
.k13:
    cmp bx, T_SET
    jne .k14
    jmp set_key
.k14:
    cmp bx, T_APP
    jne .r
.toapp:                         ; SI = focused app window
    mov ax, 2                   ; MSG_KEY
    mov bx, [last_key]          ; BL = ascii, BH = scan
    call call_app
    cmp byte [close_req], 0
    je .r
    mov byte [close_req], 0
    jmp kill_window
.r:
    ret
.esc:
    mov si, [focus]
    test si, si
    jz .quit
    mov al, [si+W_TYPE]
    cmp al, T_APP
    je .toapp
    cmp al, T_NOTE
    jne .quit
    cmp byte [note_mode], 1
    jne .quit
    mov byte [note_mode], 0     ; Esc cancels the "Save as" prompt
    ret
.quit:
    cmp byte [note_mod], 0
    je .go
    cmp byte [warn_prev], 0
    jne .go
    mov word [msgp], s_unsaved2
    mov byte [quit_warn], 1
    ret
.go:
    jmp exit_gui

files_key:
    cmp ah, 0x48                ; Up
    je .up
    cmp ah, 0x50                ; Down
    je .dn
    cmp ah, 0x1C                ; Enter
    je near open_sel
    ret
.up:
    mov si, [focus]
    cmp word [si+W_SEL], 0
    je .r
    dec word [si+W_SEL]
.r:
    ret
.dn:
    call dir_count
    test ax, ax
    jz .r
    dec ax
    mov si, [focus]
    cmp [si+W_SEL], ax
    jae .r
    inc word [si+W_SEL]
    ret

set_key:                        ; Setup window: SI = window
    cmp ah, 0x48
    jne .a
    cmp word [si+W_SEL], 0
    je .r
    dec word [si+W_SEL]
    ret
.a:
    cmp ah, 0x50
    jne .b
    cmp word [si+W_SEL], 3
    jae .r
    inc word [si+W_SEL]
    ret
.b:
    mov bx, [si+W_SEL]
    cmp ah, 0x4B                ; Left
    jne .c
    dec byte [cfg+bx]
    ret
.c:
    cmp ah, 0x4D                ; Right
    jne .d
    inc byte [cfg+bx]
    ret
.d:
    cmp ah, 0x49                ; PgUp
    jne .e
    add byte [cfg+bx], 16
    ret
.e:
    cmp ah, 0x51                ; PgDn
    jne .f
    sub byte [cfg+bx], 16
    ret
.f:
    cmp ah, 0x1C
    je .save
    cmp al, 's'
    je .save
    cmp al, 'S'
    jne .r
.save:
    call save_cfg
.r:
    ret

; ---- move / size mode ----------------------------------------
wmode_start:                    ; AL = 1 move, 2 size
    cmp word [focus], 0
    je .r
    mov [wmode], al
    mov word [msgp], s_move
    cmp al, 1
    je .r
    mov word [msgp], s_sizem
.r:
    ret

wmode_key:
    cmp ah, 0x01
    je .end
    cmp ah, 0x1C
    je .end
    cmp ah, 0x40
    je .end
    cmp ah, 0x41
    je .end
    mov si, [focus]
    test si, si
    jz .end
    xor bx, bx
    xor cx, cx
    cmp ah, 0x4B
    jne .r1
    mov bx, -WSTEP
.r1:
    cmp ah, 0x4D
    jne .r2
    mov bx, WSTEP
.r2:
    cmp ah, 0x48
    jne .r3
    mov cx, -WSTEP
.r3:
    cmp ah, 0x50
    jne .r4
    mov cx, WSTEP
.r4:
    mov ax, bx
    or ax, cx
    jz .keep
    cmp byte [wmode], 2
    je near .size
    mov ax, [si+W_X]            ; move
    add ax, bx
    jge .x1
    xor ax, ax
.x1:
    mov dx, 320
    sub dx, [si+W_W]
    cmp ax, dx
    jle .x2
    mov ax, dx
.x2:
    mov [si+W_X], ax
    mov ax, [si+W_Y]
    add ax, cx
    jge .y1
    xor ax, ax
.y1:
    mov dx, TASKBAR_Y
    sub dx, [si+W_H]
    cmp ax, dx
    jle .y2
    mov ax, dx
.y2:
    mov [si+W_Y], ax
    jmp .fix
.size:
    mov word [si+W_MAX], 0
    mov ax, [si+W_W]
    add ax, bx
    cmp ax, WMIN
    jge .w1
    mov ax, WMIN
.w1:
    mov dx, 320
    sub dx, [si+W_X]
    cmp ax, dx
    jle .w2
    mov ax, dx
.w2:
    mov [si+W_W], ax
    mov ax, [si+W_H]
    add ax, cx
    cmp ax, HMIN
    jge .h1
    mov ax, HMIN
.h1:
    mov dx, TASKBAR_Y
    sub dx, [si+W_Y]
    cmp ax, dx
    jle .h2
    mov ax, dx
.h2:
    mov [si+W_H], ax
.fix:
    call win_changed
.keep:
    cmp byte [wmode], 1
    mov word [msgp], s_move
    je .r
    mov word [msgp], s_sizem
.r:
    ret
.end:
    mov byte [wmode], 0
    ret

; win_changed: SI = window whose geometry changed
win_changed:
    cmp byte [si+W_TYPE], T_NOTE
    jne .r
    call note_scroll
.r:
    ret

; toggle_max: F5
toggle_max:
    mov si, [focus]
    test si, si
    jz .r
    cmp word [si+W_MAX], 0
    jne .rest
    mov ax, [si+W_X]
    mov [si+W_SX], ax
    mov ax, [si+W_Y]
    mov [si+W_SY], ax
    mov ax, [si+W_W]
    mov [si+W_SW], ax
    mov ax, [si+W_H]
    mov [si+W_SH], ax
    mov word [si+W_X], 0
    mov word [si+W_Y], 0
    mov word [si+W_W], 320
    mov word [si+W_H], TASKBAR_Y
    mov word [si+W_MAX], 1
    jmp .fix
.rest:
    mov ax, [si+W_SX]
    mov [si+W_X], ax
    mov ax, [si+W_SY]
    mov [si+W_Y], ax
    mov ax, [si+W_SW]
    mov [si+W_W], ax
    mov ax, [si+W_SH]
    mov [si+W_H], ax
    mov word [si+W_MAX], 0
.fix:
    call win_changed
.r:
    ret

; ============================================================
;  Windows
; ============================================================
; open_win: AL = type (builtin apps)
open_win:
    mov [ow_t], al
    mov word [ow_i], 0
.f:
    mov ax, [ow_i]
    cmp ax, MAXWIN
    jae .new
    shl ax, WSHIFT
    add ax, wins
    mov si, ax
    cmp byte [si+W_USED], 0
    je .fn
    mov al, [ow_t]
    cmp [si+W_TYPE], al
    jne .fn
    mov [focus], si
    ret
.fn:
    inc word [ow_i]
    jmp .f
.new:
    call find_free_win
    jc .none
    mov byte [si+W_USED], 1
    mov al, [ow_t]
    mov [si+W_TYPE], al
    movzx bx, al
    shl bx, 3
    mov ax, [deftab+bx]
    mov [si+W_X], ax
    mov ax, [deftab+bx+2]
    mov [si+W_Y], ax
    mov ax, [deftab+bx+4]
    mov [si+W_W], ax
    mov ax, [deftab+bx+6]
    mov [si+W_H], ax
    mov word [si+W_SEL], 0
    mov word [si+W_TICK], 0
    mov word [si+W_SEG], 0
    mov word [si+W_XOFF], 0
    mov word [si+W_MAX], 0
    mov [focus], si
    cmp byte [ow_t], T_NOTE
    jne .none
    call note_reset             ; a new Notes window starts empty
.none:
    ret

; find_free_win: -> SI = free window record, CF=1 if none
find_free_win:
    xor cx, cx
.l:
    cmp cx, MAXWIN
    jae .no
    mov ax, cx
    shl ax, WSHIFT
    add ax, wins
    mov si, ax
    cmp byte [si+W_USED], 0
    je .ok
    inc cx
    jmp .l
.ok:
    clc
    ret
.no:
    stc
    ret

close_focus:
    mov si, [focus]
    test si, si
    jz .r
    mov al, [si+W_TYPE]
    cmp al, T_APP
    jne .nq
    mov ax, 4                   ; MSG_CLOSE
    call call_app
    jmp .k
.nq:
    cmp al, T_NOTE
    jne .k
    cmp byte [note_mod], 0
    je .nm
    cmp byte [warn_prev], 0
    jne .nm
    mov word [msgp], s_unsaved3
    mov byte [quit_warn], 1
    ret
.nm:
    mov byte [note_mod], 0
    mov byte [note_mode], 0
.k:
    call kill_window
.r:
    ret

; kill_window: SI = window record
kill_window:
    mov byte [si+W_USED], 0
    cmp si, [focus]
    jne .r
    mov word [focus], 0
    call focus_next
.r:
    ret

focus_next:
    mov ax, [focus]
    test ax, ax
    jz .s0
    sub ax, wins
    shr ax, WSHIFT
    jmp .s1
.s0:
    mov ax, MAXWIN-1
.s1:
    mov dx, ax
    mov cx, MAXWIN
.nx:
    inc dx
    cmp dx, MAXWIN
    jb .ok
    xor dx, dx
.ok:
    mov ax, dx
    shl ax, WSHIFT
    add ax, wins
    mov si, ax
    cmp byte [si+W_USED], 0
    jne .got
    loop .nx
    ret
.got:
    mov [focus], si
    ret

; win_title: SI = window record -> SI = title string
win_title:
    push bx
    movzx bx, byte [si+W_TYPE]
    cmp bx, T_APP
    je .app
    shl bx, 1
    mov si, [title_tab+bx]
    pop bx
    ret
.app:
    sub si, wins
    shr si, WSHIFT
    imul si, si, 12
    add si, wtitles
    pop bx
    ret

; ============================================================
;  Drawing (back buffer in ES, then one copy to the screen)
; ============================================================
redraw:
    mov byte [dirty], 0
    mov ax, [bbseg]
    mov es, ax
    mov word [clip_r], 320
    mov word [clip_b], 200

    mov al, [cfg]               ; wallpaper
    xor bx, bx
    xor cx, cx
    mov dx, 320
    mov si, TASKBAR_Y
    call fill_rect

    mov si, s_brand
    mov bx, 4
    mov cx, 2
    mov dl, 15
    call draw_str
    mov si, [msgp]              ; status / error message
    test si, si
    jz .nomsg
    mov bx, 88
    mov cx, 2
    mov dl, 14
    call draw_str
.nomsg:
    mov si, s_hint1
    mov bx, 4
    mov cx, 171
    mov dl, 15
    call draw_str
    mov si, s_hint2
    mov bx, 4
    mov cx, 180
    mov dl, 15
    call draw_str

    mov word [ti], 0            ; background windows, then the focused one
.w1:
    mov ax, [ti]
    cmp ax, MAXWIN
    jae .w2
    shl ax, WSHIFT
    add ax, wins
    mov si, ax
    cmp byte [si+W_USED], 0
    je .w1n
    cmp si, [focus]
    je .w1n
    mov [cur_win], si
    call draw_window
.w1n:
    inc word [ti]
    jmp .w1
.w2:
    mov si, [focus]
    test si, si
    jz .tb
    mov [cur_win], si
    call draw_window
.tb:
    call draw_taskbar
    call draw_cursor            ; mouse pointer on top of everything
    call blit
    ret

blit:
    mov ax, [bbseg]
    cmp ax, VIDEO               ; no back buffer: already on screen
    je .r
    push ds
    push es
    mov dx, 0x3DA
    mov cx, 0xFFFF
.w1:
    in al, dx
    test al, 8
    jz .w2s
    loop .w1
.w2s:
    mov cx, 0xFFFF
.w2:
    in al, dx
    test al, 8
    jnz .go
    loop .w2
.go:
    mov ax, [bbseg]
    mov ds, ax
    mov ax, VIDEO
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 16000
    rep movsd
    pop es
    pop ds
.r:
    ret

draw_window:
    mov si, [cur_win]
    mov ax, [si+W_X]
    mov [wx], ax
    mov ax, [si+W_Y]
    mov [wy], ax
    mov ax, [si+W_W]
    mov [ww], ax
    mov ax, [si+W_H]
    mov [wh], ax
    movzx ax, byte [si+W_TYPE]
    mov [wtype], ax

    mov ax, [wx]
    add ax, [ww]
    mov [clip_r], ax
    mov ax, [wy]
    add ax, [wh]
    mov [clip_b], ax

    xor al, al                  ; black border
    mov bx, [wx]
    mov cx, [wy]
    mov dx, [ww]
    mov si, [wh]
    call fill_rect

    mov al, 8                   ; title bar
    mov di, [cur_win]
    cmp di, [focus]
    jne .tb
    mov al, [cfg+1]
.tb:
    mov bx, [wx]
    inc bx
    mov cx, [wy]
    inc cx
    mov dx, [ww]
    sub dx, 2
    mov si, TITLE_H
    call fill_rect

    mov al, [cfg+3]             ; body
    mov bx, [wx]
    inc bx
    mov cx, [wy]
    add cx, TITLE_H+1
    mov dx, [ww]
    sub dx, 2
    mov si, [wh]
    sub si, TITLE_H+2
    call fill_rect

    mov si, [cur_win]           ; title text
    call win_title
    mov bx, [wx]
    add bx, 4
    mov cx, [wy]
    add cx, 2
    mov dl, 15
    call draw_str

    mov al, 4                   ; close box
    mov bx, [wx]
    add bx, [ww]
    sub bx, 10
    mov cx, [wy]
    add cx, 2
    mov dx, 7
    mov si, 7
    call fill_rect
    mov al, 'x'
    mov bx, [wx]
    add bx, [ww]
    sub bx, 9
    mov cx, [wy]
    add cx, 2
    mov dl, 15
    call draw_char

    mov bx, [wtype]
    shl bx, 1
    call word [content_tab+bx]
    ret

draw_taskbar:
    mov word [clip_r], 320
    mov word [clip_b], 200
    mov al, [cfg+2]
    xor bx, bx
    mov cx, TASKBAR_Y
    mov dx, 320
    mov si, 200-TASKBAR_Y
    call fill_rect
    mov al, 15
    xor bx, bx
    mov cx, TASKBAR_Y
    mov dx, 320
    mov si, 1
    call fill_rect

    mov word [ti], 0
.l:
    mov ax, [ti]
    cmp ax, MAXWIN
    jae near .clk
    shl ax, WSHIFT
    add ax, wins
    mov si, ax
    cmp byte [si+W_USED], 0
    je near .n
    mov [tsp], si
    mov al, 8
    mov dl, 15
    cmp si, [focus]
    jne .c
    mov al, 15
    mov dl, 0
.c:
    mov [tbt], dl
    mov bx, [ti]
    imul bx, bx, 34
    add bx, 4
    mov [tbx], bx
    mov cx, TASKBAR_Y+1
    mov dx, 33
    mov si, 9
    call fill_rect

    mov si, [tsp]
    call win_title
    mov bx, [tbx]
    add bx, 2
    mov cx, TASKBAR_Y+2
    mov dl, [tbt]
    mov ax, [tbx]
    add ax, 33
    mov [clip_r], ax
    call draw_str
.n:
    inc word [ti]
    jmp .l
.clk:
    mov word [clip_r], 320
    mov word [clip_b], 200
    mov ah, 0x02
    int 0x1A
    mov di, tbuf
    mov al, ch
    call put2
    mov byte [di], ':'
    inc di
    mov al, cl
    call put2
    mov byte [di], 0
    mov si, tbuf
    mov bx, 288
    mov cx, TASKBAR_Y+2
    mov dl, 0
    call draw_str
    ret

; ============================================================
;  Window contents
; ============================================================
c_files:
    mov si, s_name
    mov bx, [wx]
    add bx, 4
    mov cx, [wy]
    add cx, CONT_Y
    mov dl, 0
    call draw_str
    mov si, s_size
    mov bx, [wx]
    add bx, 80
    mov cx, [wy]
    add cx, CONT_Y
    mov dl, 0
    call draw_str
    mov si, s_enter
    mov bx, [wx]
    add bx, 4
    mov cx, [wy]
    add cx, [wh]
    sub cx, 9
    mov dl, 0
    call draw_str

    mov ax, [wh]                ; visible rows
    sub ax, ROW0+11
    jns .a
    xor ax, ax
.a:
    xor dx, dx
    mov cx, ROW_H
    div cx
    test ax, ax
    jnz .b
    inc ax
.b:
    mov [frows], ax
    mov si, [cur_win]           ; first visible index
    mov ax, [si+W_SEL]
    xor dx, dx
    mov cx, [frows]
    div cx
    mov ax, [si+W_SEL]
    sub ax, dx
    mov [ftop], ax

    call walk_init
.e:
    call next_valid             ; DI = entry
    jc near .end
    mov ax, [nvis]
    dec ax
    mov [fk], ax
    cmp ax, [ftop]
    jb .e
    mov bx, [ftop]
    add bx, [frows]
    cmp ax, bx
    jae near .end
    sub ax, [ftop]
    imul ax, ax, ROW_H
    add ax, [wy]
    add ax, ROW0
    mov [fy], ax

    mov si, [cur_win]
    mov ax, [fk]
    cmp ax, [si+W_SEL]
    jne .plain
    mov al, 9                   ; highlight
    mov bx, [wx]
    add bx, 2
    mov cx, [fy]
    dec cx
    mov dx, [ww]
    sub dx, 4
    mov si, ROW_H
    call fill_rect
    mov byte [fcol], 15
    jmp .txt
.plain:
    mov byte [fcol], 0
.txt:
    call fmt_name
    mov si, namebuf
    mov bx, [wx]
    add bx, 4
    mov cx, [fy]
    mov dl, [fcol]
    call draw_str

    mov ax, [di+28]
    call num_str
    mov bx, [wx]
    add bx, 80
    mov cx, [fy]
    mov dl, [fcol]
    call draw_str
    jmp .e
.end:
    ret

c_clock:
    mov ah, 0x02
    int 0x1A
    mov di, tbuf
    mov al, ch
    call put2
    mov byte [di], ':'
    inc di
    mov al, cl
    call put2
    mov byte [di], ':'
    inc di
    mov al, dh
    call put2
    mov byte [di], 0
    mov si, tbuf
    mov bx, [wx]
    add bx, 8
    mov cx, [wy]
    add cx, CONT_Y
    mov dl, 0
    call draw_str

    mov ah, 0x04
    int 0x1A
    mov di, dbuf
    mov al, ch
    call put2
    mov al, cl
    call put2
    mov byte [di], '-'
    inc di
    mov al, dh
    call put2
    mov byte [di], '-'
    inc di
    mov al, dl
    call put2
    mov byte [di], 0
    mov si, dbuf
    mov bx, [wx]
    add bx, 8
    mov cx, [wy]
    add cx, CONT_Y+10
    mov dl, 0
    call draw_str
    ret

c_tasks:
    mov si, s_win
    mov bx, [wx]
    add bx, 4
    mov cx, [wy]
    add cx, CONT_Y
    mov dl, 0
    call draw_str
    mov si, s_ticks
    mov bx, [wx]
    add bx, 70
    mov cx, [wy]
    add cx, CONT_Y
    mov dl, 0
    call draw_str

    mov word [tk_i], 0
.l:
    mov ax, [tk_i]
    cmp ax, MAXWIN
    jae near .d
    shl ax, WSHIFT
    add ax, wins
    mov [tsp], ax
    mov si, ax
    cmp byte [si+W_USED], 0
    je near .n
    mov ax, [tk_i]
    imul ax, ax, ROW_H
    add ax, [wy]
    add ax, ROW0
    mov [tyy], ax
    mov si, [tsp]
    call win_title
    mov bx, [wx]
    add bx, 4
    mov cx, [tyy]
    mov dl, 0
    call draw_str
    mov si, [tsp]
    mov ax, [si+W_TICK]
    call num_str
    mov bx, [wx]
    add bx, 70
    mov cx, [tyy]
    mov dl, 0
    call draw_str
.n:
    inc word [tk_i]
    jmp .l
.d:
    ret

c_set:
    mov word [tk_i], 0
.l:
    cmp word [tk_i], 4
    jae near .hint
    mov ax, [tk_i]
    imul ax, ax, 10
    add ax, [wy]
    add ax, CONT_Y
    mov [tyy], ax
    mov si, [cur_win]
    mov ax, [tk_i]
    cmp ax, [si+W_SEL]
    jne .plain
    mov al, 9
    mov bx, [wx]
    add bx, 2
    mov cx, [tyy]
    dec cx
    mov dx, [ww]
    sub dx, 4
    mov si, 10
    call fill_rect
    mov byte [fcol], 15
    jmp .t
.plain:
    mov byte [fcol], 0
.t:
    mov bx, [tk_i]
    shl bx, 1
    mov si, [set_labels+bx]
    mov bx, [wx]
    add bx, 6
    mov cx, [tyy]
    mov dl, [fcol]
    call draw_str
    mov bx, [tk_i]
    mov al, [cfg+bx]
    mov bx, [wx]
    add bx, 70
    mov cx, [tyy]
    mov dx, 24
    mov si, 8
    call fill_rect
    mov bx, [tk_i]
    movzx ax, byte [cfg+bx]
    call num_str
    mov bx, [wx]
    add bx, 100
    mov cx, [tyy]
    mov dl, [fcol]
    call draw_str
    inc word [tk_i]
    jmp .l
.hint:
    mov si, s_set1
    mov bx, [wx]
    add bx, 4
    mov cx, [wy]
    add cx, [wh]
    sub cx, 19
    mov dl, 0
    call draw_str
    mov si, s_set2
    mov bx, [wx]
    add bx, 4
    mov cx, [wy]
    add cx, [wh]
    sub cx, 10
    mov dl, 0
    call draw_str
    ret

c_app:
    mov si, [cur_win]
    mov ax, 3                   ; MSG_DRAW
    call call_app
    ret

; ---- Notes --------------------------------------------------
c_note:
    mov si, [cur_win]
    call note_geom
    mov ax, [wx]
    add ax, 3
    mov [tx0], ax
    mov ax, [wy]
    add ax, TITLE_H+2
    mov [ty0], ax

    cmp word [fend], FBUF
    jne .have
    mov si, s_empty
    mov bx, [tx0]
    mov cx, [ty0]
    mov dl, 8
    call draw_str
    jmp .cursor
.have:
    mov si, [cur_win]
    mov ax, [si+W_SEL]
    mov [tmp_line], ax
    mov ax, [si+W_XOFF]
    mov [note_xo], ax
    mov si, FBUF
.skip:                          ; skip the lines above the view
    cmp word [tmp_line], 0
    je .rows
    cmp si, [fend]
    jae .rows
    lodsb
    cmp al, 10
    jne .skip
    dec word [tmp_line]
    jmp .skip
.rows:
    mov word [row_n], 0
.row:
    mov ax, [row_n]
    cmp ax, [nvr]
    jae near .cursor
    imul ax, ax, ROW_H
    add ax, [ty0]
    mov cx, ax                  ; CX = row y
    mov bx, [tx0]
    mov dl, 0
    mov ax, [note_xo]           ; skip the scrolled-off columns
    mov [n_cnt], ax
.A:
    cmp word [n_cnt], 0
    je .B0
    cmp si, [fend]
    jae .C
    cmp byte [si], 10
    je .C
    inc si
    dec word [n_cnt]
    jmp .A
.B0:
    mov ax, [nvc]
    mov [n_cnt], ax
.B:
    cmp word [n_cnt], 0
    je .C
    cmp si, [fend]
    jae .C
    mov al, [si]
    cmp al, 10
    je .C
    inc si
    call draw_char
    add bx, CW
    dec word [n_cnt]
    jmp .B
.C:                             ; move to the start of the next line
    cmp si, [fend]
    jae .nx
    lodsb
    cmp al, 10
    jne .C
.nx:
    inc word [row_n]
    jmp .row
.cursor:
    cmp byte [note_mode], 0
    jne .done
    call cur_pos                ; BX = line, AX = column
    mov si, [cur_win]
    sub bx, [si+W_SEL]
    jb .done
    cmp bx, [nvr]
    jae .done
    sub ax, [si+W_XOFF]
    jb .done
    cmp ax, [nvc]
    jae .done
    imul ax, ax, CW
    add ax, [tx0]
    imul bx, bx, ROW_H
    add bx, [ty0]
    mov cx, bx
    mov bx, ax
    mov dx, 2
    mov si, 8
    mov al, 4
    call fill_rect
.done:
    ret

; build_status: -> SI = status line text
build_status:
    cmp byte [note_mode], 1
    je .prompt
    cmp byte [note_name], 0
    jne .nm
    mov si, s_noname
    call app_str
    jmp .m
.nm:
    mov si, note_name
    call app_name11
.m:
    cmp byte [note_mod], 0
    je .p
    mov byte [di], '*'
    inc di
.p:
    mov si, s_ln
    call app_str
    call cur_pos
    push ax
    mov ax, bx
    inc ax
    call num_str
    call app_str
    mov si, s_col
    call app_str
    pop ax
    inc ax
    call num_str
    call app_str
    mov si, s_keys
    call app_str
    jmp .e
.prompt:
    mov si, s_saveas
    call app_str
    mov si, nin_buf
    call app_str
    mov byte [di], '_'
    inc di
.e:
    mov byte [di], 0
    ret

app_str:                        ; append asciiz SI to [DI]
.l:
    mov al, [si]
    test al, al
    jz .d
    mov [di], al
    inc si
    inc di
    jmp .l
.d:
    ret

app_name11:                     ; append "NAME.EXT" from 11-byte SI
    mov bx, si
    xor si, si
.a:
    cmp si, 8
    jae .e
    mov al, [bx+si]
    cmp al, ' '
    je .e
    mov [di], al
    inc di
    inc si
    jmp .a
.e:
    cmp byte [bx+8], ' '
    je .d
    mov byte [di], '.'
    inc di
    xor si, si
.x:
    cmp si, 3
    jae .d
    mov al, [bx+si+8]
    cmp al, ' '
    je .d
    mov [di], al
    inc di
    inc si
    jmp .x
.d:
    ret

; ============================================================
;  Text editor (Notes)
; ============================================================
note_reset:
    mov word [fend], FBUF
    mov word [note_cur], FBUF
    mov byte [note_mod], 0
    mov byte [note_mode], 0
    mov byte [note_name], 0
    ret

; note_geom: SI = Notes window -> [nvr] rows, [nvc] columns
note_geom:
    mov ax, [si+W_H]
    sub ax, TITLE_H+3
    jns .a
    xor ax, ax
.a:
    xor dx, dx
    mov cx, ROW_H
    div cx
    test ax, ax
    jnz .b
    inc ax
.b:
    mov [nvr], ax
    mov ax, [si+W_W]
    sub ax, 6
    jns .c
    xor ax, ax
.c:
    xor dx, dx
    mov cx, CW
    div cx
    test ax, ax
    jnz .d
    inc ax
.d:
    mov [nvc], ax
    ret

; cur_pos: -> BX = cursor line, AX = cursor column
cur_pos:
    xor bx, bx
    mov di, FBUF
    mov dx, FBUF
.l:
    cmp di, [note_cur]
    jae .d
    cmp byte [di], 10
    jne .n
    inc bx
    mov dx, di
    inc dx
.n:
    inc di
    jmp .l
.d:
    mov ax, [note_cur]
    sub ax, dx
    ret

; note_scroll: SI = Notes window; keep the cursor in view
note_scroll:
    call note_geom
    call cur_pos
    mov cx, [si+W_SEL]
    cmp bx, cx
    jae .v1
    mov [si+W_SEL], bx
    jmp .h
.v1:
    mov cx, [si+W_SEL]
    add cx, [nvr]
    cmp bx, cx
    jb .h
    mov cx, bx
    sub cx, [nvr]
    inc cx
    mov [si+W_SEL], cx
.h:
    mov cx, [si+W_XOFF]
    cmp ax, cx
    jae .h1
    mov [si+W_XOFF], ax
    ret
.h1:
    add cx, [nvc]
    cmp ax, cx
    jb .r
    mov cx, ax
    sub cx, [nvc]
    inc cx
    mov [si+W_XOFF], cx
.r:
    ret

ln_start:                       ; SI -> start of its line
.l:
    cmp si, FBUF
    jbe .d
    cmp byte [si-1], 10
    je .d
    dec si
    jmp .l
.d:
    ret

ln_end:                         ; SI -> the LF ending its line (or fend)
.l:
    cmp si, [fend]
    jae .d
    cmp byte [si], 10
    je .d
    inc si
    jmp .l
.d:
    ret

note_up:
    mov si, [note_cur]
    call ln_start
    mov bx, [note_cur]
    sub bx, si                  ; BX = column
    cmp si, FBUF
    jbe .r
    dec si
    mov di, si                  ; DI = LF of previous line
    call ln_start
    mov cx, di
    sub cx, si                  ; previous line length
    cmp bx, cx
    jbe .ok
    mov bx, cx
.ok:
    add si, bx
    mov [note_cur], si
.r:
    ret

note_down:
    mov si, [note_cur]
    call ln_start
    mov bx, [note_cur]
    sub bx, si                  ; BX = column
    mov si, [note_cur]
    call ln_end
    cmp si, [fend]
    jae .r
    inc si
    mov di, si                  ; start of next line
    call ln_end
    mov cx, si
    sub cx, di
    cmp bx, cx
    jbe .ok
    mov bx, cx
.ok:
    add di, bx
    mov [note_cur], di
.r:
    ret

note_home:
    mov si, [note_cur]
    call ln_start
    mov [note_cur], si
    ret

note_end:
    mov si, [note_cur]
    call ln_end
    mov [note_cur], si
    ret

note_ins:                       ; AL = character
    cmp word [fend], FBUF+FMAX-2
    jae .full
    push es
    push ax
    mov ax, cs
    mov es, ax
    mov cx, [fend]
    sub cx, [note_cur]
    jz .nomove
    mov si, [fend]
    dec si
    mov di, [fend]
    std
    rep movsb
    cld
.nomove:
    pop ax
    mov di, [note_cur]
    mov [di], al
    inc word [note_cur]
    inc word [fend]
    mov byte [note_mod], 1
    pop es
    ret
.full:
    mov word [msgp], s_full
    ret

note_del:                       ; delete the character at the cursor
    mov ax, [note_cur]
    cmp ax, [fend]
    jae .r
    push es
    mov ax, cs
    mov es, ax
    mov di, [note_cur]
    mov si, di
    inc si
    mov cx, [fend]
    sub cx, si
    cld
    rep movsb
    dec word [fend]
    mov byte [note_mod], 1
    pop es
.r:
    ret

note_key:                       ; AH = scan, AL = ascii, SI = Notes window
    mov si, [focus]
    call note_geom
    mov ax, [last_key]
    cmp byte [note_mode], 0
    jne near note_prompt_key
    cmp al, 0x13                ; Ctrl+S
    je near note_save
    cmp al, 0x0E                ; Ctrl+N
    jne .nn
    cmp ah, 0x31
    je near note_new
.nn:
    cmp ah, 0x4B
    jne .a1
    cmp word [note_cur], FBUF
    jbe .done
    dec word [note_cur]
    jmp .done
.a1:
    cmp ah, 0x4D
    jne .a2
    mov bx, [note_cur]
    cmp bx, [fend]
    jae .done
    inc word [note_cur]
    jmp .done
.a2:
    cmp ah, 0x48
    jne .a3
    call note_up
    jmp .done
.a3:
    cmp ah, 0x50
    jne .a4
    call note_down
    jmp .done
.a4:
    cmp ah, 0x47
    jne .a5
    call note_home
    jmp .done
.a5:
    cmp ah, 0x4F
    jne .a6
    call note_end
    jmp .done
.a6:
    cmp ah, 0x49
    jne .a7
    mov bx, [nvr]
    mov [pg_cnt], bx
.pu:
    call note_up
    dec word [pg_cnt]
    jnz .pu
    jmp .done
.a7:
    cmp ah, 0x51
    jne .a8
    mov bx, [nvr]
    mov [pg_cnt], bx
.pd:
    call note_down
    dec word [pg_cnt]
    jnz .pd
    jmp .done
.a8:
    cmp ah, 0x53
    jne .a9
    call note_del
    jmp .done
.a9:
    cmp ah, 0x0E
    jne .a10
    cmp word [note_cur], FBUF
    jbe .done
    dec word [note_cur]
    call note_del
    jmp .done
.a10:
    cmp ah, 0x1C
    jne .a11
    mov al, 10
    call note_ins
    jmp .done
.a11:
    cmp ah, 0x47
    jb .do_ins
    cmp ah, 0x53
    ja .do_ins
    jmp .done
.do_ins:
    cmp al, 32
    jb .done
    cmp al, 126
    ja .done
    call note_ins
.done:
    mov si, [focus]
    call note_scroll
    ret

note_new:                       ; Ctrl+N
    cmp byte [note_mod], 0
    jne .un
    call note_reset
    mov si, [focus]
    mov word [si+W_SEL], 0
    mov word [si+W_XOFF], 0
    ret
.un:
    mov word [msgp], s_unsaved
    ret

note_save:                      ; Ctrl+S
    cmp byte [note_name], 0
    jne do_save_note
    mov byte [note_mode], 1     ; no name yet: ask for one
    mov byte [nin_len], 0
    mov byte [nin_buf], 0
    ret

do_save_note:
    mov si, note_name
    mov di, FBUF
    mov cx, [fend]
    sub cx, FBUF
    call fs_write
    jc .r
    mov byte [note_mod], 0
    mov word [msgp], s_saved
.r:
    ret

note_prompt_key:                ; typing the file name
    cmp ah, 0x1C
    je .ok
    cmp ah, 0x0E
    je .bs
    cmp al, 32
    jb .r
    cmp al, 126
    ja .r
    cmp al, 'a'
    jb .u
    cmp al, 'z'
    ja .u
    sub al, 32
.u:
    cmp al, '.'
    je .add
    cmp al, '_'
    je .add
    cmp al, '-'
    je .add
    cmp al, '0'
    jb .r
    cmp al, '9'
    jbe .add
    cmp al, 'A'
    jb .r
    cmp al, 'Z'
    ja .r
.add:
    movzx bx, byte [nin_len]
    cmp bx, 12
    jae .r
    mov [nin_buf+bx], al
    inc bx
    mov byte [nin_buf+bx], 0
    mov [nin_len], bl
    ret
.bs:
    cmp byte [nin_len], 0
    je .r
    dec byte [nin_len]
    movzx bx, byte [nin_len]
    mov byte [nin_buf+bx], 0
    ret
.ok:
    call parse_name
    jc .r
    mov byte [note_mode], 0
    jmp do_save_note
.r:
    ret

; parse_name: nin_buf ("NAME.EXT") -> note_name (11 bytes), CF=1 if empty
parse_name:
    mov bx, note_name
    mov cx, 11
.f:
    mov byte [bx], ' '
    inc bx
    loop .f
    mov si, nin_buf
    mov bx, note_name
    xor cx, cx
.b:
    mov al, [si]
    test al, al
    jz .done
    inc si
    cmp al, '.'
    je .ext
    cmp cx, 8
    jae .b
    mov [bx], al
    inc bx
    inc cx
    jmp .b
.ext:
    mov bx, note_name+8
    xor cx, cx
.e:
    mov al, [si]
    test al, al
    jz .done
    inc si
    cmp al, '.'
    je .e
    cmp cx, 3
    jae .e
    mov [bx], al
    inc bx
    inc cx
    jmp .e
.done:
    cmp byte [note_name], ' '
    je .bad
    clc
    ret
.bad:
    mov byte [note_name], 0
    stc
    ret

; strip_cr: remove CR bytes from the loaded text
strip_cr:
    mov si, FBUF
    mov di, FBUF
.l:
    cmp si, [fend]
    jae .d
    mov al, [si]
    inc si
    cmp al, 13
    je .l
    mov [di], al
    inc di
    jmp .l
.d:
    mov [fend], di
    ret

; ============================================================
;  Text and number helpers
; ============================================================
; draw_char: AL=char, BX=x, CX=y, DL=color. Preserves all regs.
; 5x7 glyphs, 6x8 cell, ASCII 32..126.
draw_char:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov si, bx
    add si, 5
    cmp si, [clip_r]
    ja .skip
    mov si, cx
    add si, 7
    cmp si, [clip_b]
    ja .skip
    cmp al, 32
    jb .skip
    cmp al, 126
    ja .skip
    sub al, 32
    xor ah, ah
    mov si, ax
    shl si, 2
    add si, ax                  ; SI = index * 5
    add si, font5x7
    mov di, cx
    imul di, di, 320
    add di, bx
    mov bp, 5
.col:
    mov al, [si]
    inc si
    push di
    mov ah, 7
.bit:
    test al, 1
    jz .np
    mov [es:di], dl
.np:
    shr al, 1
    add di, 320
    dec ah
    jnz .bit
    pop di
    inc di
    dec bp
    jnz .col
.skip:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; draw_str: SI=asciiz, BX=x, CX=y, DL=color
draw_str:
.l:
    lodsb
    test al, al
    jz .d
    call draw_char
    add bx, CW
    jmp .l
.d:
    ret

; fill_rect: BX=x, CX=y, DX=w, SI=h, AL=color. Preserves all regs.
fill_rect:
    test dx, dx
    jz .z
    test si, si
    jnz .go
.z:
    ret
.go:
    pusha
    mov di, cx
    imul di, di, 320
    add di, bx
    mov bx, dx
    mov cx, si
.r:
    push cx
    mov cx, bx
    rep stosb
    pop cx
    add di, 320
    sub di, bx
    loop .r
    popa
    ret

put2:                           ; AL = BCD byte -> two digits at [DI]
    mov ah, al
    shr al, 4
    add al, '0'
    mov [di], al
    mov al, ah
    and al, 0x0F
    add al, '0'
    mov [di+1], al
    add di, 2
    ret

bcd2bin:                        ; AL BCD -> AL binary
    push bx
    mov bl, al
    and bl, 0x0F
    shr al, 4
    mov bh, 10
    mul bh
    add al, bl
    pop bx
    ret

num_str:                        ; AX unsigned -> SI = decimal asciiz
    push ax
    push bx
    push dx
    push di
    mov di, numbuf+7
    mov byte [di], 0
    mov bx, 10
.l:
    xor dx, dx
    div bx
    dec di
    add dl, '0'
    mov [di], dl
    test ax, ax
    jnz .l
    mov si, di
    pop di
    pop dx
    pop bx
    pop ax
    ret

fmt_name:                       ; DI = FAT entry -> namebuf "NAME.EXT"
    push si
    push bx
    push cx
    push ax
    mov si, di
    mov bx, namebuf
    mov cx, 8
.a:
    mov al, [si]
    cmp al, ' '
    je .b
    mov [bx], al
    inc si
    inc bx
    loop .a
.b:
    mov si, di
    add si, 8
    cmp byte [si], ' '
    je .z
    mov byte [bx], '.'
    inc bx
    mov cx, 3
.c:
    mov al, [si]
    cmp al, ' '
    je .z
    mov [bx], al
    inc si
    inc bx
    loop .c
.z:
    mov byte [bx], 0
    pop ax
    pop cx
    pop bx
    pop si
    ret

; ============================================================
;  Memory placement helpers
; ============================================================
choose_bb:                      ; back buffer must not overlap the GUI segment
    mov ax, cs
    mov si, bb_cand
.l:
    mov bx, [si]
    test bx, bx
    jz .none
    add si, 2
    mov dx, bx
    sub dx, ax
    jns .p
    neg dx
.p:
    cmp dx, 0x1000
    jb .l
    mov [bbseg], bx
    ret
.none:
    mov word [bbseg], VIDEO
    ret

choose_bounce:                  ; keep the sector buffer inside one 64 KB page
    mov ax, cs
    shl ax, 4
    mov bx, BOUNCE0
    mov cx, 3
.l:
    mov dx, ax
    add dx, bx
    cmp dx, 0xFE01
    jb .ok
    add bx, 0x200
    loop .l
.ok:
    mov [bounce], bx
    ret

set_diskmsg:                    ; "Disk error 0xNN"
    mov al, [diskerr]
    mov ah, al
    shr al, 4
    call hexd
    mov [dmsg+13], al
    mov al, ah
    call hexd
    mov [dmsg+14], al
    mov word [msgp], dmsg
    ret

hexd:
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jbe .r
    add al, 7
.r:
    ret

; ============================================================
;  FAT12
; ============================================================
mount:
    mov byte [diskerr], 0
    mov byte [can_write], 0
    mov word [spt], 18
    mov word [heads], 2
    xor ax, ax
    mov bx, SECBUF
    call read_sector
    cmp byte [diskerr], 0
    jne near .err

    movzx ax, byte [SECBUF+13]
    test ax, ax
    jnz .a1
    inc ax
.a1:
    mov [spc], ax
    mov ax, [SECBUF+24]
    test ax, ax
    jz .a2
    mov [spt], ax
.a2:
    mov ax, [SECBUF+26]
    test ax, ax
    jz .a3
    mov [heads], ax
.a3:
    mov ax, [SECBUF+14]
    mov [rsvd], ax
    movzx ax, byte [SECBUF+16]
    mov [nfats], ax
    mov ax, [SECBUF+22]
    mov [spf], ax
    mov ax, [SECBUF+19]
    mov [totsec], ax
    mov ax, [nfats]
    mul word [spf]
    add ax, [rsvd]
    mov [root_lba], ax
    mov cx, [SECBUF+17]
    shr cx, 4
    cmp cx, 14
    jbe .a4
    mov cx, 14
.a4:
    mov [root_secs], cx
    add ax, cx
    mov [data_lba], ax

    mov ax, [totsec]            ; highest cluster number
    sub ax, [data_lba]
    jbe .a6
    xor dx, dx
    div word [spc]
    inc ax
    cmp ax, 4084
    jbe .a5
    mov ax, 4084
.a5:
    mov [maxcl], ax
.a6:
    mov ax, [rsvd]
    mov cx, [spf]
    cmp cx, 12
    jbe .a7
    mov cx, 12
.a7:
    mov bx, FAT_BUF
    call read_run
    mov ax, [root_lba]
    mov cx, [root_secs]
    mov bx, ROOT_BUF
    call read_run
    cmp byte [diskerr], 0
    jne near .err
    cmp word [spf], 12
    ja .r
    cmp word [maxcl], 2
    jb .r
    cmp word [nfats], 0
    je .r
    mov byte [can_write], 1
.r:
    ret
.err:
    call set_diskmsg
    ret

reload_caches:                  ; re-read FAT and root dir from disk
    mov ax, [rsvd]
    mov cx, [spf]
    mov bx, FAT_BUF
    call read_run
    mov ax, [root_lba]
    mov cx, [root_secs]
    mov bx, ROOT_BUF
    call read_run
    ret

read_run:                       ; AX = LBA, CX = count, BX = dest offset
.l:
    jcxz .d
    call read_sector
    inc ax
    add bx, 512
    dec cx
    jmp .l
.d:
    ret

; disk_read / disk_write: AX = LBA, data in [bounce]. CF=1 on error.
; The BIOS error code stays in [diskerr]. Preserves all registers.
disk_read:
    mov byte [dio_op], 2
    jmp disk_io
disk_write:
    mov byte [dio_op], 3
disk_io:
    pusha
    push es
    mov [rs_lba], ax
    mov ax, cs
    mov es, ax
    mov cx, 5
.try:
    push cx
    mov ax, [rs_lba]
    xor dx, dx
    div word [spt]
    inc dx
    mov cl, dl
    xor dx, dx
    div word [heads]
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah
    mov dl, [drive]
    mov bx, [bounce]
    mov ah, [dio_op]
    mov al, 1
    int 0x13
    pop cx
    jnc .ok
    mov [diskerr], ah
    push cx
    xor ax, ax
    mov dl, [drive]
    int 0x13
    pop cx
    loop .try
    pop es
    popa
    stc
    ret
.ok:
    pop es
    popa
    clc
    ret

read_sector:                    ; AX = LBA, BX = dest offset (GUI segment)
    pusha
    push es
    call disk_read
    jc .e
    mov ax, cs
    mov es, ax
    mov di, bx
    mov si, [bounce]
    mov cx, 256
    cld
    rep movsw
.e:
    pop es
    popa
    ret

copy_to_bounce:                 ; SI = source (advances by 512)
    push es
    push di
    push cx
    mov ax, cs
    mov es, ax
    mov di, [bounce]
    mov cx, 256
    cld
    rep movsw
    pop cx
    pop di
    pop es
    ret

fat_next:                       ; AX = cluster -> AX = FAT entry
    push bx
    push si
    mov bx, ax
    mov si, ax
    shr si, 1
    add si, bx
    mov ax, [si+FAT_BUF]
    test bx, 1
    jz .even
    shr ax, 4
    jmp .out
.even:
    and ax, 0x0FFF
.out:
    pop si
    pop bx
    ret

fat_set:                        ; AX = cluster, DX = 12-bit value
    push bx
    push si
    push cx
    push dx
    mov bx, ax
    mov si, ax
    shr si, 1
    add si, bx
    mov cx, [si+FAT_BUF]
    and dx, 0x0FFF
    test bx, 1
    jz .even
    and cx, 0x000F
    shl dx, 4
    or cx, dx
    jmp .st
.even:
    and cx, 0xF000
    or cx, dx
.st:
    mov [si+FAT_BUF], cx
    pop dx
    pop cx
    pop si
    pop bx
    ret

; load_chain: follow the chain from [lf_clu], copy up to [lf_size]
; bytes to [dseg]:[doff], never past offset [dlimit].
; [got] = bytes copied, CF=1 on disk error.
load_chain:
    push es
    mov byte [diskerr], 0
    mov word [got], 0
    mov ax, [lf_clu]
    mov [cur_clu], ax
.cl:
    mov ax, [cur_clu]
    cmp ax, 2
    jb near .fin
    cmp ax, 0xFF8
    jae near .fin
    mov ax, [got]
    cmp ax, [lf_size]
    jae near .fin
    mov ax, [cur_clu]
    sub ax, 2
    mov cx, [spc]
    mul cx
    add ax, [data_lba]
    mov [cur_lba], ax
    mov cx, [spc]
.sec:
    mov [sec_left], cx
    mov ax, [lf_size]
    sub ax, [got]
    jbe near .fin
    cmp ax, 512
    jbe .n
    mov ax, 512
.n:
    mov [chunk], ax
    mov bx, [doff]
    add bx, ax
    jc near .fin
    cmp bx, [dlimit]
    ja near .fin
    mov ax, [cur_lba]
    call disk_read
    jc near .err
    mov es, [dseg]
    mov di, [doff]
    mov si, [bounce]
    mov cx, [chunk]
    cld
    rep movsb
    mov ax, [chunk]
    add [doff], ax
    add [got], ax
    inc word [cur_lba]
    mov cx, [sec_left]
    loop .sec
    mov ax, [cur_clu]
    call fat_next
    mov [cur_clu], ax
    jmp .cl
.err:
    pop es
    stc
    ret
.fin:
    pop es
    clc
    ret

; load_file: [lf_clu], [lf_size] -> Notes buffer. CF=1 on error.
load_file:
    mov word [fend], FBUF
    mov ax, cs
    mov [dseg], ax
    mov word [doff], FBUF
    mov word [dlimit], FBUF+FMAX
    call load_chain
    jc .err
    mov ax, [got]
    add ax, FBUF
    mov [fend], ax
    clc
    ret
.err:
    call set_diskmsg
    stc
    ret

; ---- writing --------------------------------------------------
; find_name: SI = 11-byte name -> DI = entry, CF=1 if absent.
; [fw_free] = first free directory slot (or 0).
find_name:
    mov word [fw_free], 0
    mov [fn_name], si
    xor dx, dx
.l:
    cmp dx, 224
    jae near .nf
    mov ax, dx
    shl ax, 5
    add ax, ROOT_BUF
    mov di, ax
    mov al, [di]
    test al, al
    jz .end
    cmp al, 0xE5
    je .free
    mov al, [di+11]
    cmp al, 0x0F
    je .n
    test al, 0x08
    jnz .n
    mov si, [fn_name]
    xor bx, bx
.c:
    mov al, [di+bx]
    cmp al, [si+bx]
    jne .n
    inc bx
    cmp bx, 11
    jb .c
    clc
    ret
.free:
    cmp word [fw_free], 0
    jne .n
    mov [fw_free], di
    jmp .n
.end:
    cmp word [fw_free], 0
    jne .nf
    mov [fw_free], di
    jmp .nf
.n:
    inc dx
    jmp .l
.nf:
    stc
    ret

free_chain:                     ; AX = first cluster
    mov cx, 4100
.l:
    cmp ax, 2
    jb .d
    cmp ax, 0xFF8
    jae .d
    push ax
    call fat_next
    mov bx, ax
    pop ax
    xor dx, dx
    call fat_set
    mov ax, bx
    loop .l
.d:
    ret

; alloc_chain: [fw_need] clusters -> AX = first, CF=1 if disk full
alloc_chain:
    mov word [ac_first], 0
    mov word [ac_prev], 0
    mov cx, [fw_need]
    mov bx, 2
.next:
.s:
    cmp bx, [maxcl]
    ja .fail
    mov ax, bx
    call fat_next
    test ax, ax
    jz .got
    inc bx
    jmp .s
.got:
    mov ax, [ac_prev]
    test ax, ax
    jnz .link
    mov [ac_first], bx
    jmp .mark
.link:
    mov dx, bx
    call fat_set
.mark:
    mov ax, bx
    mov dx, 0xFFF
    call fat_set
    mov [ac_prev], bx
    inc bx
    loop .next
    mov ax, [ac_first]
    clc
    ret
.fail:
    stc
    ret

; fill_bounce: next chunk of the file into [bounce], zero padded
fill_bounce:
    push es
    mov ax, cs
    mov es, ax
    mov di, [bounce]
    xor ax, ax
    mov cx, 256
    cld
    rep stosw
    mov cx, [fc_left]
    cmp cx, 512
    jbe .c
    mov cx, 512
.c:
    mov si, [fc_ptr]
    mov di, [bounce]
    sub [fc_left], cx
    add [fc_ptr], cx
    rep movsb
    pop es
    ret

flush_fat:                      ; write every FAT copy. CF=1 on error
    mov word [ff_k], 0
.copy:
    mov ax, [ff_k]
    cmp ax, [nfats]
    jae .ok
    mul word [spf]
    add ax, [rsvd]
    mov [ff_lba], ax
    mov word [ff_i], 0
    mov si, FAT_BUF
.s:
    mov ax, [ff_i]
    cmp ax, [spf]
    jae .nc
    call copy_to_bounce
    mov ax, [ff_lba]
    call disk_write
    jc .err
    inc word [ff_lba]
    inc word [ff_i]
    jmp .s
.nc:
    inc word [ff_k]
    jmp .copy
.ok:
    clc
    ret
.err:
    stc
    ret

flush_root:                     ; write the root directory. CF=1 on error
    mov ax, [root_lba]
    mov [ff_lba], ax
    mov word [ff_i], 0
    mov si, ROOT_BUF
.s:
    mov ax, [ff_i]
    cmp ax, [root_secs]
    jae .ok
    call copy_to_bounce
    mov ax, [ff_lba]
    call disk_write
    jc .err
    inc word [ff_lba]
    inc word [ff_i]
    jmp .s
.ok:
    clc
    ret
.err:
    stc
    ret

get_fat_time:                   ; -> AX = FAT time, DX = FAT date
    push bx
    push cx
    mov word [ft_time], 0
    mov word [ft_date], 0x0021  ; 1980-01-01 if the RTC fails
    mov ah, 0x02
    int 0x1A
    jc .d
    mov [ft_h], ch
    mov [ft_m], cl
    mov [ft_s], dh
    mov al, [ft_h]
    call bcd2bin
    xor ah, ah
    shl ax, 11
    mov bx, ax
    mov al, [ft_m]
    call bcd2bin
    xor ah, ah
    shl ax, 5
    or bx, ax
    mov al, [ft_s]
    call bcd2bin
    xor ah, ah
    shr ax, 1
    or bx, ax
    mov [ft_time], bx
    mov ah, 0x04
    int 0x1A
    jc .d
    mov [ft_c], ch
    mov [ft_y], cl
    mov [ft_mo], dh
    mov [ft_d], dl
    mov al, [ft_y]
    call bcd2bin
    xor ah, ah
    mov bx, ax
    mov al, [ft_c]
    call bcd2bin
    xor ah, ah
    mov cx, 100
    mul cx
    add ax, bx
    sub ax, 1980
    jb .d
    cmp ax, 127
    ja .d
    shl ax, 9
    mov bx, ax
    mov al, [ft_mo]
    call bcd2bin
    xor ah, ah
    shl ax, 5
    or bx, ax
    mov al, [ft_d]
    call bcd2bin
    xor ah, ah
    or bx, ax
    mov [ft_date], bx
.d:
    mov ax, [ft_time]
    mov dx, [ft_date]
    pop cx
    pop bx
    ret

; fs_write: SI = 11-byte name, DI = data, CX = size.
; Creates or replaces a file in the root directory.
; CF=1 on error (a message is set).
fs_write:
    mov [fw_name], si
    mov [fw_data], di
    mov [fw_size], cx
    cmp byte [can_write], 0
    je near .nowrite
    call find_name
    jc .new
    test byte [di+11], 0x11     ; read-only or directory
    jnz near .ro
    mov [fw_ent], di
    mov ax, [di+26]
    call free_chain
    jmp .alloc
.new:
    mov di, [fw_free]
    test di, di
    jz near .dirfull
    mov [fw_ent], di
.alloc:
    mov word [fw_first], 0
    mov ax, [fw_size]
    test ax, ax
    jz .fill
    mov cx, [spc]
    shl cx, 9
    mov [cbytes], cx
    dec cx
    add ax, cx
    xor dx, dx
    div word [cbytes]
    mov [fw_need], ax
    call alloc_chain
    jc near .full
    mov [fw_first], ax
.fill:
    mov ax, [fw_first]
    mov [fc_clu], ax
    mov ax, [fw_data]
    mov [fc_ptr], ax
    mov ax, [fw_size]
    mov [fc_left], ax
.wc:
    mov ax, [fc_clu]
    cmp ax, 2
    jb .wdone
    cmp ax, 0xFF8
    jae .wdone
    sub ax, 2
    mov cx, [spc]
    mul cx
    add ax, [data_lba]
    mov [fc_lba], ax
    mov cx, [spc]
.ws:
    cmp word [fc_left], 0
    je .wdone
    mov [fc_sec], cx
    call fill_bounce
    mov ax, [fc_lba]
    call disk_write
    jc near .wfail
    inc word [fc_lba]
    mov cx, [fc_sec]
    loop .ws
    mov ax, [fc_clu]
    call fat_next
    mov [fc_clu], ax
    jmp .wc
.wdone:
    mov di, [fw_ent]            ; directory entry
    mov si, [fw_name]
    mov cx, 11
.cn:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    loop .cn
    mov di, [fw_ent]
    mov byte [di+11], 0x20
    mov bx, 12
.z:
    mov byte [di+bx], 0
    inc bx
    cmp bx, 22
    jb .z
    call get_fat_time
    mov di, [fw_ent]
    mov [di+22], ax
    mov [di+24], dx
    mov ax, [fw_first]
    mov [di+26], ax
    mov ax, [fw_size]
    mov [di+28], ax
    mov word [di+30], 0
    call flush_fat
    jc near .wfail
    call flush_root
    jc near .wfail
    mov byte [wrote], 1
    clc
    ret
.nowrite:
    mov word [msgp], s_nowrite
    stc
    ret
.ro:
    mov word [msgp], s_ro
    stc
    ret
.dirfull:
    mov word [msgp], s_dirfull
    stc
    ret
.full:
    call reload_caches
    mov word [msgp], s_diskfull
    stc
    ret
.wfail:
    call set_diskmsg
    call reload_caches
    stc
    ret

; ---- settings file --------------------------------------------
load_cfg:
    mov si, cfg_name
    call find_name
    jc .r
    mov ax, [di+26]
    mov [lf_clu], ax
    mov word [lf_size], 4
    mov ax, cs
    mov [dseg], ax
    mov word [doff], cfg_tmp
    mov word [dlimit], cfg_tmp+4
    call load_chain
    jc .r
    cmp word [got], 4
    jne .r
    mov ax, [cfg_tmp]
    mov [cfg], ax
    mov ax, [cfg_tmp+2]
    mov [cfg+2], ax
.r:
    ret

save_cfg:
    mov si, cfg_name
    mov di, cfg
    mov cx, 4
    call fs_write
    jc .r
    mov word [msgp], s_cfgsaved
.r:
    ret

; ============================================================
;  Directory walking
; ============================================================
walk_init:
    mov word [fe], 0
    mov word [nvis], 0
    ret

next_valid:                     ; DI = next valid entry, CF=1 at the end
.n:
    mov ax, [fe]
    cmp ax, 224
    jae .eof
    shl ax, 5
    add ax, ROOT_BUF
    mov di, ax
    inc word [fe]
    mov al, [di]
    test al, al
    jz .eof
    cmp al, 0xE5
    je .n
    mov al, [di+11]
    cmp al, 0x0F
    je .n
    test al, 0x08
    jnz .n
    inc word [nvis]
    clc
    ret
.eof:
    stc
    ret

find_entry:                     ; AX = index -> DI, CF=1 if absent
    mov [want], ax
    call walk_init
.f:
    call next_valid
    jc .nf
    mov ax, [nvis]
    dec ax
    cmp ax, [want]
    jne .f
    clc
    ret
.nf:
    stc
    ret

dir_count:                      ; -> AX = number of entries
    call walk_init
.c:
    call next_valid
    jnc .c
    mov ax, [nvis]
    ret

; Enter in Files: *.APP starts a program, other files open in Notes
open_sel:
    mov si, [focus]
    mov ax, [si+W_SEL]
    call find_entry
    jc near .r
    mov ax, [di+26]
    mov [lf_clu], ax
    mov ax, [di+28]
    mov dx, [di+30]
    cmp word [di+8], 'AP'
    jne .text
    cmp byte [di+10], 'P'
    jne .text
    jmp launch_app
.text:
    cmp byte [note_mod], 0
    je .go
    mov word [msgp], s_unsaved
    ret
.go:
    xor bx, bx                  ; remember the file name
.cp:
    mov cl, [di+bx]
    mov [tmp_name+bx], cl
    inc bx
    cmp bx, 11
    jb .cp
    test dx, dx
    jnz .cap
    cmp ax, FMAX
    jbe .ok
.cap:
    mov ax, FMAX
.ok:
    mov [lf_size], ax
    mov al, T_NOTE
    call open_win
    call note_reset
    call load_file
    jc .skip
    call strip_cr
    xor bx, bx
.nm:
    mov al, [tmp_name+bx]
    mov [note_name+bx], al
    inc bx
    cmp bx, 11
    jb .nm
.skip:
    mov si, [focus]
    test si, si
    jz .r
    mov word [si+W_SEL], 0
    mov word [si+W_XOFF], 0
.r:
    ret

; ============================================================
;  Starting GUI programs (*.APP)
; ============================================================
find_app_seg:                   ; -> AX = free segment, CF=1 if none
    mov bx, app_cand
.n:
    mov ax, [bx]
    test ax, ax
    jz .no
    add bx, 2
    mov dx, ax
    mov cx, cs
    sub dx, cx
    jns .p1
    neg dx
.p1:
    cmp dx, 0x1000
    jb .n
    mov dx, ax
    sub dx, [bbseg]
    jns .p2
    neg dx
.p2:
    cmp dx, 0x1000
    jb .n
    xor di, di
.w:
    cmp di, MAXWIN
    jae .ok
    mov si, di
    shl si, WSHIFT
    add si, wins
    cmp byte [si+W_USED], 0
    je .wn
    cmp byte [si+W_TYPE], T_APP
    jne .wn
    cmp [si+W_SEG], ax
    je .n
.wn:
    inc di
    jmp .w
.ok:
    clc
    ret
.no:
    stc
    ret

; launch_app: [lf_clu] = first cluster, AX:DX = file size
launch_app:
    test dx, dx
    jnz .big
    cmp ax, 0xF000
    jbe .szok
.big:
    mov ax, 0xF000
.szok:
    cmp ax, 40
    jb near .bad
    mov [lf_size], ax
    call find_free_win
    jc near .nowin
    mov [new_win], si
    call find_app_seg
    jc near .noseg
    mov [new_seg], ax
    mov [dseg], ax
    mov word [doff], 0
    mov word [dlimit], 0xFFFF
    call load_chain
    jc near .derr
    mov ax, [new_seg]
    mov es, ax
    cmp word [es:0], 'SG'
    jne near .bad
    cmp word [es:2], 'A1'
    jne near .bad

    mov ax, [es:4]
    cmp ax, 16
    jae .w1
    mov ax, 16
.w1:
    cmp ax, 300
    jbe .w2
    mov ax, 300
.w2:
    add ax, 2
    mov [new_w], ax
    mov ax, [es:6]
    cmp ax, 16
    jae .h1
    mov ax, 16
.h1:
    cmp ax, 170
    jbe .h2
    mov ax, 170
.h2:
    add ax, TITLE_H+2
    mov [new_h], ax

    mov bx, [new_win]
    sub bx, wins
    shr bx, WSHIFT
    mov [new_idx], bx
    imul bx, bx, 12
    add bx, wtitles
    xor si, si
.t:
    mov al, [es:si+8]
    mov [bx+si], al
    inc si
    cmp si, 11
    jb .t
    mov byte [bx+11], 0

    mov ax, [new_idx]
    imul ax, ax, 14
    add ax, 24
    mov dx, ax
    mov ax, [new_idx]
    imul ax, ax, 10
    add ax, 14
    mov bx, dx
    add bx, [new_w]
    cmp bx, 320
    jbe .xo
    mov dx, 320
    sub dx, [new_w]
.xo:
    mov bx, ax
    add bx, [new_h]
    cmp bx, TASKBAR_Y
    jbe .yo
    mov ax, TASKBAR_Y
    sub ax, [new_h]
.yo:
    mov si, [new_win]
    mov byte [si+W_USED], 1
    mov byte [si+W_TYPE], T_APP
    mov [si+W_X], dx
    mov [si+W_Y], ax
    mov ax, [new_w]
    mov [si+W_W], ax
    mov ax, [new_h]
    mov [si+W_H], ax
    mov word [si+W_SEL], 0
    mov word [si+W_TICK], 0
    mov word [si+W_XOFF], 0
    mov word [si+W_MAX], 0
    mov ax, [new_seg]
    mov [si+W_SEG], ax
    mov [focus], si
    xor ax, ax                  ; MSG_INIT
    call call_app
    mov byte [dirty], 1
    cmp byte [close_req], 0
    je .r
    mov byte [close_req], 0
    mov si, [focus]
    call kill_window
.r:
    ret
.nowin:
    mov word [msgp], s_nowin
    ret
.noseg:
    mov word [msgp], s_noseg
    ret
.bad:
    mov word [msgp], s_notapp
    ret
.derr:
    call set_diskmsg
    ret

; call_app: SI = window, AX = message, BX = key (BL ascii, BH scan).
; Result: [app_ret] = AL returned by the program (1 = redraw).
; Messages: 0 INIT, 1 TICK, 2 KEY, 3 DRAW, 4 CLOSE.
call_app:
    pusha
    push es
    push fs
    mov [app_msg], ax
    mov [app_key], bx
    mov ax, [si+W_X]
    inc ax
    mov [app_ox], ax
    mov ax, [si+W_Y]
    add ax, TITLE_H+1
    mov [app_oy], ax
    mov ax, [si+W_W]
    sub ax, 2
    mov [app_cw], ax
    mov ax, [si+W_H]
    sub ax, TITLE_H+2
    mov [app_ch], ax
    mov ax, [si+W_SEG]
    mov [app_far+2], ax
    mov byte [app_ret], 0
    mov byte [in_draw], 0
    cmp word [app_msg], 3
    jne .go
    mov byte [in_draw], 1
    mov ax, [app_ox]
    add ax, [app_cw]
    mov [clip_r], ax
    mov ax, [app_oy]
    add ax, [app_ch]
    mov [clip_b], ax
.go:
    mov ax, [app_msg]
    mov bx, [app_key]
    call far [app_far]
    mov [cs:app_ret], al
    mov ax, cs
    mov ds, ax
    cld
    xor ax, ax
    mov gs, ax
    mov byte [in_draw], 0
    pop fs
    pop es
    popa
    ret

; ============================================================
;  INT 60h  -  API for GUI programs   (AH = function)
;  Every register except AX and CF is preserved.
;   0 CLEAR  AL=color
;   1 FILL   AL=color BX=x CX=y DX=w SI=h
;   2 STR    DS:SI=asciiz BX=x CX=y DL=color
;   3 CHAR   AL=char BX=x CX=y DL=color
;   4 NUM    AL=color BX=x CX=y DX=value
;   5 RND    BX=n -> AX = 0..n-1
;   6 TICKS  -> AX = BIOS timer (18.2 Hz)
;   7 PIX    AL=color BX=x CX=y
;   9 LOAD   DS:SI=11-byte name, ES:DI=buffer, CX=max
;            -> AX=bytes, CF=1 on error
;  10 EXIT
;  11 SOUND  BX=divisor, 0 = off
; ============================================================
api_int:
    pusha
    push ds
    push es
    push fs
    mov [cs:api_ds], ds
    mov [cs:api_es], es
    mov [cs:api_ax], ax
    mov [cs:api_frame], sp
    mov ax, cs
    mov ds, ax
    mov ax, [bbseg]
    mov es, ax
    cld
    sti
    mov ax, [api_ax]
    movzx bp, ah
    cmp bp, API_N
    jae .bad
    shl bp, 1
    call word [cs:api_tab+bp]
    jmp .out
.bad:
    mov si, [api_frame]
    or word [si+26], 1
.out:
    pop fs
    pop es
    pop ds
    popa
    iret

api_bad:
    mov si, [api_frame]
    or word [si+26], 1
    ret

api_clear:
    cmp byte [in_draw], 0
    je .r
    mov bx, [app_ox]
    mov cx, [app_oy]
    mov dx, [app_cw]
    mov si, [app_ch]
    call fill_rect
.r:
    ret

api_fill:
    cmp byte [in_draw], 0
    je .r
    cmp bx, [app_cw]
    jae .r
    cmp cx, [app_ch]
    jae .r
    mov di, [app_cw]
    sub di, bx
    cmp dx, di
    jbe .w
    mov dx, di
.w:
    mov di, [app_ch]
    sub di, cx
    cmp si, di
    jbe .h
    mov si, di
.h:
    add bx, [app_ox]
    add cx, [app_oy]
    call fill_rect
.r:
    ret

api_str:
    cmp byte [in_draw], 0
    je .r
    cmp bx, [app_cw]
    jae .r
    cmp cx, [app_ch]
    jae .r
    mov fs, [api_ds]
    mov di, apibuf
    push cx
    mov cx, 60
.c:
    mov al, [fs:si]
    inc si
    mov [di], al
    inc di
    test al, al
    jz .e
    loop .c
    mov byte [di], 0
.e:
    pop cx
    mov si, apibuf
    add bx, [app_ox]
    add cx, [app_oy]
    call draw_str
.r:
    ret

api_char:
    cmp byte [in_draw], 0
    je .r
    cmp bx, [app_cw]
    jae .r
    cmp cx, [app_ch]
    jae .r
    add bx, [app_ox]
    add cx, [app_oy]
    call draw_char
.r:
    ret

api_num:
    cmp byte [in_draw], 0
    je .r
    cmp bx, [app_cw]
    jae .r
    cmp cx, [app_ch]
    jae .r
    mov [an_col], al
    mov ax, dx
    call num_str
    add bx, [app_ox]
    add cx, [app_oy]
    mov dl, [an_col]
    call draw_str
.r:
    ret

api_pix:
    cmp byte [in_draw], 0
    je .r
    cmp bx, [app_cw]
    jae .r
    cmp cx, [app_ch]
    jae .r
    mov dx, 1
    mov si, 1
    add bx, [app_ox]
    add cx, [app_oy]
    call fill_rect
.r:
    ret

api_rnd:
    mov ax, [seed]
    mov dx, 25173
    mul dx
    add ax, 13849
    mov [seed], ax
    shr ax, 4
    test bx, bx
    jz .raw
    xor dx, dx
    div bx
    mov ax, dx
.raw:
    mov si, [api_frame]
    mov [si+20], ax
    and word [si+26], 0xFFFE
    ret

api_ticks:
    push es
    xor ax, ax
    mov es, ax
    mov ax, [es:0x46C]
    pop es
    mov si, [api_frame]
    mov [si+20], ax
    and word [si+26], 0xFFFE
    ret

api_exit:
    mov byte [close_req], 1
    ret

api_snd:
    test bx, bx
    jz .off
    mov al, 0xB6
    out 0x43, al
    mov ax, bx
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 3
    out 0x61, al
    ret
.off:
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    ret

api_load:
    mov [al_di], di
    mov [al_cx], cx
    mov fs, [api_ds]
    mov di, namebuf2
    mov cx, 11
.c:
    mov al, [fs:si]
    mov [di], al
    inc si
    inc di
    loop .c
    mov si, namebuf2
    call find_name
    jc .nf
    mov ax, [di+26]
    mov [lf_clu], ax
    mov ax, [di+28]
    cmp word [di+30], 0
    jne .cap
    cmp ax, [al_cx]
    jbe .sz
.cap:
    mov ax, [al_cx]
.sz:
    mov [lf_size], ax
    mov ax, [api_es]
    mov [dseg], ax
    mov ax, [al_di]
    mov [doff], ax
    mov word [dlimit], 0xFFFF
    call load_chain
    jc .nf
    mov ax, [got]
    mov si, [api_frame]
    mov [si+20], ax
    and word [si+26], 0xFFFE
    ret
.nf:
    mov si, [api_frame]
    mov word [si+20], 0
    or word [si+26], 1
    ret

; ============================================================
;  PS/2 mouse (IRQ12 masked, polled through the 8042)
; ============================================================
kbc_wait:
    push cx
    mov cx, 0xFFFF
.l:
    in al, 0x64
    test al, 2
    jz .d
    loop .l
.d:
    pop cx
    ret

mouse_init:
    in al, 0xA1
    mov [oldmask], al
    or al, 0x10                 ; mask IRQ12 - the GUI polls the 8042 itself
    out 0xA1, al
    call kbc_wait
    mov al, 0xA8                ; enable the aux (mouse) device
    out 0x64, al
    call kbc_wait
    mov al, 0xD4                ; write to the mouse
    out 0x64, al
    call kbc_wait
    mov al, 0xF4                ; enable data reporting
    out 0x60, al
    mov cx, 0x3000
.w:
    in al, 0x64
    and al, 0x21
    cmp al, 0x21
    je .ack
    loop .w
    jmp .done
.ack:
    in al, 0x60
.done:
    mov word [mpi], 0
    ret

mouse_off:
    call kbc_wait
    mov al, 0xD4
    out 0x64, al
    call kbc_wait
    mov al, 0xF5                ; disable data reporting
    out 0x60, al
    mov cx, 0x2000
.w:
    in al, 0x64
    and al, 0x21
    cmp al, 0x21
    je .ack
    loop .w
    jmp .done
.ack:
    in al, 0x60
.done:
    mov al, [oldmask]
    out 0xA1, al                ; restore the PIC mask
    ret

poll_mouse:
.l:
    in al, 0x64
    and al, 0x21                ; output full + aux data
    cmp al, 0x21
    jne .done
    in al, 0x60
    mov bx, [mpi]
    test bx, bx
    jnz .store
    test al, 8                  ; bit 3 set only in the first byte
    jz .l
.store:
    mov [mpk+bx], al
    inc bx
    cmp bx, 3
    jb .save
    xor bx, bx
    call apply_packet
.save:
    mov [mpi], bx
    jmp .l
.done:
    ret

apply_packet:
    mov al, [mpk]
    and al, 7
    mov [mb], al                ; buttons: bit0 = left
    movsx cx, byte [mpk+1]      ; X movement
    movsx dx, byte [mpk+2]      ; Y movement (inverted)
    mov ax, [mx]
    add ax, cx
    jns .x1
    xor ax, ax
.x1:
    cmp ax, 319
    jbe .x2
    mov ax, 319
.x2:
    mov [mx], ax
    mov ax, [my]
    sub ax, dx
    jns .y1
    xor ax, ax
.y1:
    cmp ax, 199
    jbe .y2
    mov ax, 199
.y2:
    mov [my], ax
    mov byte [dirty], 1         ; cursor moved: repaint
    ret

; ---- buttons --------------------------------------------------
handle_mouse:
    mov al, [mb]
    mov ah, [pmb]
    mov [pmb], al
    test al, 1
    jnz .down
    mov word [dragging], 0xFFFF ; released: stop any drag
    ret
.down:
    test ah, 1
    jnz .held
    call hit_press              ; fresh press
    ret
.held:
    mov si, [dragging]
    cmp si, 0xFFFF
    je .r
    mov ax, [mx]                ; drag the window by its title bar
    sub ax, [dragdx]
    jge .x1
    xor ax, ax
.x1:
    mov dx, 320
    sub dx, [si+W_W]
    cmp ax, dx
    jle .x2
    mov ax, dx
.x2:
    mov [si+W_X], ax
    mov ax, [my]
    sub ax, [dragdy]
    jge .y1
    xor ax, ax
.y1:
    mov dx, TASKBAR_Y
    sub dx, [si+W_H]
    cmp ax, dx
    jle .y2
    mov ax, dx
.y2:
    mov [si+W_Y], ax
    call win_changed            ; keep a Notes view consistent
    mov byte [dirty], 1
.r:
    ret

hit_press:
    mov si, [focus]             ; the focused window is drawn on top
    test si, si
    jz .others
    call hit_window
    jc .done
.others:
    xor cx, cx
.ol:
    cmp cx, MAXWIN
    jae near .taskbar
    mov ax, cx
    shl ax, WSHIFT
    add ax, wins
    mov si, ax
    cmp byte [si+W_USED], 0
    je .on
    cmp si, [focus]
    je .on
    call hit_window
    jc .done
.on:
    inc cx
    jmp .ol
.taskbar:
    mov ax, [my]
    cmp ax, TASKBAR_Y
    jb .done
    mov ax, [mx]
    sub ax, 4                   ; taskbar buttons: x = 4 + slot*34, w = 33
    jl .done
    xor dx, dx
    mov cx, 34
    div cx                      ; AX = window slot
    cmp ax, MAXWIN
    jae .done
    shl ax, WSHIFT
    add ax, wins
    mov si, ax
    cmp byte [si+W_USED], 0
    je .done
    mov [focus], si
    mov byte [dirty], 1
.done:
    ret

; hit_window: SI = window record -> CF=1 if the click landed on it
hit_window:
    mov ax, [mx]
    sub ax, [si+W_X]
    jl .no
    cmp ax, [si+W_W]
    jae .no
    mov [hitx], ax
    mov ax, [my]
    sub ax, [si+W_Y]
    jl .no
    cmp ax, [si+W_H]
    jae .no
    mov [hity], ax
    mov [focus], si             ; any click focuses the window
    cmp word [hity], TITLE_H+1
    ja near .client
    mov ax, [hitx]              ; title bar: [x] box or drag
    mov dx, [si+W_W]
    sub dx, 10
    cmp ax, dx
    jae .close
    mov [dragging], si
    mov ax, [mx]
    sub ax, [si+W_X]
    mov [dragdx], ax
    mov ax, [my]
    sub ax, [si+W_Y]
    mov [dragdy], ax
    mov byte [dirty], 1
    stc
    ret
.close:
    call close_focus            ; honours the unsaved-text warning
    mov byte [dirty], 1
    stc
    ret
.client:
    mov byte [dirty], 1
    mov al, [si+W_TYPE]
    cmp al, T_FILES
    je .files
    cmp al, T_SET
    je .setup
    stc
    ret
.files:
    mov ax, [hity]              ; which list row was clicked?
    sub ax, ROW0
    jl .stc
    xor dx, dx
    mov cx, ROW_H
    div cx
    add ax, [ftop]              ; first visible row (kept fresh by c_files)
    mov bx, ax
    call dir_count
    cmp bx, ax
    jae .stc                    ; click below the last entry: ignore
    mov si, [focus]
    cmp bx, [si+W_SEL]
    jne .sel
    call open_sel               ; second click on a row opens it
    stc
    ret
.sel:
    mov [si+W_SEL], bx
    stc
    ret
.setup:
    mov ax, [hity]              ; which settings row was clicked?
    sub ax, CONT_Y
    jl .stc
    xor dx, dx
    mov cx, 10
    div cx
    cmp ax, 3
    ja .stc
    mov si, [focus]
    mov [si+W_SEL], ax
.stc:
    stc
    ret
.no:
    clc
    ret

draw_cursor:                    ; 8x12 arrow into the back buffer (ES)
    pusha
    mov si, cur
    xor dx, dx                  ; row
.row:
    xor cx, cx                  ; col
.col:
    lodsb
    test al, al
    jz .next
    cmp al, 2
    je .body
    xor ah, ah                  ; outline: black
    jmp .put
.body:
    mov ah, 15                  ; body: white
.put:
    mov bx, [mx]
    add bx, cx
    cmp bx, 319
    ja .next
    mov di, [my]
    add di, dx
    cmp di, 199
    ja .next
    mov al, ah
    imul di, di, 320
    add di, bx
    mov [es:di], al
.next:
    inc cx
    cmp cx, 8
    jb .col
    inc dx
    cmp dx, 12
    jb .row
    popa
    ret

; ============================================================
;  Tables
; ============================================================
api_tab:
    dw api_clear, api_fill, api_str, api_char, api_num, api_rnd
    dw api_ticks, api_pix, api_bad, api_load, api_exit, api_snd
content_tab:
    dw 0, c_files, c_clock, c_tasks, c_note, c_app, c_set
title_tab:
    dw 0, t_files, t_clock, t_tasks, t_note, 0, t_set
set_labels:
    dw l_wall, l_title, l_task, l_win
; window defaults per type: x, y, w, h   (8 bytes per type)
deftab:
    dw 0, 0, 0, 0
    dw 2, 10, 124, 100          ; Files
    dw 130, 10, 100, 34         ; Clock
    dw 130, 48, 124, 92         ; Tasks
    dw 8, 14, 304, 150          ; Notes
    dw 0, 0, 0, 0               ; (programs are placed by launch_app)
    dw 70, 30, 180, 76          ; Setup
bb_cand:
    dw 0x7000, 0x6000, 0x5000, 0x4000, 0x3000, 0
app_cand:
    dw 0x6000, 0x5000, 0x4000, 0x3000, 0

; ============================================================
;  Strings
; ============================================================
s_brand   db "SpheraOS GUI", 0
s_hint1   db "F1 Files F2 Clock F3 Tasks F4 Notes F8 Setup", 0
s_hint2   db "F5 max F6 move F7 size Tab focus F10 close Esc exit", 0
s_name    db "Name", 0
s_size    db "Size", 0
s_enter   db "Enter=open  .APP=run", 0
s_win     db "Window", 0
s_ticks   db "Ticks", 0
s_empty   db "(empty - type, or open a file in Files)", 0
s_nowin   db "No free window", 0
s_noseg   db "No memory for app", 0
s_notapp  db "Not a GUI app", 0
s_saved   db "Saved", 0
s_cfgsaved db "Settings saved", 0
s_unsaved db "Unsaved text: Ctrl+S first", 0
s_unsaved2 db "Unsaved! Esc again to quit", 0
s_unsaved3 db "Unsaved! F10 again to close", 0
s_full    db "Buffer full (8 KB)", 0
s_move    db "MOVE: arrows, Enter=done", 0
s_sizem   db "SIZE: arrows, Enter=done", 0
s_nowrite db "Disk is not writable here", 0
s_ro      db "File is read-only", 0
s_dirfull db "Directory full", 0
s_diskfull db "Disk full", 0
s_saveas  db "Save as: ", 0
s_noname  db "[new]", 0
s_ln      db "  Ln ", 0
s_col     db " Col ", 0
s_keys    db "  ^S save ^N new", 0
s_set1    db "Arrows, PgUp/PgDn = change", 0
s_set2    db "S / Enter = save settings", 0
l_wall    db "Wallpaper", 0
l_title   db "Title bar", 0
l_task    db "Taskbar", 0
l_win     db "Window", 0
t_files   db "Files", 0
t_clock   db "Clock", 0
t_tasks   db "Tasks", 0
t_note    db "Notes", 0
t_set     db "Setup", 0
dmsg      db "Disk error 0x??", 0
cfg_name  db "GUI     CFG"

; ============================================================
;  5x7 font, ASCII 32..126, 5 columns per glyph (bit 0 = top row)
; ============================================================
font5x7:
    db 0x00,0x00,0x00,0x00,0x00 ; space
    db 0x00,0x00,0x5F,0x00,0x00 ; !
    db 0x00,0x07,0x00,0x07,0x00 ; "
    db 0x14,0x7F,0x14,0x7F,0x14 ; #
    db 0x24,0x2A,0x7F,0x2A,0x12 ; $
    db 0x23,0x13,0x08,0x64,0x62 ; %
    db 0x36,0x49,0x55,0x22,0x50 ; &
    db 0x00,0x05,0x03,0x00,0x00 ; '
    db 0x00,0x1C,0x22,0x41,0x00 ; (
    db 0x00,0x41,0x22,0x1C,0x00 ; )
    db 0x14,0x08,0x3E,0x08,0x14 ; *
    db 0x08,0x08,0x3E,0x08,0x08 ; +
    db 0x00,0x50,0x30,0x00,0x00 ; ,
    db 0x08,0x08,0x08,0x08,0x08 ; -
    db 0x00,0x60,0x60,0x00,0x00 ; .
    db 0x20,0x10,0x08,0x04,0x02 ; /
    db 0x3E,0x51,0x49,0x45,0x3E ; 0
    db 0x00,0x42,0x7F,0x40,0x00 ; 1
    db 0x42,0x61,0x51,0x49,0x46 ; 2
    db 0x21,0x41,0x45,0x4B,0x31 ; 3
    db 0x18,0x14,0x12,0x7F,0x10 ; 4
    db 0x27,0x45,0x45,0x45,0x39 ; 5
    db 0x3C,0x4A,0x49,0x49,0x30 ; 6
    db 0x01,0x71,0x09,0x05,0x03 ; 7
    db 0x36,0x49,0x49,0x49,0x36 ; 8
    db 0x06,0x49,0x49,0x29,0x1E ; 9
    db 0x00,0x36,0x36,0x00,0x00 ; :
    db 0x00,0x56,0x36,0x00,0x00 ; ;
    db 0x08,0x14,0x22,0x41,0x00 ; <
    db 0x14,0x14,0x14,0x14,0x14 ; =
    db 0x00,0x41,0x22,0x14,0x08 ; >
    db 0x02,0x01,0x51,0x09,0x06 ; ?
    db 0x32,0x49,0x79,0x41,0x3E ; @
    db 0x7E,0x11,0x11,0x11,0x7E ; A
    db 0x7F,0x49,0x49,0x49,0x36 ; B
    db 0x3E,0x41,0x41,0x41,0x22 ; C
    db 0x7F,0x41,0x41,0x22,0x1C ; D
    db 0x7F,0x49,0x49,0x49,0x41 ; E
    db 0x7F,0x09,0x09,0x09,0x01 ; F
    db 0x3E,0x41,0x49,0x49,0x7A ; G
    db 0x7F,0x08,0x08,0x08,0x7F ; H
    db 0x00,0x41,0x7F,0x41,0x00 ; I
    db 0x20,0x40,0x41,0x3F,0x01 ; J
    db 0x7F,0x08,0x14,0x22,0x41 ; K
    db 0x7F,0x40,0x40,0x40,0x40 ; L
    db 0x7F,0x02,0x0C,0x02,0x7F ; M
    db 0x7F,0x04,0x08,0x10,0x7F ; N
    db 0x3E,0x41,0x41,0x41,0x3E ; O
    db 0x7F,0x09,0x09,0x09,0x06 ; P
    db 0x3E,0x41,0x51,0x21,0x5E ; Q
    db 0x7F,0x09,0x19,0x29,0x46 ; R
    db 0x46,0x49,0x49,0x49,0x31 ; S
    db 0x01,0x01,0x7F,0x01,0x01 ; T
    db 0x3F,0x40,0x40,0x40,0x3F ; U
    db 0x1F,0x20,0x40,0x20,0x1F ; V
    db 0x3F,0x40,0x38,0x40,0x3F ; W
    db 0x63,0x14,0x08,0x14,0x63 ; X
    db 0x07,0x08,0x70,0x08,0x07 ; Y
    db 0x61,0x51,0x49,0x45,0x43 ; Z
    db 0x00,0x7F,0x41,0x41,0x00 ; [
    db 0x02,0x04,0x08,0x10,0x20 ; backslash
    db 0x00,0x41,0x41,0x7F,0x00 ; ]
    db 0x04,0x02,0x01,0x02,0x04 ; ^
    db 0x40,0x40,0x40,0x40,0x40 ; _
    db 0x00,0x01,0x02,0x04,0x00 ; `
    db 0x20,0x54,0x54,0x54,0x78 ; a
    db 0x7F,0x48,0x44,0x44,0x38 ; b
    db 0x38,0x44,0x44,0x44,0x20 ; c
    db 0x38,0x44,0x44,0x48,0x7F ; d
    db 0x38,0x54,0x54,0x54,0x18 ; e
    db 0x08,0x7E,0x09,0x01,0x02 ; f
    db 0x0C,0x52,0x52,0x52,0x3E ; g
    db 0x7F,0x08,0x04,0x04,0x78 ; h
    db 0x00,0x44,0x7D,0x40,0x00 ; i
    db 0x20,0x40,0x44,0x3D,0x00 ; j
    db 0x7F,0x10,0x28,0x44,0x00 ; k
    db 0x00,0x41,0x7F,0x40,0x00 ; l
    db 0x7C,0x04,0x18,0x04,0x78 ; m
    db 0x7C,0x08,0x04,0x04,0x78 ; n
    db 0x38,0x44,0x44,0x44,0x38 ; o
    db 0x7C,0x14,0x14,0x14,0x08 ; p
    db 0x08,0x14,0x14,0x18,0x7C ; q
    db 0x7C,0x08,0x04,0x04,0x08 ; r
    db 0x48,0x54,0x54,0x54,0x20 ; s
    db 0x04,0x3F,0x44,0x40,0x20 ; t
    db 0x3C,0x40,0x40,0x20,0x7C ; u
    db 0x1C,0x20,0x40,0x20,0x1C ; v
    db 0x3C,0x40,0x30,0x40,0x3C ; w
    db 0x44,0x28,0x10,0x28,0x44 ; x
    db 0x0C,0x50,0x50,0x50,0x3C ; y
    db 0x44,0x64,0x54,0x4C,0x44 ; z
    db 0x00,0x08,0x36,0x41,0x00 ; {
    db 0x00,0x00,0x7F,0x00,0x00 ; |
    db 0x00,0x41,0x36,0x08,0x00 ; }
    db 0x10,0x08,0x08,0x10,0x08 ; ~

; ---- mouse pointer (8x12): 1 = black outline, 2 = white body ----
cur:
    db 1,0,0,0,0,0,0,0
    db 1,1,0,0,0,0,0,0
    db 1,2,1,0,0,0,0,0
    db 1,2,2,1,0,0,0,0
    db 1,2,2,2,1,0,0,0
    db 1,2,2,2,2,1,0,0
    db 1,2,2,2,2,2,1,0
    db 1,2,2,2,2,2,2,1
    db 1,2,2,2,1,1,1,1
    db 1,2,1,2,1,0,0,0
    db 1,1,0,1,2,1,0,0
    db 0,0,0,1,1,1,0,0

; ============================================================
;  Variables
; ============================================================
drive     db 0
dirty     db 1
last_sec  db 0xFF
diskerr   db 0
dio_op    db 2
in_draw   db 0
close_req db 0
app_ret   db 0
an_col    db 0
tbt       db 0
fcol      db 0
ow_t      db 0
wmode     db 0
note_mod  db 0
note_mode db 0
nin_len   db 0
quit_warn db 0
warn_prev db 0
wrote     db 0
can_write db 0
ft_h      db 0
ft_m      db 0
ft_s      db 0
ft_c      db 0
ft_y      db 0
ft_mo     db 0
ft_d      db 0
cfg       db 3, 1, 7, 7         ; wallpaper, title bar, taskbar, window body
cfg_tmp   db 0, 0, 0, 0
fontdummy db 0
bbseg     dw 0
bounce    dw BOUNCE0
old_ss    dw 0
old_sp    dw 0
old_v_off dw 0
old_v_seg dw 0
last_tick dw 0
last_key  dw 0
msgp      dw 0
seed      dw 1
wx        dw 0
wy        dw 0
ww        dw 0
wh        dw 0
wtype     dw 0
clip_r    dw 320
clip_b    dw 200
cur_win   dw 0
focus     dw 0
ti        dw 0
ti2       dw 0
tk_i      dw 0
ow_i      dw 0
tsp       dw 0
tyy       dw 0
tbx       dw 0
ftop      dw 0
frows     dw 1
fk        dw 0
fy        dw 0
fe        dw 0
nvis      dw 0
want      dw 0
tmp_line  dw 0
row_n     dw 0
n_cnt     dw 0
pg_cnt    dw 0
nvr       dw 1
nvc       dw 1
tx0       dw 0
ty0       dw 0
note_xo   dw 0
note_cur  dw FBUF
fend      dw FBUF
spc       dw 1
spt       dw 18
heads     dw 2
rsvd      dw 1
nfats     dw 2
spf       dw 9
totsec    dw 0
maxcl     dw 0
root_lba  dw 0
root_secs dw 14
data_lba  dw 0
rs_lba    dw 0
cur_clu   dw 0
cur_lba   dw 0
got       dw 0
sec_left  dw 0
chunk     dw 0
lf_clu    dw 0
lf_size   dw 0
dseg      dw 0
doff      dw 0
dlimit    dw 0
fn_name   dw 0
fw_name   dw 0
fw_data   dw 0
fw_size   dw 0
fw_ent    dw 0
fw_free   dw 0
fw_first  dw 0
fw_need   dw 0
cbytes    dw 512
ac_first  dw 0
ac_prev   dw 0
fc_clu    dw 0
fc_ptr    dw 0
fc_left   dw 0
fc_lba    dw 0
fc_sec    dw 0
ff_k      dw 0
ff_i      dw 0
ff_lba    dw 0
ft_time   dw 0
ft_date   dw 0
new_win   dw 0
new_seg   dw 0
new_w     dw 0
new_h     dw 0
new_idx   dw 0
app_msg   dw 0
app_key   dw 0
app_ox    dw 0
app_oy    dw 0
app_cw    dw 0
app_ch    dw 0
app_far   dw 0x20, 0            ; entry offset 20h, segment filled in
api_ds    dw 0
api_es    dw 0
api_ax    dw 0
api_frame dw 0
al_di     dw 0
al_cx     dw 0
wins      times MAXWIN*WSZ db 0
wtitles   times MAXWIN*12 db 0
note_name times 12 db 0
tmp_name  times 12 db 0
nin_buf   times 16 db 0
stbuf     times 96 db 0
tbuf      times 12 db 0
dbuf      times 12 db 0
namebuf   times 16 db 0
namebuf2  times 12 db 0
numbuf    times 8 db 0
apibuf    times 64 db 0
; ---- PS/2 mouse state ----
mx        dw 160
my        dw 100
mpi       dw 0
dragdx    dw 0
dragdy    dw 0
hitx      dw 0
hity      dw 0
dragging  dw 0xFFFF            ; window record being dragged, 0xFFFF = none
mb        db 0                  ; buttons (bit0 = left)
pmb       db 0                  ; previous buttons
oldmask   db 0
mpk       times 4 db 0          ; raw 3-byte packet + spare