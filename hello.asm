; hello.asm — Простейшая тестовая программа для SpheraOS
; Собирается как плоский бинарник, загружается на 0x8000:0000
BITS 16
ORG 0

start:
    ; Выводим приветствие
    mov si, msg_hello
    call Print
    
    ; Ждём нажатия клавиши
    xor ah, ah
    int 0x16
    
    ; Выводим прощание
    mov si, msg_done
    call Print
    
    ; ВАЖНО: RETF (далёкий возврат) — иначе система зависнет!
    retf

Print:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp Print
.done:
    ret

msg_hello db "Hello from .BIN program!", 0x0D, 0x0A
          db "Press any key to continue...", 0x0D, 0x0A, 0
msg_done  db 0x0D, 0x0A, "Returning to shell...", 0x0D, 0x0A, 0
