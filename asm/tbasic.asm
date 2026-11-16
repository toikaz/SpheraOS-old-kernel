; ==================================================================
;  SpheraOS Tiny BASIC 86 (Адаптированная версия)
;  Сборка: nasm -f bin tbasic.asm -o TBASIC.BIN
;  Запуск в ОС: run TBASIC.BIN
; ==================================================================
[CPU 386]
[BITS 16]
[ORG 0]

;==============================================================================
; Const section
;==============================================================================
STACK_SEG       EQU 1000h
STACK_OFF       EQU 0FFFFh

ROWS            EQU 25
COLS            EQU 80

DIRECT			EQU 0
RUN				EQU 1

MAX_STACK		EQU 128

;==============================================================================
; MAIN PROGRAM
;==============================================================================
START:
		call	ILM_CLEAR				;clear screen

		mov		dx,STR_WELCOME			;print welcome string
		call	PRINT_STR

		call	ILM_INIT				;init function (clear all)
		call	ILM_NLINE				;new line

CO:
		mov		sp,STACK_OFF			;clear SP (error could happened)

		mov		ax,PGM					;copy PGM address
		mov		[PGP],ax				;set PGP at beginning of program
		mov		[CURSOR],ax				;set CURSOR at beginning of line
		mov		[MODE],byte 00h			;set mode 0 (direct)

		mov		al,3Eh					;set prompt '>'
		call	ILM_GETLINE				;get line in LBUF
		call	ILM_NLINE				;new line

		cmp		[LBUF],byte 00h			;LBUF empty ?
		je		CO						;skip

		call	ILM_TSTL                ;test for line number
		cmp		al,-1					;number valid ?
		je		CO						;if not back to collection

		call	ILM_INSERT        		;insert line

		cmp		al,00h					;is direct ?
		jne		CO						;no, back to collection

XEC:
		call	ILM_XINIT             	;clear AESTACK

STMT:
		mov		dx,STR_REM				;"REM" (comment)
		call	ILM_TST
		cmp		al,00h
		je		S0

		call	ILM_NXT					;next line
		cmp		al,00h
		je		CO
		cmp		al,01h
		je		XEC

S0:
		mov		dx,STR_LET				;"LET"
		call	ILM_TST
		cmp		al,00h
		je		S1

		call	ILM_TSTV				;there is a variable ? ?
		cmp		al,-1
		je		CO
		cmp		al,00h
		je		ERROR

		mov		dx,STR_ASSIGN			;there is "=" assignement symbol ?
		call	ILM_TST
		cmp		al,00h
		je		ERROR

		call	EXPR					;evaluate expression

		call	ILM_DONE				;EOL ?
		cmp		al,00h
		je		CO

		call	ILM_STORE				;store value into variable
		cmp		al,00h
		je		CO

		call	ILM_NXT					;next line
		cmp		al,00h
		je		CO
		cmp		al,01h
		je		XEC

S1:
		mov		dx,STR_GOTO				;"GOTO"
		call	ILM_TST
		cmp		al,00h
		je		S2

		call	EXPR					;evaluate expression

		call 	ILM_DONE				;EOL ?
		cmp		al,00h
		je		CO

		call	ILM_XPER				;set PGP to new line, reset CURSOR
		cmp		al,0
		je		CO

		jmp		XEC

S2:
		mov		dx,STR_GOSUB			;"GOSUB"
		call	ILM_TST
		cmp		al,00h
		je		S3

		call 	EXPR					;evaluate expression

		call 	ILM_DONE				;EOL ?
		cmp		al,00h
		je		CO

		call	ILM_SAV					;save current line on SBRSTACK
		cmp		al,00h
		je		CO

		call	ILM_XPER				;set PGP to new line, reset CURSOR
		cmp		al,0
		je		CO

S3:
		mov		dx,STR_PRINT			;"PRINT"
		call	ILM_TST
		cmp		al,00h
		je		S8

S4:
		mov		dx,STR_QUOTES			;chack for quotes
		call	ILM_TST
		cmp		al,00h
		je		S7

		call	ILM_PRS         		;print the string
		cmp		al,00h
		je		CO

S5:
		mov		dx,STR_COMMA			;check comma for more
		call	ILM_TST
		cmp		al,00h
		je		S6

		call	ILM_SPC					;add single space

		jmp		S4

S6:
		call 	ILM_DONE				;EOL ?
		cmp		al,00h
		je		CO

        call	ILM_NLINE				;new line

        call	ILM_NXT					;next line
		cmp		al,00h
		je		CO
		cmp		al,01h
		je		XEC

S7:
		call    EXPR					;evaluate expression

		call	ILM_PRN					;print number
		cmp		al,00h
		je		CO

		jmp		S5

S8:
		mov		dx,STR_IF				;"IF"
		call	ILM_TST
		cmp		al,00h
		je		S9

		call	EXPR					;evaluate expression

		call	RELOP					;set logical operator on AESTACK

		call	EXPR					;evaluate expression

        mov		dx,STR_THEN				;check "THEN"
		call	ILM_TST
		cmp		al,00h
		je		ERROR

		call	ILM_CMPR				;perform compare
		cmp		al,-1
		je		CO
		cmp		al,00h
		jne		XEC						;match ok, execute "THEN" part

		call	ILM_NXT					;no match, next line
		cmp		al,00h
		je		CO
		cmp		al,01h
		je		XEC

S9:
		mov		dx,STR_INPUT			;"INPUT"
		call	ILM_TST
		cmp		al,00h
		je		S12

S10:
		call	ILM_TSTV				;check for Variable letter
		cmp		al,-1
		je		CO
		cmp		al,00h
		je		ERROR

		call	ILM_INNUM				;get number
		cmp		al,00h
		je		CO

        call	ILM_STORE				;store the number in the variable
		cmp		al,00h
		je		CO

        mov		dx,STR_COMMA			;check for more elements
		call	ILM_TST
		cmp		al,00h
		je		S11

        jmp		S10

S11:
		call 	ILM_DONE				;EOL ?
		cmp		al,00h
		je		CO

        call	ILM_NXT					;next line
		cmp		al,00h
		je		CO
		cmp		al,01h
		je		XEC

S12:
		mov		dx,STR_RETURN			;"RETURN"
		call	ILM_TST
		cmp		al,00h
		je		S13

		call 	ILM_DONE				;EOL ?
		cmp		al,00h
		je		CO

		call	ILM_RSTR				;restore previous line
		cmp		al,00h
		je		CO

		call	ILM_NXT					;next line
		cmp		al,00h
		je		CO
		cmp		al,01h
		je		XEC

S13:
		mov		dx,STR_END				;"END"
		call	ILM_TST
		cmp		al,00h
		je 		S14

		call	ILM_DONE				;no need to test DONE result
        jmp		CO						;always jump to collection routine

S14:
		mov		dx,STR_LIST				;"LIST"
		call	ILM_TST
		cmp		al,00h
		je		S15

		call 	ILM_DONE				;EOL ?
		cmp		al,00h
		je		CO

		cmp		byte [MODE],DIRECT		;im in DIRECT mode ?
		je		S14A

		mov		[ERROR_CODE],word ERROR_MODE
		call	ILM_ERR					;no, print error and go back to CO
		jmp		CO

S14A:
        call	ILM_LST					;print program
		jmp		CO

S15:
		mov		dx,STR_RUN				;"RUN"
		call	ILM_TST
		cmp		al,00h
		je		S16

        call 	ILM_DONE				;EOL ?
		cmp		al,00h
		je		CO

		cmp		byte [MODE],DIRECT		;im in DIRECT mode ?
		je		S15A

		mov		[ERROR_CODE],word ERROR_MODE
		call	ILM_ERR					;no, print error and go back to CO
		jmp		CO

S15A:
		mov		byte [MODE],RUN			;set RUN mode

        call	ILM_NXT					;next line
		cmp		al,00h
		je		CO
		cmp		al,01h
		je		XEC

S16:
    mov     dx,STR_RESET
    call    ILM_TST
    cmp     al,00h
    je      S17

    call    ILM_DONE
    cmp     al,00h
    je      CO

    cmp     byte [MODE],DIRECT
    je      S16A

    mov     [ERROR_CODE],word ERROR_MODE
    call    ILM_ERR
    jmp     CO

S16A:
    jmp     START

S17:
    mov     dx,STR_EXIT
    call    ILM_TST
    cmp     al,00h
    je      ERROR

    call    ILM_DONE
    cmp     al,00h
    je      CO

    ; Возврат в ядро SpheraOS через retf (аналогично chess.bin)
    mov     ax, 0x0003
    int     0x10
    retf

ERROR:
		mov		[ERROR_CODE],word ERROR_SYNTAX
		call	ILM_ERR
		jmp		CO

EXPR:
		mov		dx,STR_MINUS			;"-" (unary)
		call	ILM_TST
		cmp		al,00h
		je		E0

		call	TERM
		call	ILM_NEG
		cmp		al,00h
		je		CO
		jmp		E1

E0:
		mov		dx,STR_PLUS				;"+" (unary)
		call	ILM_TST
		cmp		al,00h
		je		E1A

E1A:
		call	TERM

E1:
		mov		dx,STR_PLUS				;"+"
		call	ILM_TST
		cmp		al,00h
		je		E2

		call	TERM
		call	ILM_ADD
		cmp		al,00h
		je		CO
		jmp		E1

E2:
		mov		dx,STR_MINUS			;test "-"
		call	ILM_TST
		cmp		al,00h
		je		E3

		call	TERM
		call	ILM_SUB
		cmp		al,00h
		je 		CO
		jmp		E1

E3:
		ret

TERM:
		call	FACT

T0:
		mov		dx,STR_MUL				;"*"
		call	ILM_TST
		cmp		al,00h
		je		T1

		call	FACT
		call 	ILM_MUL
		cmp		al,00h
		je		CO
		jmp		T0

T1:
		mov		dx,STR_DIV				;"/"
		call	ILM_TST
		cmp		al,00h
		je		T2

		call    FACT
        call	ILM_DIV
		cmp		al,00h
		je		CO
        jmp   	T0

T2:
		ret

FACT:
		call	ILM_TSTV
		cmp		al,-1
		je		CO
		cmp		al,00h
		je		F0

        call	ILM_IND
        cmp		al,00h
		je		CO
		ret

F0:
		call	ILM_TSTN
		cmp		al,-1
		je		CO
		cmp		al,00h
		je		F1
		ret

F1:
		mov		dx,STR_LPAREN			;"("
		call	ILM_TST
		cmp		al,00h
		je		F2

		call	EXPR

		mov		dx,STR_RPAREN			;")"
		call	ILM_TST
		cmp		al,00h
		je		F2
        ret

F2:
		mov		[ERROR_CODE],word ERROR_SYNTAX
		call	ILM_ERR
		jmp		CO

RELOP:
		mov		dx,STR_OP_E
		call	ILM_TST
		cmp		al,00h
		je		R0
		mov		dx,0
		jmp		R5

R0:
		mov		dx,STR_OP_NE
		call	ILM_TST
		cmp		al,00h
		je		R1
		mov		dx,1
		jmp		R5

R1:
		mov		dx,STR_OP_LE
		call	ILM_TST
		cmp		al,00h
		je		R2
		mov		dx,2
		jmp		R5

R2:
		mov		dx,STR_OP_GE
		call	ILM_TST
		cmp		al,00h
		je		R3
		mov		dx,3
		jmp		R5

R3:
		mov		dx,STR_OP_L
		call	ILM_TST
		cmp		al,00h
		je		R4
		mov		dx,4
		jmp		R5

R4:
		mov		dx,STR_OP_G
		call	ILM_TST
		cmp		al,00h
		je		R6
		mov		dx,5

R5:
		call	ILM_LIT
		cmp		al,00h
		je		CO
		ret

R6:
        mov		[ERROR_CODE],word ERROR_OPERATOR
		call	ILM_ERR
		jmp		CO

;==============================================================================
; Вывод строки (DX = адрес строки) через BIOS teletype (int 10h)
;==============================================================================
PRINT_STR:
        push ax
        push bx
        push si
        mov si, dx
        mov ah, 0x0E
        mov bx, 0x0007
    .ps_loop:
        lodsb
        test al, al
        jz .ps_done
        int 0x10
        jmp .ps_loop
    .ps_done:
        pop si
        pop bx
        pop ax
        ret

;==============================================================================
; Печать числа из DX в десятичном виде
;==============================================================================
PRINT_NUMBER:
        pusha
        mov     ax, dx
        test    ax, ax
        jns     .pn_pos
        push    ax
        mov     ah, 0x0E
        mov     al, '-'
        mov     bx, 7
        int     0x10
        pop     ax
        neg     ax
    .pn_pos:
        mov     bx, 10
        xor     cx, cx
    .pn_push:
        xor     dx, dx
        div     bx
        push    dx
        inc     cx
        test    ax, ax
        jnz     .pn_push
    .pn_pop:
        pop     ax
        mov     ah, 0x0E
        mov     bx, 7
        add     al, '0'
        int     0x10
        loop    .pn_pop
        popa
        ret

WAIT_KEY:
        xor     ax, ax
        int     16h
        ret

ILM_ADD:
        xor     bx, bx
        mov     bl, [AESTACK_POINTER]
		cmp     bl, 02h
        jb     	.stack_err
        dec     bl
		shl		bl, 1
		add		bx, AESTACK_BASE
		mov		ax, [bx]
		dec		bx
		dec		bx
		add		[bx], ax
		jo		.number_err
		dec		byte [AESTACK_POINTER]
		mov		al, 1
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		jmp		.err
	.number_err:
		mov		[ERROR_CODE], word ERROR_NUMBER_OVERFLOW
	.err:
		call	ILM_ERR
		xor		al, al
		ret

ILM_CLEAR:
        mov     ax, 0x0003
        int     0x10
        ret

ILM_CMPR:
		xor		ax, ax
        xor     si, si
        add     si, [AESTACK_POINTER]
		cmp     si, 03h
        jb     	.stack_err
        dec     si
		shl		si, 1
		add		si, AESTACK_BASE
		mov		dx, [si]
		dec     si
		dec     si
		mov		cx, [si]
		dec     si
		dec     si
		mov		bx, [si]
		sub		[AESTACK_POINTER], byte 03h
	.switch:
		cmp		cx, 00h
		je		.e
		cmp		cx, 01h
		je		.ne
		cmp		cx, 02h
		je		.le
		cmp		cx, 03h
		je		.ge
		cmp		cx, 04h
		je		.l
		cmp		cx, 05h
		je		.g
	.e:
		cmp		bx, dx
		je		.done_true
		ret
	.ne:
		cmp		bx, dx
		jne		.done_true
		ret
	.le:
		cmp		bx, dx
		jle		.done_true
		ret
	.ge:
		cmp		bx, dx
		jge		.done_true
		ret
	.l:
		cmp		bx, dx
		jl		.done_true
		ret
	.g:
		cmp		bx, dx
		jg		.done_true
		ret
	.done_true:
		mov		al, 1
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		call	ILM_ERR
		mov		al, -1
		ret

ILM_DIV:
        xor     bx, bx
        mov     bl, [AESTACK_POINTER]
		cmp     bl, 02h
        jb     	.stack_err
        dec     bl
		shl		bl, 1
		add		bx, AESTACK_BASE
		mov		cx, [bx]
		cmp		cx, 0
		je		.div_zero_err
		dec		bx
		dec		bx
		mov		ax, [bx]
		cwd
		idiv	cx
		mov		[bx], ax
		dec		byte [AESTACK_POINTER]
		mov		al, 01h
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		jmp		.err
	.div_zero_err:
		mov		[ERROR_CODE], word ERROR_DIVIDE_ZERO
	.err:
		call	ILM_ERR
		xor		al, al
		ret

ILM_DONE:
		mov		si, [CURSOR]
	.skip_blanks:
		cmp		[si], byte 00h
		je		.done
		cmp		[si], byte 20h
		ja		.err
		inc		si
		jmp		.skip_blanks
	.err:
		mov		[ERROR_CODE], word ERROR_SYNTAX
		call	ILM_ERR
		xor		al, al
		ret
	.done:
		mov		al, 01h
		ret

ILM_ERR:
		call	ILM_NLINE
	.mode:
		cmp		[MODE], byte 00h
		je		.err_direct
	.err_at_line:
		mov		dx, ERROR_STR_AT_LINE
		call	PRINT_STR
	.line:
		mov		ax, [PGP]
		sub		ax, PGM
		mov		bl, COLS
		div		bl
	.num:
		mov		dx, ax
		call	PRINT_NUMBER
		jmp		.err_code
	.err_direct:
		mov		dx, ERROR_STR
		call	PRINT_STR
	.err_code:
		mov		dx, [ERROR_CODE]
		call	PRINT_STR
		call	ILM_NLINE
		ret

ILM_GETLINE:
	.prompt:
		mov     ah, 0Eh
        mov     bh, 00h
        int     10h
	.init:
		mov     al, 00h
        mov		di, LBUF
        mov     cx, COLS
		rep		stosb
		mov		si, 00h
	.cycle:
		xor     ax, ax
        int     16h
		cmp		al, 0Dh
		je		.done
		cmp		al, 08h
		je		.backspace
		cmp		si, COLS-2
		jge		.cycle
		cmp		al, 20h
		jb		.cycle
		cmp		al, 7Eh
		ja		.cycle
		mov		bx, LBUF
		mov		[bx+si], al
		inc		si
		mov     ah, 0Eh
        mov     bh, 00h
        int     10h
		jmp		.cycle
	.backspace:
		cmp		si, 0
		jle		.cycle
		dec		si
		mov		bx, LBUF
		mov		[bx+si], byte 00h
		mov		bh, 00h
		mov		ah, 03h
		int		10h
		dec		dl
		mov		ah, 02h
		int		10h
		mov     ah, 0Ah
		mov		al, 20h
        int		10h
		jmp		.cycle
	.done:
		ret

ILM_IND:
        xor     bx, bx
        mov     bl, [AESTACK_POINTER]
		cmp     bl, 00h
        jbe     .stack_err
        dec     bl
		shl		bl, 1
		add		bx, AESTACK_BASE
		mov 	si, [bx]
		shl		si, 1
		add 	si, VARIABLES
		mov		ax, [si]
		mov		[bx], ax
		mov		al, 01h
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		call	ILM_ERR
		xor		al, al
		ret

ILM_INIT:
		mov		[MODE], byte 00h
		mov     al, 00h
        mov		di, PGM
        mov     cx, 256*COLS
		rep		stosb
        mov     ax, 0000h
        mov		di, VARIABLES
        mov     cx, 26
		rep		stosw
		mov		[PGP], word PGM
		mov		[CURSOR], word PGM
		mov		[AESTACK_POINTER], byte 00h
		mov		[SBRSTACK_POINTER], byte 00h
		ret

ILM_INNUM:
		mov		al, 23h
		call	ILM_GETLINE
	.init:
		mov		si, LBUF
		xor		ax, ax
		mov		bx, 10
		xor		di, di
		xor		ch, ch
	.skip_blanks:
		cmp		[si], byte 00h
		je		.empty_line
		cmp		[si], byte 20h
		jg		.check_sign
		inc		si
		jmp		.skip_blanks
	.check_sign:
		cmp		[si], byte 2Bh
		je		.skip_sign
		cmp		[si], byte 2Dh
		jne		.get_number
		mov		di, 1
	.skip_sign:
		inc		si
	.get_number:
		mov		cl, [si]
		cmp		cl, 00h
		je		.fix_sign
		cmp 	cl, 30h
		jl		.not_number
		cmp 	cl, 39h
		jg		.not_number
		sub 	cl, 30h
		mul 	bx
		jo		.big_number
		add		ax, cx
		jo		.big_number
		inc 	si
		jmp		.get_number
	.fix_sign:
		cmp		di, 00h
		je		.done
		neg		ax
	.done:
		mov		dx, ax
		call	ILM_LIT
		cmp		al, 00h
		jne		.done_ok
		ret
	.done_ok:
		call	ILM_NLINE
		mov		al, 01h
		ret
	.empty_line:
		mov		[ERROR_CODE], word ERROR_EMPTY_LINE
		jmp		.err
	.not_number:
		mov		[ERROR_CODE], word ERROR_NOT_NUMBER
		jmp		.err
	.big_number:
		mov		[ERROR_CODE], word ERROR_NUMBER_OVERFLOW
	.err:
		call	ILM_ERR
		xor		al, al
		ret

ILM_INSERT:
		mov		dl, al
		mov		cx, COLS
		sub		cx, si
		add		si, LBUF
		mov		bl, COLS
		mul		bl
		mov		di, ax
		add		di, PGM
        rep     movsb
		mov		al, dl
		ret

ILM_LIT:
		xor		bx, bx
        mov		bl, [AESTACK_POINTER]
		cmp		bl, MAX_STACK
		jae		.stack_err
		shl		bl, 1
		add		bx, AESTACK_BASE
		mov		[bx], dx
		inc		byte [AESTACK_POINTER]
		mov		al, 01h
		ret
	.stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_OVERFLOW
		call	ILM_ERR
		xor		al, al
		ret

ILM_LST:
		mov		[PAGE_BREAK], byte 00h
		mov		[LINE_COUNTER], byte 01h
		mov		di, PGM+COLS
	.cycle:
		cmp		di, PGM+256*80
		jge		.done
		cmp		[di], byte 00h
		je		.next
		xor		dx, dx
		mov		dl, [LINE_COUNTER]
		call	PRINT_NUMBER
		mov		dx, di
		call	PRINT_STR
		call	ILM_NLINE
		inc		byte [PAGE_BREAK]
		cmp		byte [PAGE_BREAK], ROWS-1
		jb		.next
		call	WAIT_KEY
		mov		byte [PAGE_BREAK], 00h
	.next:
		add		di, COLS
		inc		byte [LINE_COUNTER]
		jmp		.cycle
	.done:
		ret

ILM_MUL:
        xor     bx, bx
        mov     bl, [AESTACK_POINTER]
		cmp     bl, 02h
        jb     	.stack_err
        dec     bl
		shl		bl, 1
		add		bx, AESTACK_BASE
		mov		ax, [bx]
		dec		bx
		dec		bx
		imul	word [bx]
		jo		.number_err
		mov		[bx], ax
		dec		byte [AESTACK_POINTER]
		mov		al, 01h
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		jmp		.err
	.number_err:
		mov		[ERROR_CODE], word ERROR_NUMBER_OVERFLOW
	.err:
		call 	ILM_ERR
		xor		al, al
		ret

ILM_NEG:
        xor     bx, bx
        mov     bl, [AESTACK_POINTER]
		cmp     bl, 00h
        jbe     .stack_err
        dec     bl
		shl		bl, 1
		add		bx, AESTACK_BASE
		neg		word [bx]
		mov		al, 01h
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		call	ILM_ERR
		xor		al, al
		ret

ILM_NLINE:
        mov     ah, 0Eh
        mov     al, 0Dh
        int     10h
        mov     al, 0Ah
        int     10h
        ret

ILM_NXT:
        cmp		[MODE], byte 00h
		je		.collection
		mov		bx, [PGP]
	.cycle:
		add		bx, COLS
		cmp		bx, PGM+(256*80)
		jge		.err
		cmp		[bx], byte 00h
		je		.cycle
	.done:
		mov		[PGP], bx
		mov		[CURSOR], bx
		mov		al, 01h
		ret
	.err:
		sub		bx, COLS
		mov		[PGP], bx
		mov		[ERROR_CODE], word ERROR_PGP
		call	ILM_ERR
	.collection:
		xor		al, al
		ret

ILM_PRN:
        xor     bx, bx
        mov     bl, [AESTACK_POINTER]
		cmp     bl, 01h
        jl     	.stack_err
        dec     bl
		shl		bl, 1
		add		bx, AESTACK_BASE
		mov		dx, [bx]
		call	PRINT_NUMBER
		dec		byte [AESTACK_POINTER]
		mov		al, 1
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		call	ILM_ERR
		xor		al, al
		ret

ILM_PRS:
        mov		si, [CURSOR]
	.cycle:
		cmp		[si], byte 00h
		je		.err
		cmp		[si], byte 22h
		je		.done
		mov		al, [si]
		mov     ah, 0Eh
        mov     bh, 00h
		int		10h
		inc 	si
		jmp		.cycle
	.err:
		mov		[ERROR_CODE], word ERROR_QUOTES
		call	ILM_ERR
		xor		al, al
		ret
	.done:
		inc		si
		mov		[CURSOR], si
		mov		al, 01h
        ret

ILM_RSTR:
        xor     bx, bx
        mov     bl, [SBRSTACK_POINTER]
		cmp     bl, 00h
        jbe     .stack_err
        dec     bl
		add		bx, SBRSTACK_BASE
		xor		ax, ax
		mov 	al, [bx]
		mov		cl, COLS
		mul		cl
		add		ax, PGM
		mov		[PGP], ax
		dec		byte [SBRSTACK_POINTER]
		mov		al, 01h
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_SBRSTACK_UNDERFLOW
		call	ILM_ERR
		xor		al, al
		ret

ILM_SAV:
		xor		bx, bx
        mov		bl, [SBRSTACK_POINTER]
		cmp		bl, MAX_STACK
		jae		.stack_err
		add		bx, SBRSTACK_BASE
		mov		ax, [PGP]
		sub		ax, PGM
		mov		cl, COLS
		div		cl
		xor		ah, ah
		mov		[bx], ax
		inc		byte [SBRSTACK_POINTER]
		mov		al, 01h
		ret
	.stack_err:
		mov		[ERROR_CODE], word ERROR_SBRSTACK_OVERFLOW
		call	ILM_ERR
		xor		al, al
		ret

ILM_SPC:
        mov		al, 20h
		mov     ah, 0Eh
        mov     bh, 00h
		int		10h
        ret

ILM_STORE:
        xor     bx, bx
        mov     bl, [AESTACK_POINTER]
		cmp     bl, 02h
        jb     	.stack_err
        dec     bl
		shl		bl, 1
		add		bx, AESTACK_BASE
		mov		ax, [bx]
		dec		bx
		dec		bx
		mov		di, [bx]
		shl		di, 1
		add		di, VARIABLES
		mov		[di], ax
		dec		byte [AESTACK_POINTER]
		dec		byte [AESTACK_POINTER]
		mov		al, 1
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		call	ILM_ERR
		xor		al, al
		ret

ILM_SUB:
        xor     bx, bx
        mov     bl, [AESTACK_POINTER]
		cmp     bl, 02h
        jb     	.stack_err
        dec     bl
		shl		bl, 1
		add		bx, AESTACK_BASE
		mov		ax, [bx]
		dec		bx
		dec		bx
		sub		[bx], ax
		dec		byte [AESTACK_POINTER]
		mov		al, 01h
		ret
    .stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		call	ILM_ERR
		xor		al, al
		ret

ILM_TST:
		mov		ax, [CURSOR]
		mov		si, ax
	.skip_blanks:
		cmp		[si], byte 00h
		je		.nomatch
		cmp		[si], byte 20h
		ja		.compare
		inc		si
		jmp		.skip_blanks
	.compare:
		xor		cx, cx
		mov		bx, dx
	.strlen:
		cmp		[bx], byte 00h
		je		.strcmp
		inc 	bx
		inc		cx
		jmp		.strlen
	.strcmp:
		mov     di, dx
        repe    cmpsb
        jne     .nomatch
	.match:
		mov		[CURSOR], si
		mov		al, 01h
		ret
	.nomatch:
		mov		[CURSOR], ax
		xor		al, al
		ret

ILM_TSTL:
		xor		ax, ax
		mov		ch, 10
		mov		bx, LBUF
		mov		si, 00h
	.skip_blanks:
		mov		cl, [bx+si]
		cmp		cl, 00h
		je		.done
		cmp 	cl, byte 20h
		jg		.get_number
		inc		si
		jmp		.skip_blanks
	.get_number:
		mov		cl, [bx+si]
		cmp 	cl, 30h
		jl		.done
		cmp 	cl, 39h
		jg		.done
		sub 	cl, 30h
		mul 	ch
		jc		.err
		add		al, cl
		jc		.err
		inc 	si
		jmp		.get_number
	.done:
		cmp		ax, 00h
		jne		.blank
		ret
	.blank:
		cmp		[bx+si], byte 20h
		jg		.err
		ret
	.err:
		mov		[ERROR_CODE], word ERROR_LINE_NUMBER
		call	ILM_ERR
		mov		al, -1
		ret

ILM_TSTN:
		xor		ch, ch
		xor		ax, ax
		mov		bx, 10
		mov		di, 0
		mov		si, [CURSOR]
    .skip_blanks:
		cmp		[si], byte 00h
		je		.not_found
		cmp 	[si], byte 20h
		ja		.check_sign
		inc		si
		jmp		.skip_blanks
	.check_sign:
		cmp		[si], byte 2Bh
		je		.skip_sign
		cmp		[si], byte 2Dh
		jne		.get_number
		mov		di, 1
	.skip_sign:
		inc		si
	.check_number:
		cmp 	[si], byte 30h
		jl		.not_found
		cmp 	[si], byte 39h
		jg		.not_found
	.get_number:
		mov		cl, [si]
		cmp 	cl, 30h
		jl		.fix_sign
		cmp 	cl, 39h
		jg		.fix_sign
		sub 	cl, 30h
		mul 	bx
		jo		.number_err
		add		ax, cx
		jo		.number_err
		inc 	si
		jmp		.get_number
	.fix_sign:
		cmp		di, 00h
		je		.done
		neg		ax
	.done:
		mov		dx, ax
		call	ILM_LIT
		cmp		al, 00h
		jne		.done_ok
		mov		al, -1
		ret
	.done_ok:
		mov		[CURSOR], si
		mov		al, 01h
		ret
	.number_err:
		mov		[ERROR_CODE], word ERROR_NUMBER_OVERFLOW
		call	ILM_ERR
		mov		al, -1
		ret
	.not_found:
		xor		al, al
		ret

ILM_TSTV:
        mov     si, [CURSOR]
    .skip_blanks:
		cmp		[si], byte 00h
		je		.nomatch
		cmp		[si], byte 20h
		ja		.check
		inc		si
		jmp		.skip_blanks
	.check:
		cmp		[si], byte 41h
		jb		.nomatch
		cmp		[si], byte 5Ah
		ja		.nomatch
		xor		dh, dh
		mov		dl, byte [si]
		sub		dl, 41h
	.done:
		call	ILM_LIT
		cmp		al, 00h
		jne		.done_ok
		mov		al, -1
		ret
	.done_ok:
		inc 	si
		mov		[CURSOR], si
		mov		al, 1
		ret
	.nomatch:
		xor		al, al
		ret

ILM_XPER:
		mov		dl, COLS
        xor     bx, bx
        mov     bl, [AESTACK_POINTER]
		cmp		bl, 00h
        jbe     .stack_err
        dec		bl
		shl		bl, 1
		add		bx, AESTACK_BASE
		mov		ax, [bx]
		cmp		ax, 00h
		jle		.pgp_err
		cmp		ax, 0FFh
		jg		.pgp_err
		xor		ah, ah
		mul		dl
		add		ax, PGM
		mov		si, ax
		cmp		[si], byte 00h
        je      .empty_err
		mov		[PGP], si
		mov		[CURSOR], si
		mov		al, 01h
		ret
	.stack_err:
		mov		[ERROR_CODE], word ERROR_AESTACK_UNDERFLOW
		jmp		.err
	.pgp_err:
		mov		[ERROR_CODE], word ERROR_PGP
		jmp		.err
	.empty_err:
		mov		[ERROR_CODE], word ERROR_EMPTY_LINE
	.err:
		call	ILM_ERR
		xor		al, al
		ret

ILM_XINIT:
		mov		[AESTACK_POINTER], byte 00h
		ret

;==============================================================================
; Vars section
;==============================================================================
STR_WELCOME		db "TINY BASIC 8086 (SpheraOS Edition)",0Ah,0Dh,00h

STR_EXIT    	db "EXIT",00h
STR_REM			db "REM",00h
STR_LET			db "LET",00h
STR_GOTO		db "GOTO",00h
STR_GOSUB		db "GOSUB",00h
STR_END			db "END",00h
STR_PRINT		db "PRINT",00h
STR_LIST		db "LIST",00h
STR_RUN			db "RUN",00h
STR_RESET		db "RESET",00h
STR_RETURN		db "RETURN",00h
STR_INPUT		db "INPUT",00h
STR_IF			db "IF",00h
STR_THEN		db "THEN",00h

STR_COMMA		db ',',00h
STR_QUOTES		db '"',00h
STR_ASSIGN		db '=',00h
STR_MINUS		db '-',00h
STR_PLUS		db '+',00h
STR_MUL			db '*',00h
STR_DIV			db '/',00h
STR_LPAREN		db '(',00h
STR_RPAREN		db ')',00h

STR_OP_E		db "==",00h
STR_OP_NE		db "!=",00h
STR_OP_LE		db "<=",00h
STR_OP_GE		db ">=",00h
STR_OP_L		db "<",00h
STR_OP_G		db ">",00h

ERROR_CODE					dw 0000h

ERROR_STR					db "ERROR",00h
ERROR_STR_AT_LINE			db "ERROR at line ",00h
ERROR_SYNTAX				db ":Syntax error",00h
ERROR_LINE_NUMBER			db ":Invalid line number",00h
ERROR_EMPTY_LINE			db ":Empty line",00h
ERROR_PGP 					db ":PGP out of range",00h
ERROR_QUOTES				db ":Missing quotes",00h
ERROR_INVALID_NUMBER		db ":Number invalid",00h
ERROR_NOT_NUMBER			db ":Not a number",00h
ERROR_NUMBER_OVERFLOW		db ":Number out of range",00h
ERROR_AESTACK_OVERFLOW		db ":Arithmetic stack overflow",00h
ERROR_AESTACK_UNDERFLOW		db ":Arithmetic stack underflow",00h
ERROR_SBRSTACK_OVERFLOW		db ":Subroutines stack overflow",00h
ERROR_SBRSTACK_UNDERFLOW	db ":Subroutines stack underflow",00h
ERROR_DIVIDE_ZERO			db ":Divide by zero",00h
ERROR_OPERATOR				db ":Invalid operator",00h
ERROR_MODE					db ":Unavailable for current mode",00h

MODE			db 00h
VARIABLES		times 26 dw 0000h
AESTACK_BASE	times MAX_STACK dw 0000h
AESTACK_POINTER db 00h
SBRSTACK_BASE	times MAX_STACK db 00h
SBRSTACK_POINTER db 00h
LBUF 			times COLS db 00h
CURSOR			dw	0000h
PGP				dw	0000h
PGM				dw	0000h
LINE_COUNTER	db 00h
PAGE_BREAK		db 00h
