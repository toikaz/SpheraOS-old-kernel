; snake.asm — Растущая змейка для SpheraOS
BITS 16
ORG 0x100

start:
    mov ax, 0x0003
    int 0x10
    mov ah, 0x01
    mov cx, 0x2000
    int 0x10

    ; Инициализация счетчика
    mov dh, 0
    mov dl, 0
    call set_cur
    mov si, s_score
    call pstr

    ; Инициализация змейки (длина 3)
    mov byte [dir], 'd'
    mov word [head_idx], 2
    mov word [tail_idx], 0
    
    mov byte [hist_x + 0], 38
    mov byte [hist_y + 0], 12
    mov byte [hist_x + 1], 39
    mov byte [hist_y + 1], 12
    mov byte [hist_x + 2], 40
    mov byte [hist_y + 2], 12

    mov word [score], 0
    mov word [seed], 1234

    ; Рисуем начальную змейку
    mov si, 0
.draw_init:
    mov dl, [hist_x + si]
    mov dh, [hist_y + si]
    mov al, 'o'
    mov bl, 0x0A
    call draw
    inc si
    cmp si, 3
    jb .draw_init

    call spawn_food

.loop:
    ; Задержка
    mov cx, 1
    mov dx, 0
    mov ah, 0x86
    int 0x15

    ; Ввод
    mov ah, 1
    int 0x16
    jz .move
    mov ah, 0
    int 0x16
    cmp al, 'w'
    je .u
    cmp al, 's'
    je .d
    cmp al, 'a'
    je .l
    cmp al, 'd'
    je .r
    cmp al, 27
    je .exit
    jmp .move

.u: cmp byte [dir], 's'
    je .move
    mov byte [dir], 'w'
    jmp .move
.d: cmp byte [dir], 'w'
    je .move
    mov byte [dir], 's'
    jmp .move
.l: cmp byte [dir], 'd'
    je .move
    mov byte [dir], 'a'
    jmp .move
.r: cmp byte [dir], 'a'
    je .move
    mov byte [dir], 'd'

.move:
    ; Берем координаты текущей головы
    mov bx, [head_idx]
    mov dl, [hist_x + bx]
    mov dh, [hist_y + bx]

    ; Вычисляем новую голову
    cmp byte [dir], 'w'
    je .mu
    cmp byte [dir], 's'
    je .md
    cmp byte [dir], 'a'
    je .ml
    inc dl
    jmp .mc
.mu: dec dh
    jmp .mc
.md: inc dh
    jmp .mc
.ml: dec dl

.mc:
    ; Проверка стен
    cmp dl, 80
    jae .over
    cmp dh, 25
    jae .over

    ; Проверка на столкновение с собой (читаем символ с экрана)
    mov ah, 0x02
    xor bh, bh
    int 0x10
    mov ah, 0x08
    int 0x10
    cmp al, 'o'
    je .over

    ; Обновляем голову в массиве (циклический буфер на 32)
    inc word [head_idx]
    and word [head_idx], 31
    mov bx, [head_idx]
    mov [hist_x + bx], dl
    mov [hist_y + bx], dh

    ; Проверка яблока
    cmp dl, [food_x]
    jne .no_eat
    cmp dh, [food_y]
    jne .no_eat

    ; Съели яблоко! (хвост НЕ стираем)
    inc word [score]
    call upd_score
    call spawn_food
    jmp .draw_head

.no_eat:
    ; Не съели, стираем хвост и двигаем его
    mov bx, [tail_idx]
    mov dl, [hist_x + bx]
    mov dh, [hist_y + bx]
    mov al, ' '
    mov bl, 0x00
    call draw

    inc word [tail_idx]
    and word [tail_idx], 31

.draw_head:
    ; Рисуем новую голову
    mov bx, [head_idx]
    mov dl, [hist_x + bx]
    mov dh, [hist_y + bx]
    mov al, 'o'
    mov bl, 0x0A
    call draw
    jmp .loop

.over:
    mov ah, 0
    int 0x16
.exit:
    mov ax, 3
    int 0x10
    retf

; --- Спавн еды ---
spawn_food:
    inc word [seed]
    mov ax, [seed]
    xor dx, dx
    mov cx, 76
    div cx
    add dl, 2
    mov [food_x], dl

    mov ax, [seed]
    mov cx, 79
    mul cx
    add ax, 333
    xor dx, dx
    mov cx, 21
    div cx
    add dl, 2
    mov [food_y], dl

    ; Рисуем яблоко
    mov dl, [food_x]
    mov dh, [food_y]
    mov al, '@'
    mov bl, 0x0C
    call draw
    ret

; --- Утилиты ---
set_cur:
    mov ah, 0x02
    xor bh, bh
    int 0x10
    ret

draw:
    call set_cur
    mov ah, 0x09
    mov cx, 1
    int 0x10
    ret

pstr:
    mov ah, 0x0E
.p: lodsb
    test al, al
    jz .e
    int 0x10
    jmp .p
.e: ret

upd_score:
    mov dh, 0
    mov dl, 7
    call set_cur
    mov ax, [score]
    mov bl, 10
    div bl
    add ax, 0x3030
    mov bx, ax
    mov ah, 0x0E
    mov al, bl
    int 0x10
    mov al, bh
    int 0x10
    ret

; --- Данные ---
s_score  db "SCORE: 00", 0
dir      db 'd'
head_idx dw 2
tail_idx dw 0
food_x   db 20
food_y   db 10
score    dw 0
seed     dw 1234

; Массив истории (макс длина 32)
hist_x   times 32 db 0
hist_y   times 32 db 0
