; ============================================================
;  MATRIX.BIN — аналог cmatrix для SpheraOS
;  Сборка: nasm -f bin matrix.asm -o MATRIX.BIN
;  Запуск в SpheraOS: run MATRIX.BIN
; ============================================================
BITS 16
ORG 0

start:
    pusha
    push ds
    push es

    ; Инициализируем генератор случайных чисел через таймер BIOS
    xor ax, ax
    int 0x1A
    mov [seed], dx

    ; Очищаем экран (текстовый режим 80x25) и прячем курсор
    mov ax, 0x0003
    int 0x10
    mov ah, 0x01
    mov cx, 0x2607
    int 0x10

    ; Заполняем начальные позиции и длины для всех 80 столбцов
    mov cx, 80
    xor bx, bx
.init_cols:
    call rand
    xor dx, dx
    mov si, 25
    div si                  ; DX = 0..24
    neg dl                  ; Начинаем выше экрана (-24..0) для плавного старта
    mov [col_y + bx], dl

    call rand
    and al, 0x0F
    add al, 6               ; Длина хвоста от 6 до 21 символа
    mov [col_len + bx], al

    inc bx
    loop .init_cols

    mov ax, 0xB800
    mov es, ax              ; ES -> видеопамять VGA

main_loop:
    ; Задержка (~1 тик BIOS ≈ 55 мс, чтобы не летело слишком быстро)
    xor ax, ax
    int 0x1A
    mov bx, dx
.wait_tick:
    xor ax, ax
    int 0x1A
    cmp dx, bx
    je .wait_tick

    ; Проверяем нажатие клавиши (если нажата — выходим)
    mov ah, 0x01
    int 0x16
    jnz exit_prog

    ; Обновляем все 80 столбцов
    xor si, si              ; SI = номер столбца (0..79)
.col_loop:
    movsx ax, byte [col_y + si]
    movzx cx, byte [col_len + si]

    ; 1. Голова капли (ярко-белый символ, атрибут 0x0F)
    cmp ax, 0
    jl .draw_neck
    cmp ax, 24
    jg .draw_neck
    call rand
    and al, 0x3F
    add al, 33              ; Печатный ASCII (33..96)
    mov ah, 0x0F
    call put_char

.draw_neck:
    ; 2. Символ сразу за головой (ярко-зелёный, 0x0A)
    movsx ax, byte [col_y + si]
    dec ax
    cmp ax, 0
    jl .draw_tail
    cmp ax, 24
    jg .draw_tail
    call rand
    and al, 0x3F
    add al, 33
    mov ah, 0x0A
    call put_char

.draw_tail:
    ; 3. Середина хвоста (обычный зелёный, 0x02)
    movsx ax, byte [col_y + si]
    mov bx, cx
    shr bx, 1
    sub ax, bx
    cmp ax, 0
    jl .erase_end
    cmp ax, 24
    jg .erase_end
    call rand
    and al, 0x3F
    add al, 33
    mov ah, 0x02
    call put_char

.erase_end:
    ; 4. Стираем самый конец хвоста пробелом
    movsx ax, byte [col_y + si]
    sub ax, cx
    cmp ax, 0
    jl .advance
    cmp ax, 24
    jg .advance
    mov ax, 0x0720          ; Пробел
    push ax
    movsx ax, byte [col_y + si]
    sub ax, cx
    pop dx
    xchg ax, dx
    call put_char

.advance:
    ; Сдвигаем каплю вниз
    inc byte [col_y + si]
    movsx ax, byte [col_y + si]
    sub ax, cx
    cmp ax, 25              ; Весь хвост ушёл за нижний край?
    jl .next_col

    ; Перезапускаем столбец сверху
    call rand
    and al, 0x0F
    neg al
    mov [col_y + si], al

    call rand
    and al, 0x0F
    add al, 6
    mov [col_len + si], al

.next_col:
    inc si
    cmp si, 80
    jl .col_loop

    jmp main_loop

exit_prog:
    ; Забираем нажатую клавишу из буфера BIOS
    xor ax, ax
    int 0x16

    ; Восстанавливаем стандартный текстовый режим и курсор
    mov ax, 0x0003
    int 0x10

    pop es
    pop ds
    popa
    retf                    ; Возврат в ядро SpheraOS

; ------------------------------------------------------------
; put_char: выводит символ AL с атрибутом AH в (X=SI, Y=DX)
; ------------------------------------------------------------
put_char:
    push ax
    push bx
    push dx
    ; Смещение = (Y * 80 + X) * 2
    mov bx, dx
    shl bx, 6               ; Y * 64
    mov dx, bx
    shr dx, 2               ; Y * 16
    add bx, dx              ; Y * 80
    add bx, si              ; Y * 80 + X
    shl bx, 1               ; * 2 байта на ячейку
    mov [es:bx], ax
    pop dx
    pop bx
    pop ax
    ret

; ------------------------------------------------------------
; rand: быстрый 16-битный LCG -> AX
; ------------------------------------------------------------
rand:
    push dx
    mov ax, [seed]
    mov dx, 25173
    mul dx
    add ax, 13849
    mov [seed], ax
    pop dx
    ret

seed    dw 0xACE1
col_y   times 80 db 0
col_len times 80 db 0
