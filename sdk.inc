; ============================================================
;  SpheraOS GUI SDK  -  sdk.inc
;
;  A GUI program is a flat binary (ORG 0) of at most ~60 KB,
;  built with:   nasm -f bin myapp.asm -o myapp.app
;  Copy it to the disk as  MYAPP.APP  and press Enter on it in
;  the Files window - it opens as a window and keeps running
;  in the background (multitasking) while other windows work.
;
;  File layout:
;    +00  'SGA1'          magic          (APP_HEADER does this)
;    +04  dw width        client width  in pixels (16..300)
;    +06  dw height       client height in pixels (16..170)
;    +08  title[12]       window title (max 11 chars)
;    +20  reserved
;    +32  entry point     (first code after APP_HEADER)
;
;  The entry point is a FAR-called handler (end it with RETF).
;  On entry:  AX = message, BL = ascii, BH = scan (MSG_KEY only)
;  On exit :  AL = 1 if the window should be redrawn
;  The program owns one 64 KB segment: CS = its own code+data.
;  Start the handler with   push cs / pop ds   to reach your data.
;
;  Messages:
;    MSG_INIT   once, right after loading
;    MSG_TICK   18.2 times per second, also when not focused
;    MSG_KEY    a key was pressed while this window is focused
;    MSG_DRAW   paint the window (drawing calls work only here)
;    MSG_CLOSE  the window is being closed
;
;  API: put the arguments in registers, then   GUI API_xxx
;  (INT 60h). Every register except AX and CF is preserved.
;  Coordinates are relative to the client area, (0,0) = top-left.
;
;    API_CLEAR  AL=color                      fill the client area
;    API_FILL   AL=color BX=x CX=y DX=w SI=h  filled rectangle
;    API_STR    DS:SI=asciiz BX=x CX=y DL=color
;    API_CHAR   AL=char BX=x CX=y DL=color
;    API_NUM    AL=color BX=x CX=y DX=value   unsigned number
;    API_RND    BX=n -> AX = random 0..n-1
;    API_TICKS  -> AX = BIOS timer, 18.2 per second
;    API_PIX    AL=color BX=x CX=y
;    API_LOAD   DS:SI = 11-byte 8.3 name ("NOTES   TXT"),
;               ES:DI = buffer, CX = max bytes
;               -> AX = bytes read, CF=1 if not found / disk error
;    API_EXIT   close this program's window
;    API_SOUND  BX = divisor (1193180 / Hz), BX = 0 = silence
;
;  Colors: VGA 256-color palette (0 black, 1 blue, 2 green,
;  3 cyan, 4 red, 7 light gray, 8 dark gray, 9 light blue,
;  10 light green, 12 light red, 14 yellow, 15 white).
;  Text is 8x8 pixels, ASCII 0..127.
; ============================================================

MSG_INIT   equ 0
MSG_TICK   equ 1
MSG_KEY    equ 2
MSG_DRAW   equ 3
MSG_CLOSE  equ 4

API_CLEAR  equ 0
API_FILL   equ 1
API_STR    equ 2
API_CHAR   equ 3
API_NUM    equ 4
API_RND    equ 5
API_TICKS  equ 6
API_PIX    equ 7
API_LOAD   equ 9
API_EXIT   equ 10
API_SOUND  equ 11

KEY_ESC    equ 0x01
KEY_ENTER  equ 0x1C
KEY_SPACE  equ 0x39
KEY_UP     equ 0x48
KEY_DOWN   equ 0x50
KEY_LEFT   equ 0x4B
KEY_RIGHT  equ 0x4D

%macro GUI 1
    mov ah, %1
    int 0x60
%endmacro

; APP_HEADER "Title", width, height   (must be the first thing in the file)
%macro APP_HEADER 3
    db 'SGA1'
    dw %2, %3
%%title:
    db %1
    times 12-($-%%title) db 0
    times 32-($-$$) db 0
%endmacro
