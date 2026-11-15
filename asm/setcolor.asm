; ============================================================
;  setcolor.bin — патчит ядро в ОЗУ для поддержки цвета консоли
;  Каждый запуск циклит цвет: 07->0A->0B->0C->0E->0F->1E->4E->70->07
;
;  Build:  nasm -f bin setcolor.asm -o setcolor.bin
;  Run:    run setcolor.bin
; ============================================================
BITS 16
ORG 0

KSEG        equ 0x1000
COLOR_ADDR  equ 0xE100      ; свободный offset в KSEG (после BSS)
STUB_ADDR   equ 0xE000      ; сюда кладём стаб
SCAN_LIMIT  equ 0xA000      ; ищем только в коде, не в BSS

start:
    push ds
    push es
    push fs
    push gs

    ; --- найти PutC ---
    mov ax, KSEG
    mov es, ax
    xor di, di
    mov cx, SCAN_LIMIT
.scan_putc:
    push cx
    push di
    push cs
    pop ds
    mov si, putc_sig
    mov cx, putc_sig_len
    repe cmpsb
    pop di
    pop cx
    je .found_putc
    inc di
    loop .scan_putc
    jmp .done                   ; не нашли — тихо выходим

.found_putc:
    ; --- прочитать текущий цвет, взять следующий ---
    mov al, [es:di+4]           ; первый BB 07 00 → цвет в +4
    call next_color
    mov [es:COLOR_ADDR], al     ; сохранить
    ; пропатчить оба "mov bx, imm16" в PutC
    mov [es:di+4], al
    mov [es:di+13], al

    ; --- установить стаб в KSEG:STUB_ADDR ---
    push ds
    push si
    push di
    push cx
    push cs
    pop ds                      ; DS = CS = 0x8000 (наш сегмент)
    mov si, clear_stub
    mov di, STUB_ADDR
    mov cx, clear_stub_end - clear_stub
    rep movsb
    pop cx
    pop di
    pop si
    pop ds

    ; --- пропатчить все "mov ax,3; int 10h; ret" ---
    mov ax, KSEG
    mov es, ax
    xor di, di
    mov cx, SCAN_LIMIT
.scan_clear:
    push cx
    push di
    push cs
    pop ds
    mov si, clear_sig
    mov cx, clear_sig_len
    repe cmpsb
    pop di
    pop cx
    jne .next_clear
    ; совпало — заменяем на "call stub; ret; nop; nop"
    mov ax, STUB_ADDR
    sub ax, di
    sub ax, 3
    mov byte [es:di],   0xE8
    mov word [es:di+1], ax
    mov byte [es:di+3], 0xC3
    mov byte [es:di+4], 0x90
    mov byte [es:di+5], 0x90
.next_clear:
    inc di
    loop .scan_clear

    ; --- сразу закрасить экран новым цветом ---
    mov al, [es:COLOR_ADDR]
    mov bh, al
    mov ah, 0x06
    xor al, al
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    mov ah, 0x02
    xor bh, bh
    xor dx, dx
    int 0x10

.done:
    pop gs
    pop fs
    pop es
    pop ds
    retf

; ---- цикл цветов ----
next_color:
    cmp al, 0x07
    jne .a
    mov al, 0x0A
    ret
.a: cmp al, 0x0A
    jne .b
    mov al, 0x0B
    ret
.b: cmp al, 0x0B
    jne .c
    mov al, 0x0C
    ret
.c: cmp al, 0x0C
    jne .d
    mov al, 0x0E
    ret
.d: cmp al, 0x0E
    jne .e
    mov al, 0x0F
    ret
.e: cmp al, 0x0F
    jne .f
    mov al, 0x1E
    ret
.f: cmp al, 0x1E
    jne .g
    mov al, 0x4E
    ret
.g: cmp al, 0x4E
    jne .h
    mov al, 0x70
    ret
.h: mov al, 0x07
    ret

; ---- сигнатуры ----
putc_sig:
    db 0xB8, 0x0D, 0x0E, 0xBB  ; mov ax,0x0E0D ; BB (опкод следующего mov bx,imm)
putc_sig_len equ $ - putc_sig

clear_sig:
    db 0xB8, 0x03, 0x00, 0xCD, 0x10, 0xC3  ; mov ax,3 ; int 10h ; ret
clear_sig_len equ $ - clear_sig

; ---- стаб: очистить экран текущим цветом ----
clear_stub:
    mov ax, 0x0600              ; AH=06 (scroll/clear), AL=0 (всё окно)
    xor cx, cx                  ; левый верх (0,0)
    mov dx, 0x184F              ; правый низ (24,79)
    mov bh, [COLOR_ADDR]        ; атрибут = цвет (DS=KSEG при вызове)
    int 0x10
    mov ah, 0x02                ; курсор в (0,0)
    xor bh, bh
    xor dx, dx
    int 0x10
    ret                         ; near ret — вернёмся в пропатченный cmd_clear
clear_stub_end:
