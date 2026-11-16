; ============================================================
;  SpheraOS v3.0  -  kernel.asm
;  Plumbum shell + PLB language, FAT12, multitasking, Pulsar
;  Build: nasm -f bin kernel.asm -o kernel.bin
; ============================================================
BITS 16
ORG 0

KSEG        equ 0x1000
TSEG0       equ 0x2000
SCRATCH     equ 0x8000
EDSEG       equ 0x9000
VIDEO       equ 0xB800

MAXTASK     equ 6
SLICE       equ 20

TK_STATE    equ 0
TK_FLAGS    equ 1
TK_PC       equ 2
TK_START    equ 4
TK_DUR      equ 6
TK_CSP      equ 8
TK_SEG      equ 10
TK_NAME     equ 12
TK_SIZE     equ 32

ST_FREE     equ 0
ST_READY    equ 1
ST_SLEEP    equ 2
ST_DEAD     equ 3

F_FG        equ 1
F_RUN       equ 2

T_TEXTMAX   equ 0x7800
T_VARS      equ 0x7C00
T_VARN      equ 32
T_VARSZ     equ 80
T_CTL       equ 0x8800
T_CTLEND    equ 0x8990
T_TMP       equ 0x9000

K_IF        equ 1
K_WHILE     equ 2
K_FOR       equ 3
K_GOSUB     equ 4

; ------------------------------------------------------------
start:
    cli
    xor ax, ax
    mov ds, ax
    mov dl, [0x500]
    mov ax, KSEG
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFF0
    sti
    cld
    mov di, bss_start
    mov cx, 0x0800
    xor al, al
    rep stosb
    mov [bdrive], dl
    mov word [spt], 18
    mov word [heads], 2
    mov cx, MAXTASK
    mov bx, tasks
    mov ax, TSEG0
.ti:
    mov [bx+TK_SEG], ax
    mov word [bx+TK_CSP], T_CTL
    add ax, 0x1000
    add bx, TK_SIZE
    loop .ti
    mov byte [tasks+TK_STATE], ST_READY
    mov byte [tasks+TK_FLAGS], F_FG
    mov ax, TSEG0
    call ZeroVars
    xor ax, ax
    int 0x1A
    mov [boot_t], dx
    mov [boot_t+2], cx
    mov [seed], dx
    mov ax, 0x0003
    int 0x10
    mov si, msg_banner
    call Print
    call MountDrive
    jnc .mok
    mov si, msg_nomount
    call Print
    jmp shell
.mok:
    call LoadRoot
    jc near shell
    mov si, auto_name
    call FindEntry
    jc near shell
    mov si, auto_cmd
    mov di, cmdbuf
    call CopyStr
    mov si, cmdbuf
    call ShellBuiltin
    jmp shell

; ------------------------------------------------------------
; Console
; ------------------------------------------------------------
PutC:                           ; AL = char (LF -> CR LF)
    push ax
    push bx
    cmp al, 0x0A
    jne .raw
    mov ax, 0x0E0D
    mov bx, 0x0007
    int 0x10
    mov al, 0x0A
.raw:
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    pop bx
    pop ax
    ret

Print:                          ; DS:SI asciiz
    push ax
    push si
.l:
    mov al, [si]
    inc si
    test al, al
    jz .d
    call PutC
    jmp .l
.d:
    pop si
    pop ax
    ret

PrintNL:
    push ax
    mov al, 0x0A
    call PutC
    pop ax
    ret

CopyStr:                        ; DS:SI -> DS:DI (with NUL)
    push ax
    push si
    push di
.l:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    test al, al
    jnz .l
    pop di
    pop si
    pop ax
    ret

UpCase:                         ; AL
    cmp al, 'a'
    jb .r
    cmp al, 'z'
    ja .r
    sub al, 32
.r:
    ret

Div32by16:                      ; DX:AX / CX -> DX:AX, BX = remainder
    mov bx, ax
    mov ax, dx
    xor dx, dx
    div cx
    xchg ax, bx
    div cx
    xchg dx, bx
    ret

NumToStr:                       ; DX:AX -> numbuf (decimal asciiz)
    pusha
    mov di, numbuf+11
    mov byte [di], 0
.l:
    mov cx, 10
    call Div32by16
    add bl, '0'
    dec di
    mov [di], bl
    mov cx, ax
    or cx, dx
    jnz .l
    mov si, di
    mov di, numbuf
.c:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    test al, al
    jnz .c
    popa
    ret

PrintDec32:                     ; DX:AX
    push si
    call NumToStr
    mov si, numbuf
    call Print
    pop si
    ret

PrintDec:                       ; AX unsigned
    push dx
    xor dx, dx
    call PrintDec32
    pop dx
    ret

PrintSDec:                      ; AX signed
    push ax
    test ax, ax
    jns .p
    push ax
    mov al, '-'
    call PutC
    pop ax
    neg ax
.p:
    call PrintDec
    pop ax
    ret

PrintHexB:                      ; AL
    push ax
    push ax
    shr al, 4
    call .nib
    pop ax
    and al, 0x0F
    call .nib
    pop ax
    ret
.nib:
    add al, '0'
    cmp al, '9'
    jbe .o
    add al, 7
.o:
    call PutC
    ret

PrintHexW:                      ; AX
    push ax
    mov al, ah
    call PrintHexB
    pop ax
    call PrintHexB
    ret

Name83Text:                     ; SI -> 11 bytes ; DI = dest "NAME.EXT",0
    pusha
    mov bx, si
    mov cx, 8
.n:
    mov al, [si]
    cmp al, ' '
    je .e
    mov [di], al
    inc di
    inc si
    loop .n
.e:
    lea si, [bx+8]
    cmp byte [si], ' '
    je .z
    mov byte [di], '.'
    inc di
    mov cx, 3
.x:
    mov al, [si]
    cmp al, ' '
    je .z
    mov [di], al
    inc di
    inc si
    loop .x
.z:
    mov byte [di], 0
    popa
    ret

PrintName83:                    ; SI -> 11 bytes, padded to 14 columns
    pusha
    mov di, tmpname
    call Name83Text
    mov si, tmpname
    xor cx, cx
.p:
    mov al, [si]
    test al, al
    jz .pad
    call PutC
    inc si
    inc cx
    jmp .p
.pad:
    cmp cx, 14
    jae .d
    mov al, ' '
    call PutC
    inc cx
    jmp .pad
.d:
    popa
    ret

StrToInt:                       ; DS:SI -> AX (signed), SI advanced
    push bx
    push cx
    push dx
    xor bx, bx
    xor cx, cx
.sp:
    cmp byte [si], ' '
    jne .sg
    inc si
    jmp .sp
.sg:
    cmp byte [si], '-'
    jne .d
    mov cx, 1
    inc si
.d:
    mov al, [si]
    cmp al, '0'
    jb .e
    cmp al, '9'
    ja .e
    sub al, '0'
    xor ah, ah
    push ax
    mov ax, bx
    mov dx, 10
    mul dx
    mov bx, ax
    pop ax
    add bx, ax
    inc si
    jmp .d
.e:
    mov ax, bx
    test cx, cx
    jz .r
    neg ax
.r:
    pop dx
    pop cx
    pop bx
    ret

; ------------------------------------------------------------
; Keyboard (runs the scheduler while idle)
; ------------------------------------------------------------
GetKey:                         ; -> AX (AH scan, AL ascii)
.w:
    mov ah, 1
    int 0x16
    jnz .have
    call SchedTick
    test al, al
    jnz .w
    sti
    hlt
    jmp .w
.have:
    xor ah, ah
    int 0x16
    ret

ReadLine:                       ; -> inbuf ; CF=1 if Ctrl+C
    push bx
    push cx
    push si
    push di
    mov di, inbuf
    xor cx, cx
.key:
    call GetKey
    cmp al, 13
    je .enter
    cmp al, 8
    je .bs
    cmp al, 3
    je .cc
    test al, al
    jnz .chr
    cmp ah, 0x48
    je .hist
    jmp .key
.chr:
    cmp al, 32
    jb .key
    cmp cx, 100
    jae .key
    mov [di], al
    inc di
    inc cx
    call PutC
    jmp .key
.bs:
    test cx, cx
    jz .key
    call .erase1
    jmp .key
.erase1:
    dec di
    dec cx
    mov al, 8
    call PutC
    mov al, ' '
    call PutC
    mov al, 8
    call PutC
    ret
.hist:
    test cx, cx
    jz .hcopy
    call .erase1
    jmp .hist
.hcopy:
    mov si, hist
.hc:
    mov al, [si]
    test al, al
    jz .key
    mov [di], al
    inc si
    inc di
    inc cx
    call PutC
    jmp .hc
.enter:
    mov byte [di], 0
    test cx, cx
    jz .nh
    mov si, inbuf
    mov di, hist
    call CopyStr
.nh:
    call PrintNL
    clc
    jmp .out
.cc:
    mov si, msg_ctrlc
    call Print
    mov byte [inbuf], 0
    stc
.out:
    pop di
    pop si
    pop cx
    pop bx
    ret

; ------------------------------------------------------------
; Disk (BIOS int 13h, LBA -> CHS)
; ------------------------------------------------------------
ReadSec:                        ; AX=LBA, ES:BX buffer, CF on error
    mov byte [dop], 2
    jmp DiskIO
WriteSec:
    mov byte [dop], 3
DiskIO:
    push ax
    push bx
    push cx
    push dx
    push si
    mov si, 5
.try:
    push ax
    xor dx, dx
    div word [spt]
    inc dl
    mov cl, dl
    xor dx, dx
    div word [heads]
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah
    mov dl, [bdrive]
    mov ah, [dop]
    mov al, 1
    int 0x13
    pop ax
    jnc .ok
    push ax
    xor ax, ax
    int 0x13
    pop ax
    dec si
    jnz .try
    stc
    jmp .out
.ok:
    clc
.out:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

RdK:                            ; AX=LBA, BX=offset in kernel segment
    push es
    push ds
    pop es
    call ReadSec
    pop es
    ret

WrK:
    push es
    push ds
    pop es
    call WriteSec
    pop es
    ret

; ------------------------------------------------------------
; Mount / FAT12
; ------------------------------------------------------------
MountDrive:
    push ax
    push bx
    push cx
    push dx
    mov byte [dir_ok], 0
    mov byte [fat_ok], 0
    xor ax, ax
    mov bx, secbuf
    call RdK
    jc near .fail
    cmp word [secbuf+510], 0xAA55
    jne near .fail
    cmp word [secbuf+11], 512
    jne near .fail
    xor ah, ah
    mov al, [secbuf+13]
    test al, al
    jz near .fail
    mov [spc], ax
    mov cx, 512
    mul cx
    mov [cluster_bytes], ax
    mov ax, [secbuf+14]
    mov [rsvd], ax
    xor ah, ah
    mov al, [secbuf+16]
    mov [nfats], ax
    mov ax, [secbuf+17]
    mov [rootent], ax
    cmp ax, 224
    ja .fail
    mov ax, [secbuf+19]
    test ax, ax
    jz .fail
    mov [totsec], ax
    mov ax, [secbuf+22]
    mov [spf], ax
    cmp ax, 12
    ja .fail
    test ax, ax
    jz .fail
    mov ax, [secbuf+24]
    test ax, ax
    jz .fail
    mov [spt], ax
    mov ax, [secbuf+26]
    test ax, ax
    jz .fail
    mov [heads], ax
    mov ax, [spf]
    mul word [nfats]
    add ax, [rsvd]
    mov [root_start], ax
    mov bx, [rootent]
    add bx, 15
    shr bx, 4
    mov [root_secs], bx
    add ax, bx
    mov [data_start], ax
    mov bx, ax
    mov ax, [totsec]
    sub ax, bx
    jbe .fail
    xor dx, dx
    div word [spc]
    mov [ncl], ax
    cmp ax, 4085
    jae .fail
    inc ax
    mov [maxcl], ax
    clc
    jmp .out
.fail:
    stc
.out:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

LoadRoot:
    cmp byte [dir_ok], 0
    je .go
    clc
    ret
.go:
    push ax
    push bx
    push cx
    mov ax, [root_start]
    mov bx, dirbuf
    mov cx, [root_secs]
.l:
    call RdK
    jc .err
    inc ax
    add bx, 512
    loop .l
    mov byte [dir_ok], 1
    clc
    jmp .out
.err:
    stc
.out:
    pop cx
    pop bx
    pop ax
    ret

SaveRoot:
    push ax
    push bx
    push cx
    mov ax, [root_start]
    mov bx, dirbuf
    mov cx, [root_secs]
.l:
    call WrK
    jc .err
    inc ax
    add bx, 512
    loop .l
    clc
    jmp .out
.err:
    stc
.out:
    pop cx
    pop bx
    pop ax
    ret

LoadFAT:
    cmp byte [fat_ok], 0
    je .go
    clc
    ret
.go:
    push ax
    push bx
    push cx
    mov ax, [rsvd]
    mov bx, fatbuf
    mov cx, [spf]
.l:
    call RdK
    jc .err
    inc ax
    add bx, 512
    loop .l
    mov byte [fat_ok], 1
    clc
    jmp .out
.err:
    stc
.out:
    pop cx
    pop bx
    pop ax
    ret

FlushFAT:
    pusha
    mov dx, [nfats]
    mov ax, [rsvd]
.copy:
    mov bx, fatbuf
    mov cx, [spf]
    push ax
.l:
    call WrK
    jc .err
    inc ax
    add bx, 512
    loop .l
    pop ax
    add ax, [spf]
    dec dx
    jnz .copy
    popa
    clc
    ret
.err:
    pop ax
    popa
    stc
    ret

GetFAT:                         ; AX=cluster -> AX=value
    push bx
    mov bx, ax
    shr bx, 1
    add bx, ax
    mov bx, [fatbuf+bx]
    test al, 1
    jz .even
    shr bx, 4
.even:
    and bx, 0x0FFF
    mov ax, bx
    pop bx
    ret

SetFAT:                         ; AX=cluster, DX=value
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    shr bx, 1
    add bx, ax
    mov cx, [fatbuf+bx]
    and dx, 0x0FFF
    test al, 1
    jz .even
    and cx, 0x000F
    shl dx, 4
    or cx, dx
    jmp .st
.even:
    and cx, 0xF000
    or cx, dx
.st:
    mov [fatbuf+bx], cx
    pop dx
    pop cx
    pop bx
    pop ax
    ret

AllocCluster:                   ; -> AX, CF=1 if disk full
    push cx
    push dx
    mov cx, 2
.l:
    cmp cx, [maxcl]
    ja .full
    mov ax, cx
    call GetFAT
    test ax, ax
    jz .got
    inc cx
    jmp .l
.got:
    mov ax, cx
    mov dx, 0x0FFF
    call SetFAT
    clc
    jmp .out
.full:
    stc
.out:
    pop dx
    pop cx
    ret

FreeChain:                      ; AX = first cluster
    push ax
    push cx
    push dx
.l:
    cmp ax, 2
    jb .d
    cmp ax, 0x0FF8
    jae .d
    mov cx, ax
    call GetFAT
    push ax
    mov ax, cx
    xor dx, dx
    call SetFAT
    pop ax
    jmp .l
.d:
    pop dx
    pop cx
    pop ax
    ret

CountFree:                      ; -> AX free clusters
    push bx
    push cx
    xor bx, bx
    mov cx, 2
.l:
    cmp cx, [maxcl]
    ja .d
    mov ax, cx
    call GetFAT
    test ax, ax
    jnz .n
    inc bx
.n:
    inc cx
    jmp .l
.d:
    mov ax, bx
    pop cx
    pop bx
    ret

Name11Eq:                       ; [BX] vs [SI], 11 bytes -> ZF=1 equal
    push ax
    push bx
    push cx
    push si
    mov cx, 11
.l:
    mov al, [bx]
    cmp al, [si]
    jne .out
    inc bx
    inc si
    loop .l
    xor al, al
.out:
    pop si
    pop cx
    pop bx
    pop ax
    ret

FindEntry:                      ; SI = name83 -> DI = entry, CF=1 if none
    push ax
    push bx
    push cx
    call LoadRoot
    jc .out
    mov bx, dirbuf
    mov cx, [rootent]
.e:
    mov al, [bx]
    test al, al
    jz .nf
    cmp al, 0xE5
    je .next
    test byte [bx+11], 0x08
    jnz .next
    call Name11Eq
    jne .next
    mov di, bx
    clc
    jmp .out
.next:
    add bx, 32
    loop .e
.nf:
    stc
.out:
    pop cx
    pop bx
    pop ax
    ret

FindFree:                       ; -> DI = free slot, CF=1 if dir full
    push ax
    push bx
    push cx
    call LoadRoot
    jc .out
    mov bx, dirbuf
    mov cx, [rootent]
.l:
    mov al, [bx]
    test al, al
    jz .got
    cmp al, 0xE5
    je .got
    add bx, 32
    loop .l
    stc
    jmp .out
.got:
    mov di, bx
    clc
.out:
    pop cx
    pop bx
    pop ax
    ret

To83:                           ; DS:SI text -> DI (11 bytes); CF=1 if no token
    push ax
    push bx
    push cx
    push di
.sp:
    cmp byte [si], ' '
    jne .st
    inc si
    jmp .sp
.st:
    mov al, [si]
    test al, al
    jz .empty
    mov cx, 11
    mov bx, di
.f:
    mov byte [bx], ' '
    inc bx
    loop .f
    mov cx, 8
    mov bx, di
.nm:
    mov al, [si]
    test al, al
    jz .done
    cmp al, ' '
    je .done
    cmp al, '.'
    je .dot
    inc si
    test cx, cx
    jz .nm
    call UpCase
    mov [bx], al
    inc bx
    dec cx
    jmp .nm
.dot:
    inc si
    lea bx, [di+8]
    mov cx, 3
.ex:
    mov al, [si]
    test al, al
    jz .done
    cmp al, ' '
    je .done
    inc si
    test cx, cx
    jz .ex
    call UpCase
    mov [bx], al
    inc bx
    dec cx
    jmp .ex
.done:
    clc
    jmp .out
.empty:
    stc
.out:
    pop di
    pop cx
    pop bx
    pop ax
    ret

LoadFile:                       ; DI=entry, [xfer_seg:xfer_off], [xfer_max] -> AX=bytes, CF err
    push bx
    push cx
    push dx
    push si
    push di
    push es
    mov ax, [di+28]
    cmp word [di+30], 0
    je .sz
    mov ax, 0xFFFF
.sz:
    cmp ax, [xfer_max]
    jbe .szok
    mov ax, [xfer_max]
.szok:
    mov [lf_size], ax
    mov ax, [di+26]
    mov [lf_clu], ax
    mov ax, [xfer_seg]
    mov es, ax
    mov bx, [xfer_off]
    xor si, si
.cl:
    mov ax, [lf_clu]
    cmp ax, 2
    jb .done
    cmp ax, 0x0FF8
    jae .done
    cmp si, [lf_size]
    jae .done
    sub ax, 2
    mul word [spc]
    add ax, [data_start]
    mov cx, [spc]
.sec:
    call ReadSec
    jc .err
    inc ax
    add bx, 512
    add si, 512
    loop .sec
    mov ax, [lf_clu]
    call GetFAT
    mov [lf_clu], ax
    jmp .cl
.done:
    mov ax, [lf_size]
    clc
    jmp .out
.err:
    stc
.out:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

SaveFile:                       ; SI=name83, DX=size, data at [xfer_seg:xfer_off] -> CF err
    pusha
    push es
    mov [sf_size], dx
    mov [sf_name], si
    call LoadFAT
    jc near .ioerr
    call LoadRoot
    jc near .ioerr
    mov si, [sf_name]
    call FindEntry
    jnc .have
    call FindFree
    jc near .dirfull
    mov si, [sf_name]
    mov bx, di
    mov cx, 11
.cn:
    mov al, [si]
    mov [bx], al
    inc si
    inc bx
    loop .cn
    jmp .init
.have:
    mov ax, [di+26]
    call FreeChain
.init:
    mov [sf_ent], di
    mov byte [di+11], 0x20
    lea bx, [di+12]
    mov cx, 14
.z:
    mov byte [bx], 0
    inc bx
    loop .z
    mov word [di+26], 0
    mov word [di+28], 0
    mov word [di+30], 0
    cmp word [sf_size], 0
    je near .finish
    mov word [sf_prev], 0
    mov word [sf_first], 0
    mov ax, [xfer_off]
    mov [sf_ptr], ax
    mov ax, [sf_size]
    mov [sf_left], ax
    mov ax, [xfer_seg]
    mov es, ax
.alloc:
    call AllocCluster
    jc .full
    mov [sf_cur], ax
    cmp word [sf_prev], 0
    jne .link
    mov [sf_first], ax
    jmp .write
.link:
    mov dx, ax
    mov ax, [sf_prev]
    call SetFAT
.write:
    mov ax, [sf_cur]
    mov [sf_prev], ax
    sub ax, 2
    mul word [spc]
    add ax, [data_start]
    mov cx, [spc]
    mov bx, [sf_ptr]
.ws:
    call WriteSec
    jc .ioerr
    inc ax
    add bx, 512
    loop .ws
    mov [sf_ptr], bx
    mov ax, [sf_left]
    cmp ax, [cluster_bytes]
    jbe .last
    sub ax, [cluster_bytes]
    mov [sf_left], ax
    jmp .alloc
.last:
    mov ax, [sf_first]
    mov di, [sf_ent]
    mov [di+26], ax
    mov ax, [sf_size]
    mov [di+28], ax
.finish:
    call FlushFAT
    jc .ioerr
    call SaveRoot
    jc .ioerr
    pop es
    popa
    clc
    ret
.full:
    mov ax, [sf_first]
    call FreeChain
    call FlushFAT
    call SaveRoot
    mov si, msg_diskfull
    jmp .fail
.dirfull:
    mov si, msg_dirfull
    jmp .fail
.ioerr:
    mov si, msg_diskerr
.fail:
    call Print
    pop es
    popa
    stc
    ret

DeleteFile:                     ; SI=name83 -> CF=1 if not found
    push ax
    push di
    call LoadFAT
    jc .out
    call FindEntry
    jc .out
    mov ax, [di+26]
    call FreeChain
    mov byte [di], 0xE5
    call FlushFAT
    jc .out
    call SaveRoot
.out:
    pop di
    pop ax
    ret

; ------------------------------------------------------------
; Plumbum shell
; ------------------------------------------------------------
shell:
    mov sp, 0xFFF0
    push ds
    pop es
    cld
    sti
    mov al, [bdrive]
    mov bl, 'A'
    test al, al
    jz .pl
    mov bl, 'B'
    cmp al, 1
    je .pl
    mov bl, 'C'
.pl:
    mov al, bl
    call PutC
    mov si, msg_prompt
    call Print
    call ReadLine
    jc shell
    mov si, inbuf
.sk:
    cmp byte [si], ' '
    jne .sk2
    inc si
    jmp .sk
.sk2:
    cmp byte [si], 0
    je shell
    mov di, cmdbuf
    call CopyStr
    mov si, cmdbuf
    call ShellBuiltin
    jnc shell
    mov si, cmdbuf
    call RunSession
    jmp shell

CmdMatch:                       ; SI=line, DI=name -> CF=1 match (SI past args' spaces)
    push si
    push di
.c:
    mov al, [di]
    test al, al
    jz .end
    mov ah, [si]
    cmp ah, 'A'
    jb .cmp
    cmp ah, 'Z'
    ja .cmp
    add ah, 32
.cmp:
    cmp al, ah
    jne .no
    inc si
    inc di
    jmp .c
.end:
    mov al, [si]
    test al, al
    jz .yes
    cmp al, ' '
    jne .no
.yes:
    cmp byte [si], ' '
    jne .set
    inc si
    jmp .yes
.set:
    mov ax, si
    pop di
    add sp, 2
    mov si, ax
    stc
    ret
.no:
    pop di
    pop si
    clc
    ret

ShellBuiltin:                   ; SI=command line -> CF=1 if not a builtin
    push es
    push ds
    pop es
    mov bx, cmd_table
.l:
    mov di, [bx]
    test di, di
    jz .nf
    call CmdMatch
    jc .found
    add bx, 4
    jmp .l
.found:
    mov ax, [bx+2]
    call ax
    pop es
    clc
    ret
.nf:
    pop es
    stc
    ret

disk_err:
    mov si, msg_diskerr
    call Print
    ret
not_found:
    mov si, msg_notfound
    call Print
    ret
need_arg:
    mov si, msg_needarg
    call Print
    ret

; ------------------------------------------------------------
; File commands (SI = arguments, DS=ES=kernel)
; ------------------------------------------------------------
cmd_help:
    cmp byte [si], 'p'
    je .plb
    mov si, msg_help
    call Print
    ret
.plb:
    mov si, msg_plbhelp
    call Print
    ret

cmd_ls:
    call LoadRoot
    jc disk_err
    call LoadFAT
    jc disk_err
    xor ax, ax
    mov [ls_files], ax
    mov [ls_bytes], ax
    mov [ls_bytes+2], ax
    mov byte [ls_col], 0    ; Сброс счетчика колонок
    mov bx, dirbuf
    mov cx, [rootent]
.l:
    mov al, [bx]
    test al, al
    jz .done
    cmp al, 0xE5
    je .next
    test byte [bx+11], 0x08
    jnz .next
    
    ; Печатаем имя (PrintName83 сам добивает пробелами до 14 символов)
    mov si, bx
    call PrintName83
    
    ; Проверяем, папка это или файл
    test byte [bx+11], 0x10
    jz .file
    
    ; Если это папка, просто идем дальше (чтобы не сбить колонки)
    jmp .count_col
.file:
    ; Считаем статистику для файлов
    inc word [ls_files]
    mov ax, [bx+28]
    mov dx, [bx+30]
    add [ls_bytes], ax
    adc [ls_bytes+2], dx
.count_col:
    inc byte [ls_col]
    cmp byte [ls_col], 5    ; 5 колонок по 14 символов = 70 (влезает в 80)
    jb .next
    call PrintNL            ; Переход на новую строку
    mov byte [ls_col], 0    ; Сброс счетчика
.next:
    add bx, 32
    loop .l
.done:
    ; Если в последней строке остались элементы, делаем перенос
    cmp byte [ls_col], 0
    je .summary
    call PrintNL
.summary:
    ; Вывод итоговой статистики (как было)
    mov ax, [ls_files]
    call PrintDec
    mov si, msg_files
    call Print
    mov ax, [ls_bytes]
    mov dx, [ls_bytes+2]
    call PrintDec32
    mov si, msg_bytes
    call Print
    call CountFree
    mul word [cluster_bytes]
    mov cx, 1024
    call Div32by16
    call PrintDec32
    mov si, msg_kbfree
    call Print
    ret

cmd_cat:
    mov di, fn83
    call To83
    jc near need_arg
    mov si, fn83
    call FindEntry
    jc near not_found
    mov ax, SCRATCH
    mov [xfer_seg], ax
    mov word [xfer_off], 0
    mov word [xfer_max], 0xF000
    call LoadFile
    jc near disk_err
    push es
    mov es, [xfer_seg]
    xor bx, bx
    mov cx, ax
    mov dl, 0x0A
.p:
    test cx, cx
    jz .d
    mov al, [es:bx]
    test al, al
    jz .s
    mov dl, al
    call PutC
.s:
    inc bx
    dec cx
    jmp .p
.d:
    pop es
    cmp dl, 0x0A
    je .r
    call PrintNL
.r:
    ret

cmd_cp:
    mov di, fn83
    call To83
    jc .usage
    mov di, fn83b
    call To83
    jc .usage
    mov si, fn83
    call FindEntry
    jc near not_found
    mov ax, SCRATCH
    mov [xfer_seg], ax
    mov word [xfer_off], 0
    mov word [xfer_max], 0xF000
    call LoadFile
    jc near disk_err
    mov dx, ax
    mov si, fn83b
    call SaveFile
    ret
.usage:
    mov si, msg_use_cp
    call Print
    ret

cmd_mv:
    mov di, fn83
    call To83
    jc .usage
    mov di, fn83b
    call To83
    jc .usage
    mov si, fn83b
    call FindEntry
    jnc .exists
    mov si, fn83
    call FindEntry
    jc near not_found
    mov si, fn83b
    mov bx, di
    mov cx, 11
.c:
    mov al, [si]
    mov [bx], al
    inc si
    inc bx
    loop .c
    call SaveRoot
    jc near disk_err
    ret
.exists:
    mov si, msg_exists
    call Print
    ret
.usage:
    mov si, msg_use_mv
    call Print
    ret

cmd_rm:
    mov di, fn83
    call To83
    jc near need_arg
    mov si, fn83
    call DeleteFile
    jc near not_found
    ret

cmd_touch:
    mov di, fn83
    call To83
    jc near need_arg
    mov si, fn83
    call FindEntry
    jnc .r
    xor dx, dx
    mov si, fn83
    call SaveFile
.r:
    ret

cmd_hd:
    mov di, fn83
    call To83
    jc near need_arg
    mov si, fn83
    call FindEntry
    jc near not_found
    mov ax, SCRATCH
    mov [xfer_seg], ax
    mov word [xfer_off], 0
    mov word [xfer_max], 0x1000
    call LoadFile
    jc near disk_err
    cmp ax, 256
    jbe .sz
    mov ax, 256
.sz:
    add ax, 15
    and ax, 0xFFF0
    jz .r
    mov cx, ax
    mov ax, SCRATCH
    mov [hd_seg], ax
    mov word [hd_base], 0
    xor si, si
    call HexDump
.r:
    ret

cmd_sec:
    call StrToInt
    push ax
    mov bx, secbuf
    call RdK
    pop ax
    jc near disk_err
    mov word [hd_base], 0
    mov ax, KSEG
    mov [hd_seg], ax
    mov si, secbuf
    mov cx, 256
    call HexDump
    ret

HexDump:                        ; [hd_seg]:SI, CX bytes (mult of 16)
    pusha
    push es
    mov es, [hd_seg]
.row:
    mov ax, [hd_base]
    call PrintHexW
    mov al, ':'
    call PutC
    mov al, ' '
    call PutC
    push si
    mov dx, 16
.h:
    mov al, [es:si]
    call PrintHexB
    mov al, ' '
    call PutC
    inc si
    dec dx
    jnz .h
    pop si
    mov dx, 16
.a:
    mov al, [es:si]
    cmp al, 32
    jb .dot
    cmp al, 126
    jbe .ok
.dot:
    mov al, '.'
.ok:
    call PutC
    inc si
    dec dx
    jnz .a
    call PrintNL
    add word [hd_base], 16
    sub cx, 16
    jnz .row
    pop es
    popa
    ret

cmd_run:
    mov di, fn83
    call To83
    jc near need_arg
    mov si, fn83
    call FindEntry
    jc near not_found
    mov ax, SCRATCH
    mov [xfer_seg], ax
    mov word [xfer_off], 0
    mov word [xfer_max], 0xF000
    call LoadFile
    jc near disk_err
    push es
    mov ax, SCRATCH
    mov ds, ax
    mov es, ax
    call SCRATCH:0
    mov ax, KSEG
    mov ds, ax
    pop es
    ret

; ------------------------------------------------------------
; Disk utilities
; ------------------------------------------------------------
DriveLetter:                    ; -> AL
    mov al, [bdrive]
    cmp al, 0x80
    jae .c
    add al, 'A'
    ret
.c:
    mov al, 'C'
    ret

PrintKB:                        ; AX clusters -> "N KB"
    push ax
    push bx
    push cx
    push dx
    mul word [cluster_bytes]
    mov cx, 1024
    call Div32by16
    call PrintDec32
    mov si, msg_kb
    call Print
    pop dx
    pop cx
    pop bx
    pop ax
    ret

PrintLn:                        ; SI = label, AX = value, then newline
    call Print
    call PrintDec
    call PrintNL
    ret

cmd_df:
    call LoadFAT
    jc near disk_err
    mov si, msg_drive
    call Print
    call DriveLetter
    call PutC
    mov si, msg_fat12
    call Print
    mov ax, [ncl]
    call PrintKB
    call PrintNL
    mov si, msg_used
    call Print
    call CountFree
    mov bx, ax
    mov ax, [ncl]
    sub ax, bx
    call PrintKB
    mov si, msg_free
    call Print
    mov ax, bx
    call PrintKB
    call PrintNL
    ret

cmd_disk:
    mov si, msg_drive
    call Print
    call DriveLetter
    call PutC
    mov si, msg_biosdrv
    call Print
    mov al, [bdrive]
    call PrintHexB
    mov al, ')'
    call PutC
    call PrintNL
    mov si, msg_d_spt
    mov ax, [spt]
    call PrintLn
    mov si, msg_d_heads
    mov ax, [heads]
    call PrintLn
    mov si, msg_d_total
    mov ax, [totsec]
    call PrintLn
    mov si, msg_d_spc
    mov ax, [spc]
    call PrintLn
    call PrintNL
    mov si, msg_d_fat
    mov ax, [rsvd]
    call PrintLn
    mov si, msg_d_spf
    mov ax, [spf]
    call PrintLn
    mov si, msg_d_root
    mov ax, [root_start]
    call PrintLn
    mov si, msg_d_data
    mov ax, [data_start]
    call PrintLn
    mov si, msg_d_ncl
    mov ax, [ncl]
    call PrintLn
    call PrintNL
    ret

cmd_drive:
    cmp byte [si], 0
    je .show
    mov al, [si]
    or al, 0x20
    mov bl, 0
    cmp al, 'a'
    je .set
    mov bl, 1
    cmp al, 'b'
    je .set
    mov bl, 0x80
    cmp al, 'c'
    je .set
    mov si, msg_use_drive
    call Print
    ret
.set:
    mov al, [bdrive]
    push ax
    mov [bdrive], bl
    call MountDrive
    jnc .ok
    pop ax
    mov [bdrive], al
    call MountDrive
    mov si, msg_mountfail
    call Print
    ret
.ok:
    pop ax
.show:
    mov si, msg_curdrive
    call Print
    call DriveLetter
    call PutC
    mov al, ':'
    call PutC
    call PrintNL
    ret

cmd_format:
    mov byte [fmt_all], 0
    cmp byte [si], '-'
    jne .ask
    mov byte [fmt_all], 1
.ask:
    mov si, msg_fmt_ask
    call Print
    call ReadLine
    jc .no
    mov al, [inbuf]
    or al, 0x20
    cmp al, 'y'
    jne .no
    call LoadFAT
    jc near disk_err
    call LoadRoot
    jc near disk_err
    mov bx, dirbuf
    mov cx, [rootent]
.l:
    mov al, [bx]
    test al, al
    jz .done
    cmp al, 0xE5
    je .next
    test byte [bx+11], 0x08
    jnz .next
    cmp byte [fmt_all], 0
    jne .del
    mov si, sys_name
    call Name11Eq
    je .next
.del:
    mov ax, [bx+26]
    call FreeChain
    mov byte [bx], 0xE5
.next:
    add bx, 32
    loop .l
.done:
    call FlushFAT
    jc near disk_err
    call SaveRoot
    jc near disk_err
    mov si, msg_fmt_done
    call Print
    ret
.no:
    mov si, msg_cancel
    call Print
    ret

cmd_fsck:
    mov byte [fsck_fix], 0
    cmp byte [si], '-'
    jne .go
    mov byte [fsck_fix], 1
.go:
    call LoadFAT
    jc near disk_err
    call LoadRoot
    jc near disk_err
    mov di, fsck_map
    mov cx, 512
.z:
    mov byte [di], 0
    inc di
    loop .z
    xor ax, ax
    mov [fk_files], ax
    mov [fk_err], ax
    mov [fk_lost], ax
    mov bx, dirbuf
    mov cx, [rootent]
.ent:
    mov al, [bx]
    test al, al
    jz .scan
    cmp al, 0xE5
    je .nx
    test byte [bx+11], 0x08
    jnz .nx
    inc word [fk_files]
    mov ax, [bx+26]
.walk:
    cmp ax, 2
    jb .nx
    cmp ax, 0x0FF8
    jae .nx
    cmp ax, [maxcl]
    ja .bad
    call BitTest
    jnz .cross
    call BitSet
    call GetFAT
    jmp .walk
.cross:
    mov si, msg_fk_cross
    jmp .rep
.bad:
    mov si, msg_fk_bad
.rep:
    inc word [fk_err]
    call Print
    push si
    mov si, bx
    call PrintName83
    pop si
    call PrintNL
.nx:
    add bx, 32
    loop .ent
.scan:
    mov cx, 2
.sc:
    cmp cx, [maxcl]
    ja .rep2
    mov ax, cx
    call GetFAT
    test ax, ax
    jz .scn
    mov ax, cx
    call BitTest
    jnz .scn
    inc word [fk_lost]
    cmp byte [fsck_fix], 0
    je .scn
    mov ax, cx
    xor dx, dx
    call SetFAT
.scn:
    inc cx
    jmp .sc
.rep2:
    mov ax, [fk_files]
    mov si, msg_fk_files
    call PrintLn
    mov ax, [fk_err]
    mov si, msg_fk_err
    call PrintLn
    mov ax, [fk_lost]
    mov si, msg_fk_lost
    call PrintLn
    cmp byte [fsck_fix], 0
    je .nl
    cmp word [fk_lost], 0
    je .nl
    call FlushFAT
    mov si, msg_fk_fixed
    call Print
.nl:
    call PrintNL
    ret

BitTest:                        ; AX = cluster -> ZF=0 if marked
    push si
    push cx
    push dx
    mov si, ax
    shr si, 3
    add si, fsck_map
    mov cl, al
    and cl, 7
    mov dl, 1
    shl dl, cl
    test [si], dl
    pop dx
    pop cx
    pop si
    ret

BitSet:
    push si
    push cx
    push dx
    mov si, ax
    shr si, 3
    add si, fsck_map
    mov cl, al
    and cl, 7
    mov dl, 1
    shl dl, cl
    or [si], dl
    pop dx
    pop cx
    pop si
    ret

; ------------------------------------------------------------
; System commands
; ------------------------------------------------------------
cmd_mem:
    mov si, msg_mem1
    call Print
    int 0x12
    call PrintDec
    mov si, msg_mem2
    call Print
    mov ax, MAXTASK
    mov cx, 64
    mul cx
    call PrintDec
    mov si, msg_mem3
    call Print
    ret

cmd_ver:
    mov si, msg_ver
    call Print
    ret

Uptime:                         ; -> DX:AX seconds
    xor ax, ax
    int 0x1A
    sub dx, [boot_t]
    sbb cx, [boot_t+2]
    jnc .ok
    add dx, 0x00B0
    adc cx, 0x0018
.ok:
    mov ax, dx
    mov dx, cx
    mov bx, ax
    mov cx, dx
    shl ax, 1
    rcl dx, 1
    shl ax, 1
    rcl dx, 1
    add ax, bx
    adc dx, cx
    mov cx, 91
    call Div32by16
    ret

PrintUptime:
    pusha
    call Uptime
    mov cx, 3600
    call Div32by16
    call PrintDec32
    mov al, 'h'
    call PutC
    mov al, ' '
    call PutC
    mov ax, bx
    xor dx, dx
    mov cx, 60
    div cx
    call PrintDec
    mov al, 'm'
    call PutC
    mov al, ' '
    call PutC
    mov ax, dx
    call PrintDec
    mov al, 's'
    call PutC
    popa
    ret

cmd_uptime:
    mov si, msg_up
    call Print
    call PrintUptime
    call PrintNL
    ret

cmd_time:
    mov ah, 2
    int 0x1A
    mov al, ch
    call PrintHexB
    mov al, ':'
    call PutC
    mov al, cl
    call PrintHexB
    mov al, ':'
    call PutC
    mov al, dh
    call PrintHexB
    call PrintNL
    ret

cmd_date:
    mov ah, 4
    int 0x1A
    mov al, dl
    call PrintHexB
    mov al, '.'
    call PutC
    mov al, dh
    call PrintHexB
    mov al, '.'
    call PutC
    mov al, ch
    call PrintHexB
    mov al, cl
    call PrintHexB
    call PrintNL
    ret

cmd_echo:
    call Print
    call PrintNL
    ret

cmd_clear:
    mov ax, 0x0003
    int 0x10
    ret

cmd_reboot:
    jmp 0xFFFF:0x0000

cmd_poweroff:
    mov si, msg_bye
    call Print
    mov dx, 0x604
    mov ax, 0x2000
    out dx, ax
    mov dx, 0xB004
    mov ax, 0x2000
    out dx, ax
    mov ax, 0x5301
    xor bx, bx
    int 0x15
    mov ax, 0x5307
    mov bx, 1
    mov cx, 3
    int 0x15
    cli
.h:
    hlt
    jmp .h

cmd_sysfetch:
    mov si, msg_fetch_logo
    call Print
    mov si, msg_f_os
    call Print
    mov si, msg_f_kern
    call Print
    mov si, msg_f_up
    call Print
    call PrintUptime
    call PrintNL
    mov si, msg_f_mem
    call Print
    int 0x12
    call PrintDec
    mov si, msg_kb
    call Print
    call PrintNL
    mov si, msg_f_disk
    call Print
    call DriveLetter
    call PutC
    mov si, msg_f_colon
    call Print
    call PrintNL
    mov si, msg_f_tasks
    call Print
    xor dl, dl
    mov cl, 1
.t:
    mov al, cl
    call TaskPtr
    cmp byte [bx+TK_STATE], 0
    je .n
    inc dl
.n:
    inc cl
    cmp cl, MAXTASK
    jb .t
    mov al, dl
    xor ah, ah
    call PrintDec
    call PrintNL
    call PrintNL
    ret

; ------------------------------------------------------------
; Tasks and scheduler
; ------------------------------------------------------------
TaskPtr:                        ; AL = slot -> BX = task struct
    push ax
    xor ah, ah
    mov bx, ax
    shl bx, 5
    add bx, tasks
    pop ax
    ret

CurTask:                        ; -> BX (preserves AX)
    push ax
    mov al, [cur_task]
    call TaskPtr
    pop ax
    ret

GetTicks:                       ; -> AX low word of BIOS ticks
    push cx
    push dx
    xor ax, ax
    int 0x1A
    mov ax, dx
    pop dx
    pop cx
    ret

ZeroVars:                       ; AX = task segment
    push es
    push di
    push cx
    push ax
    mov es, ax
    mov di, T_VARS
    mov cx, T_VARN*T_VARSZ/2
    xor ax, ax
    rep stosw
    pop ax
    pop cx
    pop di
    pop es
    ret

SchedTick:                      ; -> AL = number of tasks that ran
    push bx
    push cx
    push dx
    call GetTicks
    mov [nowt], ax
    xor dx, dx
    mov cl, 1
.n:
    mov al, cl
    call TaskPtr
    mov al, [bx+TK_STATE]
    cmp al, ST_READY
    je .run
    cmp al, ST_SLEEP
    jne .skip
    mov ax, [nowt]
    sub ax, [bx+TK_START]
    cmp ax, [bx+TK_DUR]
    jb .skip
    mov byte [bx+TK_STATE], ST_READY
.run:
    test byte [bx+TK_FLAGS], F_RUN
    jnz .skip
    mov al, cl
    call RunSlice
    inc dl
.skip:
    inc cl
    cmp cl, MAXTASK
    jb .n
    mov al, dl
    pop dx
    pop cx
    pop bx
    ret

RunSlice:                       ; AL = slot ; executes up to SLICE statements
    pusha
    push es
    push word [cur_task]
    push word [cur_line]
    push word [slice_sp]
    mov [slice_sp], sp
    mov [cur_task], al
    mov cx, SLICE
    test al, al
    jnz .go
    mov cx, 1
.go:
    call CurTask
    or byte [bx+TK_FLAGS], F_RUN
    mov es, [bx+TK_SEG]
.loop:
    call CurTask
    cmp byte [bx+TK_STATE], ST_READY
    jne SliceExit
    mov si, [bx+TK_PC]
    cmp byte [es:si], 0
    je .eof
    push cx
    call ExecLine
    pop cx
    dec cx
    jnz .loop
    jmp SliceExit
.eof:
    call TaskExit
SliceExit:
    mov sp, [slice_sp]
    call CurTask
    and byte [bx+TK_FLAGS], 0xFF-F_RUN
    cmp byte [bx+TK_STATE], ST_DEAD
    jne .a
    mov byte [bx+TK_STATE], ST_FREE
.a:
    pop word [slice_sp]
    pop word [cur_line]
    pop word [cur_task]
    pop es
    popa
    ret

TaskExit:
    cmp byte [cur_task], 0
    je .r
    call CurTask
    mov byte [bx+TK_STATE], ST_FREE
.r:
    ret

KillTask:                       ; AL = slot -> CF=1 if no such task
    push bx
    call TaskPtr
    cmp byte [bx+TK_STATE], ST_FREE
    je .no
    test byte [bx+TK_FLAGS], F_RUN
    jnz .dead
    mov byte [bx+TK_STATE], ST_FREE
    jmp .ok
.dead:
    mov byte [bx+TK_STATE], ST_DEAD
.ok:
    clc
    pop bx
    ret
.no:
    stc
    pop bx
    ret

WaitTask:                       ; AL = slot, wait until it finishes (Ctrl+C kills)
    push ax
    push bx
    push si
    mov [wt_slot], al
.l:
    call SchedTick
    mov [wt_ran], al
    mov al, [wt_slot]
    call TaskPtr
    cmp byte [bx+TK_STATE], ST_FREE
    je .done
    mov ah, 1
    int 0x16
    jz .nokey
    cmp al, 3
    jne .nokey
    xor ah, ah
    int 0x16
    mov si, msg_ctrlc
    call Print
    mov al, [wt_slot]
    call KillTask
    jmp .done
.nokey:
    cmp byte [wt_ran], 0
    jne .l
    sti
    hlt
    jmp .l
.done:
    pop si
    pop bx
    pop ax
    ret

StartTask:                      ; fn83 = file, [bgflag] -> AL = slot, CF=1 on error
    push bx
    push cx
    push dx
    push si
    push di
    call LoadRoot
    jc near .ioerr
    mov si, fn83
    call FindEntry
    jc near .nf
    mov cl, 1
.f:
    mov al, cl
    call TaskPtr
    cmp byte [bx+TK_STATE], ST_FREE
    je .got
    inc cl
    cmp cl, MAXTASK
    jb .f
    mov si, msg_notask
    jmp .err
.got:
    mov [st_slot], cl
    mov ax, [bx+TK_SEG]
    mov [xfer_seg], ax
    mov word [xfer_off], 0
    mov word [xfer_max], T_TEXTMAX
    call LoadFile
    jc .ioerr
    push es
    mov es, [xfer_seg]
    mov bx, ax
    mov byte [es:bx], 0
    pop es
    mov ax, [xfer_seg]
    call ZeroVars
    mov al, [st_slot]
    call TaskPtr
    mov byte [bx+TK_STATE], ST_READY
    mov byte [bx+TK_FLAGS], F_FG
    cmp byte [bgflag], 0
    je .fg
    mov byte [bx+TK_FLAGS], 0
.fg:
    mov word [bx+TK_PC], 0
    mov word [bx+TK_CSP], T_CTL
    lea di, [bx+TK_NAME]
    mov si, fn83
    mov cx, 11
.nc:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    loop .nc
    mov byte [di], 0
    mov al, [st_slot]
    clc
    jmp .out
.nf:
    mov si, msg_notfound
    jmp .err
.ioerr:
    mov si, msg_diskerr
.err:
    call Print
    stc
.out:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

RunSession:                     ; SI = statement line (DS)
    push es
    mov ax, TSEG0
    mov es, ax
    xor di, di
.c:
    mov al, [si]
    mov [es:di], al
    inc si
    inc di
    test al, al
    jnz .c
    mov word [tasks+TK_PC], 0
    mov word [tasks+TK_CSP], T_CTL
    mov byte [tasks+TK_STATE], ST_READY
    pop es
    xor al, al
    call RunSlice
    ret

cmd_plb:
    mov di, fn83
    call To83
    jc near need_arg
    cmp byte [fn83+8], ' '
    jne .ext
    mov byte [fn83+8], 'P'
    mov byte [fn83+9], 'L'
    mov byte [fn83+10], 'B'
.ext:
    cmp byte [si], ' '
    jne .a
    inc si
    jmp .ext
.a:
    mov byte [bgflag], 0
    cmp byte [si], '&'
    jne .go
    mov byte [bgflag], 1
.go:
    call StartTask
    jc .r
    cmp byte [bgflag], 0
    jne .bg
    call WaitTask
    ret
.bg:
    mov si, msg_started
    call Print
    xor ah, ah
    call PrintDec
    call PrintNL
.r:
    ret

cmd_ps:
    mov si, msg_ps_hdr
    call Print
    mov cl, 1
.l:
    mov al, cl
    call TaskPtr
    mov al, [bx+TK_STATE]
    test al, al
    jz .n
    push ax
    mov al, cl
    xor ah, ah
    call PrintDec
    mov al, ' '
    call PutC
    mov al, ' '
    call PutC
    mov al, ' '
    call PutC
    pop ax
    mov si, ps_run
    cmp al, ST_READY
    je .st
    mov si, ps_sleep
    cmp al, ST_SLEEP
    je .st
    mov si, ps_dead
.st:
    call Print
    mov si, ps_fg
    test byte [bx+TK_FLAGS], F_FG
    jnz .m
    mov si, ps_bg
.m:
    call Print
    lea si, [bx+TK_NAME]
    call PrintName83
    call PrintNL
.n:
    inc cl
    cmp cl, MAXTASK
    jb .l
    ret

cmd_kill:
    cmp byte [si], 0
    je near need_arg
    call StrToInt
    cmp ax, 1
    jl .bad
    cmp ax, MAXTASK-1
    jg .bad
    call KillTask
    jc .bad
    mov si, msg_killed
    call Print
    ret
.bad:
    mov si, msg_notask2
    call Print
    ret

cmd_killall:
    mov cl, 1
.l:
    mov al, cl
    call KillTask
    inc cl
    cmp cl, MAXTASK
    jb .l
    mov si, msg_killed
    call Print
    ret

cmd_fg:
    cmp byte [si], 0
    je near need_arg
    call StrToInt
    cmp ax, 1
    jl .bad
    cmp ax, MAXTASK-1
    jg .bad
    call TaskPtr
    cmp byte [bx+TK_STATE], ST_FREE
    je .bad
    or byte [bx+TK_FLAGS], F_FG
    call WaitTask
    ret
.bad:
    mov si, msg_notask2
    call Print
    ret

; ------------------------------------------------------------
; Plumbum interpreter    (DS = kernel, ES = task segment)
; ------------------------------------------------------------
SkipWs:                         ; ES:SI, only SI changes
    push ax
.l:
    mov al, [es:si]
    cmp al, ' '
    je .s
    cmp al, 9
    je .s
    cmp al, 13
    je .s
    pop ax
    ret
.s:
    inc si
    jmp .l

IsIdCh:                         ; AL -> CF=1 if [A-Za-z0-9_]
    cmp al, '_'
    je .y
    cmp al, '0'
    jb .n
    cmp al, '9'
    jbe .y
    cmp al, 'A'
    jb .n
    cmp al, 'Z'
    jbe .y
    cmp al, 'a'
    jb .n
    cmp al, 'z'
    jbe .y
.n:
    clc
    ret
.y:
    stc
    ret

GetIdent:                       ; ES:SI -> DI (12 bytes, lowercase), CX = chars read
    push ax
    push bx
    push di
    mov byte [id_dollar], 0
    mov cx, 12
    xor al, al
.z:
    mov [di], al
    inc di
    loop .z
    pop di
    push di
    xor cx, cx
.n:
    mov al, [es:si]
    call IsIdCh
    jnc .e
    cmp al, 'A'
    jb .st
    cmp al, 'Z'
    ja .st
    add al, 32
.st:
    cmp cx, 10
    jae .sk
    mov bx, cx
    mov [di+bx], al
.sk:
    inc cx
    inc si
    jmp .n
.e:
    test cx, cx
    jz .r
    cmp byte [es:si], '$'
    jne .r
    inc si
    mov bx, cx
    cmp bx, 10
    jbe .p
    mov bx, 10
.p:
    mov byte [di+bx], '$'
    mov byte [id_dollar], 1
.r:
    pop di
    pop bx
    pop ax
    ret

StrEqSI_DI:                     ; DS:SI vs DS:DI asciiz -> ZF=1 equal
.l:
    mov al, [si]
    cmp al, [di]
    jne .r
    test al, al
    jz .r
    inc si
    inc di
    jmp .l
.r:
    ret

IdEq:                           ; idbuf2 == [DI] ? ZF
    push si
    push di
    mov si, idbuf2
    call StrEqSI_DI
    pop di
    pop si
    ret

TryWord:                        ; DI = lowercase word ; ES:SI -> CF=1 + SI advanced if matched
    push ax
    push bx
    push si
    push di
.l:
    mov al, [di]
    test al, al
    jz .end
    mov ah, [es:si]
    cmp ah, 'A'
    jb .c
    cmp ah, 'Z'
    ja .c
    add ah, 32
.c:
    cmp al, ah
    jne .no
    inc di
    inc si
    jmp .l
.end:
    mov al, [es:si]
    call IsIdCh
    jc .no
    mov [tw_si], si
    pop di
    pop si
    pop bx
    pop ax
    mov si, [tw_si]
    stc
    ret
.no:
    pop di
    pop si
    pop bx
    pop ax
    clc
    ret

FindVar:                        ; idbuf -> ES:DI = variable entry (created if new)
    push ax
    push bx
    push cx
    push dx
    push si
    mov bx, T_VARS
    mov dx, T_VARN
.l:
    mov si, idbuf
    mov di, bx
    mov cx, 12
    repe cmpsb
    je .f
    cmp byte [es:bx], 0
    je .c
    add bx, T_VARSZ
    dec dx
    jnz .l
    mov dx, msg_toomany
    jmp RunError
.c:
    mov si, idbuf
    mov di, bx
    mov cx, 12
.cp:
    mov al, [si]
    mov [es:di], al
    inc si
    inc di
    loop .cp
    mov word [es:bx+12], 0
    mov byte [es:bx+14], 0
.f:
    mov di, bx
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

LineNext:                       ; SI -> start of next line (or NUL)
    push ax
.l:
    mov al, [es:si]
    test al, al
    jz .d
    inc si
    cmp al, 0x0A
    jne .l
.d:
    pop ax
    ret

SetPC:                          ; SI = new pc
    push bx
    call CurTask
    mov [bx+TK_PC], si
    pop bx
    ret

ExecLine:                       ; SI = line start
    mov [cur_line], si
    push si
.s:
    mov al, [es:si]
    test al, al
    jz .e
    inc si
    cmp al, 0x0A
    jne .s
.e:
    call CurTask
    mov [bx+TK_PC], si
    pop si

ExecStmt:                       ; SI = parse position
    call SkipWs
    mov al, [es:si]
    test al, al
    jz .r
    cmp al, 0x0A
    je .r
    cmp al, '#'
    je .r
    mov [stmt_start], si
    mov di, idbuf
    call GetIdent
    test cx, cx
    jz .fb
    cmp byte [es:si], ':'
    je .r
    cmp byte [id_dollar], 0
    jne .asg
    mov bx, kw_table
.k:
    mov di, [bx]
    test di, di
    jz .asg
    push si
    mov si, idbuf
    call StrEqSI_DI
    pop si
    je .hit
    add bx, 4
    jmp .k
.hit:
    mov ax, [bx+2]
    call ax
.r:
    ret
.asg:
    call DoAssign
    jnc .r
.fb:
    mov si, [stmt_start]
    mov di, cmdbuf
    mov cx, 126
.cp:
    mov al, [es:si]
    test al, al
    jz .ce
    cmp al, 0x0A
    je .ce
    cmp al, 13
    je .ce
    mov [di], al
    inc si
    inc di
    loop .cp
.ce:
    mov byte [di], 0
    mov si, cmdbuf
    call ShellBuiltin
    jnc .r
    mov dx, msg_unknown
    jmp RunError

DoAssign:                       ; after ident: CF=1 if this is not an assignment
    push si
    call SkipWs
    mov al, [es:si]
    mov ah, [es:si+1]
    cmp al, '='
    jne .cmpd
    cmp ah, '='
    je near .no
    inc si
    mov byte [as_op], 0
    jmp .go
.cmpd:
    cmp ah, '='
    jne near .no
    mov byte [as_op], 1
    cmp al, '+'
    je .op
    mov byte [as_op], 2
    cmp al, '-'
    je .op
    mov byte [as_op], 3
    cmp al, '*'
    jne .no
.op:
    add si, 2
.go:
    add sp, 2
    mov al, [id_dollar]
    mov [as_str], al
    call FindVar
    push di
    cmp byte [as_str], 0
    jne .str
    call ParseOr
    pop di
    mov bl, [as_op]
    cmp bl, 0
    je .set
    cmp bl, 1
    je .add
    cmp bl, 2
    je .sub
    imul word [es:di+12]
    mov [es:di+12], ax
    jmp .ok
.set:
    mov [es:di+12], ax
    jmp .ok
.add:
    add [es:di+12], ax
    jmp .ok
.sub:
    sub [es:di+12], ax
    jmp .ok
.str:
    cmp byte [as_op], 0
    jne .syn
    mov di, strbuf
    call EvalStr
    pop di
    mov bx, strbuf
    add di, 14
    mov cx, 63
.cs:
    mov al, [bx]
    mov [es:di], al
    test al, al
    jz .ok
    inc bx
    inc di
    loop .cs
    mov byte [es:di], 0
.ok:
    clc
    ret
.no:
    pop si
    stc
    ret
.syn:
    jmp ErrSyntax

ErrSyntax:
    mov dx, msg_syntax
RunError:                       ; DX = message ; aborts the current task/statement
    mov sp, [slice_sp]
    push dx
    mov si, msg_err_pre
    call Print
    pop si
    call Print
    cmp byte [cur_task], 0
    je .nl
    mov si, msg_atline
    call Print
    call CurTask
    mov es, [bx+TK_SEG]
    call CountLine
    call PrintDec
.nl:
    call PrintNL
    call TaskExit
    jmp SliceExit

CountLine:                      ; -> AX line number of cur_line
    push bx
    push si
    mov si, [cur_line]
    xor ax, ax
    xor bx, bx
.l:
    cmp bx, si
    jae .d
    cmp byte [es:bx], 0x0A
    jne .n
    inc ax
.n:
    inc bx
    jmp .l
.d:
    inc ax
    pop si
    pop bx
    ret

; ---- control stack: entries of 10 bytes (type,a,b,c,d) ----
CtlPush:                        ; AX = type -> BX = entry (ES:BX)
    push cx
    push di
    mov cx, ax
    call CurTask
    mov di, [bx+TK_CSP]
    cmp di, T_CTLEND
    jae .full
    mov [es:di], cx
    add word [bx+TK_CSP], 10
    mov bx, di
    pop di
    pop cx
    ret
.full:
    mov dx, msg_ctlfull
    jmp RunError

CtlTop:                         ; -> BX = top entry (ES:BX)
    push ax
    call CurTask
    mov ax, [bx+TK_CSP]
    cmp ax, T_CTL
    jbe .empty
    sub ax, 10
    mov bx, ax
    pop ax
    ret
.empty:
    mov dx, msg_noblock
    jmp RunError

CtlPop:
    push bx
    call CurTask
    sub word [bx+TK_CSP], 10
    pop bx
    ret

HasThen:                        ; ES:SI -> CF=1 if the line has a ' then' word
    push ax
    push bx
    mov bx, si
.l:
    mov al, [es:bx]
    test al, al
    jz .no
    cmp al, 0x0A
    je .no
    cmp al, '#'
    je .no
    mov ah, al
    or ah, 0x20
    cmp ah, 't'
    jne .n
    cmp byte [es:bx-1], ' '
    jne .n
    mov ax, [es:bx]
    or ax, 0x2020
    cmp ax, 0x6874
    jne .n
    mov ax, [es:bx+2]
    or ax, 0x2020
    cmp ax, 0x6E65
    jne .n
    mov al, [es:bx+4]
    call IsIdCh
    jc .n
    stc
    jmp .out
.n:
    inc bx
    jmp .l
.no:
    clc
.out:
    pop bx
    pop ax
    ret

SkipBlock:                      ; SI=line start, BX=depth, DL=1: stop at else -> SI=stop line, AL=1 if else
.line:
    cmp byte [es:si], 0
    je .eof
    push si
    call SkipWs
    push bx
    mov di, idbuf2
    call GetIdent
    pop bx
    mov di, w_end
    call IdEq
    je .isend
    mov di, w_else
    call IdEq
    je .iselse
    mov di, w_while
    call IdEq
    je .open
    mov di, w_for
    call IdEq
    je .open
    mov di, w_if
    call IdEq
    jne .next
    call HasThen
    jc .next
.open:
    inc bx
    jmp .next
.isend:
    test bx, bx
    jz .found0
    dec bx
    jmp .next
.iselse:
    test bx, bx
    jnz .next
    test dl, dl
    jz .next
    pop si
    mov al, 1
    ret
.found0:
    pop si
    xor al, al
    ret
.next:
    pop si
    call LineNext
    jmp .line
.eof:
    mov dx, msg_noend
    jmp RunError

FindLabel:                      ; idbuf -> SI = line after label, CF=1 if missing
    xor si, si
.l:
    cmp byte [es:si], 0
    je .no
    push si
    call SkipWs
    mov di, idbuf2
    call GetIdent
    test cx, cx
    jz .n
    cmp byte [es:si], ':'
    jne .n
    push si
    mov si, idbuf
    mov di, idbuf2
    call StrEqSI_DI
    pop si
    je .yes
.n:
    pop si
    call LineNext
    jmp .l
.yes:
    add sp, 2
    call LineNext
    clc
    ret
.no:
    stc
    ret

; ---- expressions -------------------------------------------
ParseOr:
    call ParseAnd
.l:
    call SkipWs
    mov di, w_or
    call TryWord
    jnc .r
    push ax
    call ParseAnd
    pop bx
    test bx, bx
    jnz .t
    test ax, ax
    jz .f
.t:
    mov ax, 1
    jmp .l
.f:
    xor ax, ax
    jmp .l
.r:
    ret

ParseAnd:
    call ParseCmp
.l:
    call SkipWs
    mov di, w_and
    call TryWord
    jnc .r
    push ax
    call ParseCmp
    pop bx
    test bx, bx
    jz .f
    test ax, ax
    jz .f
    mov ax, 1
    jmp .l
.f:
    xor ax, ax
    jmp .l
.r:
    ret

ParseCmp:
    call SkipWs
    call IsStrStart
    jc near .str
    call ParseAdd
    call SkipWs
    mov dx, [es:si]
    mov cl, 1
    mov ch, 2
    cmp dx, 0x3D3D
    je .have
    mov cl, 2
    cmp dx, 0x3D21
    je .have
    cmp dx, 0x3E3C
    je .have
    mov cl, 3
    cmp dx, 0x3D3C
    je .have
    mov cl, 4
    cmp dx, 0x3D3E
    je .have
    mov ch, 1
    mov cl, 5
    cmp dl, '<'
    je .have
    mov cl, 6
    cmp dl, '>'
    je .have
    ret
.have:
    mov bl, ch
    xor bh, bh
    add si, bx
    push ax
    push cx
    call ParseAdd
    mov bx, ax
    pop cx
    pop ax
    cmp cl, 1
    jne .n2
    cmp ax, bx
    je .true
    jmp .false
.n2:
    cmp cl, 2
    jne .n3
    cmp ax, bx
    jne .true
    jmp .false
.n3:
    cmp cl, 3
    jne .n4
    cmp ax, bx
    jle .true
    jmp .false
.n4:
    cmp cl, 4
    jne .n5
    cmp ax, bx
    jge .true
    jmp .false
.n5:
    cmp cl, 5
    jne .n6
    cmp ax, bx
    jl .true
    jmp .false
.n6:
    cmp ax, bx
    jg .true
.false:
    xor ax, ax
    ret
.true:
    mov ax, 1
    ret
.str:
    sub sp, 512
    mov bx, sp
    mov di, sp
    call EvalStr
    call SkipWs
    mov dx, [es:si]
    mov cl, 1
    cmp dx, 0x3D3D
    je .sop
    mov cl, 0
    cmp dx, 0x3D21
    jne near ErrSyntax
.sop:
    add si, 2
    push cx
    mov di, bx
    add di, 256
    push bx
    call EvalStr
    pop bx
    pop cx
    push si
    mov si, bx
    mov di, bx
    add di, 256
    call StrEqSI_DI
    pop si
    mov ax, 0
    jne .sne
    mov ax, 1
.sne:
    test cl, cl
    jnz .sd
    xor ax, 1
.sd:
    add sp, 512
    ret

ParseAdd:
    call ParseMul
.l:
    call SkipWs
    mov bl, [es:si]
    cmp bl, '+'
    je .add
    cmp bl, '-'
    je .sub
    ret
.add:
    inc si
    push ax
    call ParseMul
    pop bx
    add ax, bx
    jmp .l
.sub:
    inc si
    push ax
    call ParseMul
    mov bx, ax
    pop ax
    sub ax, bx
    jmp .l

ParseMul:
    call ParseUnary
.l:
    call SkipWs
    mov bl, [es:si]
    cmp bl, '*'
    je .mul
    cmp bl, '/'
    je .div
    cmp bl, '%'
    je .mod
    ret
.mul:
    inc si
    push ax
    call ParseUnary
    pop bx
    imul bx
    jmp .l
.div:
    inc si
    push ax
    call ParseUnary
    mov bx, ax
    pop ax
    test bx, bx
    jz .dz
    cwd
    idiv bx
    jmp .l
.mod:
    inc si
    push ax
    call ParseUnary
    mov bx, ax
    pop ax
    test bx, bx
    jz .dz
    cwd
    idiv bx
    mov ax, dx
    jmp .l
.dz:
    mov dx, msg_divzero
    jmp RunError

ParseUnary:
    call SkipWs
    mov al, [es:si]
    cmp al, '-'
    jne .p
    inc si
    call ParseUnary
    neg ax
    ret
.p:
    cmp al, '+'
    jne .n
    inc si
    jmp ParseUnary
.n:
    mov di, w_not
    call TryWord
    jnc ParsePrimary
    call ParseUnary
    test ax, ax
    jz .one
    xor ax, ax
    ret
.one:
    mov ax, 1
    ret

ParsePrimary:
    call SkipWs
    mov al, [es:si]
    cmp al, '('
    jne .p1
    inc si
    call ParseOr
    call SkipWs
    cmp byte [es:si], ')'
    jne .syn
    inc si
    ret
.p1:
    cmp al, '0'
    jb .p2
    cmp al, '9'
    ja .p2
    jmp ParseNumber
.p2:
    cmp al, 0x27
    jne .id
    inc si
    mov al, [es:si]
    xor ah, ah
    inc si
    cmp byte [es:si], 0x27
    jne .syn
    inc si
    ret
.id:
    mov di, idbuf
    call GetIdent
    test cx, cx
    jz .syn
    cmp byte [id_dollar], 0
    jne .syn
    cmp byte [es:si], '('
    je .func
    call FindVar
    mov ax, [es:di+12]
    ret
.func:
    inc si
    mov bx, fn_table
.f:
    mov di, [bx]
    test di, di
    jz .unk
    push si
    mov si, idbuf
    call StrEqSI_DI
    pop si
    je .call
    add bx, 4
    jmp .f
.call:
    mov ax, [bx+2]
    call ax
    call SkipWs
    cmp byte [es:si], ')'
    jne .syn
    inc si
    ret
.unk:
    mov dx, msg_unkfunc
    jmp RunError
.syn:
    jmp ErrSyntax

ParseNumber:                    ; ES:SI -> AX
    xor bx, bx
    mov al, [es:si]
    cmp al, '0'
    jne .dec
    mov al, [es:si+1]
    or al, 0x20
    cmp al, 'x'
    jne .dec
    add si, 2
.hx:
    mov al, [es:si]
    cmp al, '0'
    jb .done
    cmp al, '9'
    jbe .hd
    or al, 0x20
    cmp al, 'a'
    jb .done
    cmp al, 'f'
    ja .done
    sub al, 'a'-10
    jmp .hadd
.hd:
    sub al, '0'
.hadd:
    shl bx, 4
    xor ah, ah
    or bx, ax
    inc si
    jmp .hx
.dec:
    mov al, [es:si]
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done
    sub al, '0'
    xor ah, ah
    mov dx, ax
    mov ax, bx
    shl ax, 1
    mov cx, ax
    shl ax, 2
    add ax, cx
    add ax, dx
    mov bx, ax
    inc si
    jmp .dec
.done:
    mov ax, bx
    ret

; ---- string expressions ------------------------------------
IsStrStart:                     ; ES:SI -> CF=1 if a string expression starts here
    push ax
    push bx
    push cx
    push si
    push di
    mov al, [es:si]
    cmp al, '"'
    je .yes
    call IsIdCh
    jnc .no
    cmp al, '0'
    jb .go
    cmp al, '9'
    jbe .no
.go:
    mov di, idbuf2
    call GetIdent
    cmp byte [id_dollar], 0
    jne .yes
    cmp byte [es:si], '('
    jne .no
    mov bx, sfn_table
.f:
    mov di, [bx]
    test di, di
    jz .no
    call IdEq
    je .yes
    add bx, 4
    jmp .f
.yes:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    stc
    ret
.no:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    clc
    ret

EvalStr:                        ; ES:SI -> DS:DI asciiz (max 250), AX = length
    push bx
    push cx
    push dx
    push di
    mov bx, di
    xor cx, cx
.atom:
    call SkipWs
    mov al, [es:si]
    cmp al, '"'
    je near .lit
    push bx
    push cx
    mov di, idbuf
    call GetIdent
    test cx, cx
    pop cx
    pop bx
    jz near .syn
    cmp byte [id_dollar], 0
    je .fn
    push bx
    push cx
    call FindVar
    mov dx, di
    pop cx
    pop bx
    mov di, dx
    add di, 14
.cv:
    mov al, [es:di]
    test al, al
    jz near .after
    cmp cx, 250
    jae near .after
    mov [bx], al
    inc bx
    inc cx
    inc di
    jmp .cv
.fn:
    cmp byte [es:si], '('
    jne near .syn
    inc si
    push bx
    push cx
    mov bx, sfn_table
.ff:
    mov di, [bx]
    test di, di
    jz near .unk
    push si
    mov si, idbuf
    call StrEqSI_DI
    pop si
    je .fcall
    add bx, 4
    jmp .ff
.fcall:
    mov ax, [bx+2]
    call ax
    call SkipWs
    cmp byte [es:si], ')'
    jne .syn
    inc si
    pop cx
    pop bx
    mov di, fbuf
.fc:
    mov al, [di]
    test al, al
    jz .after
    cmp cx, 250
    jae .after
    mov [bx], al
    inc bx
    inc cx
    inc di
    jmp .fc
.lit:
    inc si
.ll:
    mov al, [es:si]
    test al, al
    jz .syn
    cmp al, 0x0A
    je .syn
    inc si
    cmp al, '"'
    je .after
    cmp al, 0x5C
    jne .put
    mov al, [es:si]
    inc si
    cmp al, 'n'
    jne .t1
    mov al, 0x0A
    jmp .put
.t1:
    cmp al, 't'
    jne .put
    mov al, 9
.put:
    cmp cx, 250
    jae .ll
    mov [bx], al
    inc bx
    inc cx
    jmp .ll
.after:
    call SkipWs
    cmp byte [es:si], '+'
    jne .end
    inc si
    jmp .atom
.end:
    mov byte [bx], 0
    mov ax, cx
    pop di
    pop dx
    pop cx
    pop bx
    ret
.unk:
    mov dx, msg_unkfunc
    jmp RunError
.syn:
    jmp ErrSyntax

; ---- string functions: SI after '(' ; result in fbuf --------
sf_chr:
    call ParseOr
    mov [fbuf], al
    mov byte [fbuf+1], 0
    ret

sf_str:
    call ParseOr
    mov di, fbuf
    test ax, ax
    jns .p
    mov byte [di], '-'
    inc di
    neg ax
.p:
    xor dx, dx
    call NumToStr
    push si
    mov si, numbuf
.c:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    test al, al
    jnz .c
    pop si
    ret

sf_mid:
    sub sp, 256
    mov di, sp
    call EvalStr
    call SkipWs
    cmp byte [es:si], ','
    jne .syn
    inc si
    call ParseOr
    push ax
    call SkipWs
    cmp byte [es:si], ','
    jne .syn
    inc si
    call ParseOr
    mov cx, ax
    pop ax
    mov bx, sp
    dec ax
.adv:
    test ax, ax
    jle .cp
    cmp byte [bx], 0
    je .cp
    inc bx
    dec ax
    jmp .adv
.cp:
    mov di, fbuf
.c:
    test cx, cx
    jle .end
    mov al, [bx]
    test al, al
    jz .end
    mov [di], al
    inc bx
    inc di
    dec cx
    jmp .c
.end:
    mov byte [di], 0
    add sp, 256
    ret
.syn:
    jmp ErrSyntax

; ---- numeric functions: SI after '(' ; result in AX ---------
f_len:
    sub sp, 256
    mov di, sp
    call EvalStr
    add sp, 256
    ret

f_asc:
    sub sp, 256
    mov di, sp
    call EvalStr
    mov bx, sp
    mov al, [bx]
    xor ah, ah
    add sp, 256
    ret

f_val:
    sub sp, 256
    mov di, sp
    call EvalStr
    mov bx, sp
    push si
    mov si, bx
    call StrToInt
    pop si
    add sp, 256
    ret

f_exists:
    sub sp, 256
    mov di, sp
    call EvalStr
    mov bx, sp
    push si
    mov si, bx
    mov di, fn83
    call To83
    mov si, fn83
    call FindEntry
    pop si
    mov ax, 0
    jc .r
    mov ax, 1
.r:
    add sp, 256
    ret

f_rnd:
    call ParseOr
    mov bx, ax
    mov ax, [seed]
    mov dx, 25173
    mul dx
    add ax, 13849
    mov [seed], ax
    test bx, bx
    jle .z
    xor dx, dx
    div bx
    mov ax, dx
    ret
.z:
    xor ax, ax
    ret

f_abs:
    call ParseOr
    test ax, ax
    jns .r
    neg ax
.r:
    ret

f_ticks:
    call GetTicks
    ret

f_key:
    call CurTask
    xor ax, ax
    test byte [bx+TK_FLAGS], F_FG
    jz .r
    mov ah, 1
    int 0x16
    jz .r0
    xor ah, ah
    int 0x16
    test al, al
    jz .ext
    xor ah, ah
    ret
.ext:
    mov al, ah
    xor ah, ah
    add ax, 256
    ret
.r0:
    xor ax, ax
.r:
    ret

; ---- statements ---------------------------------------------
st_rem:
    ret

st_print:
    mov byte [pr_nl], 1
.item:
    call SkipWs
    mov al, [es:si]
    test al, al
    jz .end
    cmp al, 0x0A
    je .end
    cmp al, '#'
    je .end
    call IsStrStart
    jnc .num
    mov di, printbuf
    call EvalStr
    push si
    mov si, printbuf
    call Print
    pop si
    jmp .sep
.num:
    call ParseOr
    call PrintSDec
.sep:
    call SkipWs
    mov al, [es:si]
    cmp al, ','
    jne .semi
    inc si
    jmp .item
.semi:
    cmp al, ';'
    jne .end
    inc si
    mov byte [pr_nl], 0
.end:
    cmp byte [pr_nl], 0
    je .r
    call PrintNL
.r:
    ret

st_input:
    call SkipWs
    cmp byte [es:si], '"'
    jne .var
    mov di, strbuf
    call EvalStr
    push si
    mov si, strbuf
    call Print
    pop si
    call SkipWs
    cmp byte [es:si], ','
    jne .syn
    inc si
    call SkipWs
.var:
    mov di, idbuf
    call GetIdent
    test cx, cx
    jz .syn
    mov al, [id_dollar]
    push ax
    call FindVar
    push di
    call CurTask
    test byte [bx+TK_FLAGS], F_FG
    jz .nofg
    push es
    push ds
    pop es
    call ReadLine
    pop es
    jc .brk
    jmp .got
.nofg:
    mov byte [inbuf], 0
.got:
    pop di
    pop ax
    test al, al
    jz .int
    mov bx, inbuf
    add di, 14
    mov cx, 63
.c:
    mov al, [bx]
    mov [es:di], al
    test al, al
    jz .d
    inc bx
    inc di
    loop .c
    mov byte [es:di], 0
.d:
    ret
.int:
    push di
    mov si, inbuf
    call StrToInt
    pop di
    mov [es:di+12], ax
    ret
.brk:
    mov dx, msg_intr
    jmp RunError
.syn:
    jmp ErrSyntax

st_let:
    call SkipWs
    mov di, idbuf
    call GetIdent
    test cx, cx
    jz .syn
    call DoAssign
    jc .syn
    ret
.syn:
    jmp ErrSyntax

st_if:
    call ParseOr
    push ax
    call SkipWs
    mov di, w_then
    call TryWord
    jnc .block
    pop ax
    test ax, ax
    jz .r
    jmp ExecStmt
.r:
    ret
.block:
    pop ax
    test ax, ax
    jz .false
    mov ax, K_IF
    call CtlPush
    ret
.false:
    call CurTask
    mov si, [bx+TK_PC]
    xor bx, bx
    mov dl, 1
    call SkipBlock
    push ax
    call LineNext
    call SetPC
    pop ax
    test al, al
    jz .r
    mov ax, K_IF
    call CtlPush
    ret

st_else:
    call CtlTop
    cmp word [es:bx], K_IF
    jne .err
    call CtlPop
    call CurTask
    mov si, [bx+TK_PC]
    xor bx, bx
    xor dl, dl
    call SkipBlock
    call LineNext
    call SetPC
    ret
.err:
    mov dx, msg_noblock
    jmp RunError

st_while:
    mov ax, [cur_line]
    push ax
    call ParseOr
    mov dx, ax
    pop cx
    test dx, dx
    jz .false
    mov ax, K_WHILE
    call CtlPush
    mov [es:bx+2], cx
    ret
.false:
    call CurTask
    mov si, [bx+TK_PC]
    xor bx, bx
    xor dl, dl
    call SkipBlock
    call LineNext
    call SetPC
    ret

st_for:
    call SkipWs
    mov di, idbuf
    call GetIdent
    test cx, cx
    jz near .syn
    cmp byte [id_dollar], 0
    jne near .syn
    call FindVar
    push di
    call SkipWs
    cmp byte [es:si], '='
    jne .syn
    inc si
    call ParseOr
    pop di
    mov [es:di+12], ax
    push di
    call SkipWs
    mov di, w_to
    call TryWord
    jnc .syn
    call ParseOr
    push ax
    mov word [for_step], 1
    call SkipWs
    mov di, w_step
    call TryWord
    jnc .nostep
    call ParseOr
    mov [for_step], ax
.nostep:
    pop bx
    pop di
    mov ax, [es:di+12]
    mov dx, [for_step]
    test dx, dx
    js .neg
    cmp ax, bx
    jg .skip
    jmp .enter
.neg:
    cmp ax, bx
    jl .skip
.enter:
    mov cx, bx
    call CurTask
    mov dx, [bx+TK_PC]
    mov ax, K_FOR
    call CtlPush
    mov [es:bx+2], di
    mov [es:bx+4], cx
    mov ax, [for_step]
    mov [es:bx+6], ax
    mov [es:bx+8], dx
    ret
.skip:
    call CurTask
    mov si, [bx+TK_PC]
    xor bx, bx
    xor dl, dl
    call SkipBlock
    call LineNext
    call SetPC
    ret
.syn:
    jmp ErrSyntax

st_end:
    call CtlTop
    mov ax, [es:bx]
    cmp ax, K_IF
    je .pop
    cmp ax, K_WHILE
    je .while
    cmp ax, K_FOR
    je .for
    mov dx, msg_noblock
    jmp RunError
.pop:
    call CtlPop
    ret
.while:
    mov si, [es:bx+2]
    call CtlPop
    call SetPC
    ret
.for:
    mov di, [es:bx+2]
    mov ax, [es:di+12]
    add ax, [es:bx+6]
    mov [es:di+12], ax
    mov cx, [es:bx+6]
    test cx, cx
    js .neg
    cmp ax, [es:bx+4]
    jg .done
    jmp .again
.neg:
    cmp ax, [es:bx+4]
    jl .done
.again:
    mov si, [es:bx+8]
    call SetPC
    ret
.done:
    call CtlPop
    ret

st_break:
    xor cx, cx
.l:
    call CtlTop
    mov ax, [es:bx]
    cmp ax, K_WHILE
    je .loop
    cmp ax, K_FOR
    je .loop
    cmp ax, K_IF
    jne .err
    call CtlPop
    inc cx
    jmp .l
.loop:
    call CtlPop
    call CurTask
    mov si, [bx+TK_PC]
    mov bx, cx
    xor dl, dl
    call SkipBlock
    call LineNext
    call SetPC
    ret
.err:
    mov dx, msg_noloop
    jmp RunError

st_continue:
    xor cx, cx
.l:
    call CtlTop
    mov ax, [es:bx]
    cmp ax, K_WHILE
    je .loop
    cmp ax, K_FOR
    je .loop
    cmp ax, K_IF
    jne .err
    call CtlPop
    inc cx
    jmp .l
.loop:
    call CurTask
    mov si, [bx+TK_PC]
    mov bx, cx
    xor dl, dl
    call SkipBlock
    call SetPC
    ret
.err:
    mov dx, msg_noloop
    jmp RunError

st_goto:
    call SkipWs
    mov di, idbuf
    call GetIdent
    test cx, cx
    jz .syn
    call FindLabel
    jc .nl
    call SetPC
    ret
.nl:
    mov dx, msg_nolabel
    jmp RunError
.syn:
    jmp ErrSyntax

st_gosub:
    call SkipWs
    mov di, idbuf
    call GetIdent
    test cx, cx
    jz .syn
    call FindLabel
    jc .nl
    push si
    call CurTask
    mov dx, [bx+TK_PC]
    mov ax, K_GOSUB
    call CtlPush
    mov [es:bx+2], dx
    pop si
    call SetPC
    ret
.nl:
    mov dx, msg_nolabel
    jmp RunError
.syn:
    jmp ErrSyntax

st_return:
    call CtlTop
    cmp word [es:bx], K_GOSUB
    je .got
    call CtlPop
    jmp st_return
.got:
    mov si, [es:bx+2]
    call CtlPop
    call SetPC
    ret

st_stop:
    jmp TaskExit

st_cls:
    mov ax, 0x0003
    int 0x10
    ret

st_sleep:
    call ParseOr
    mov cx, 18
    imul cx
    mov dx, ax
    cmp byte [cur_task], 0
    jne .task
    call GetTicks
    mov cx, ax
.w:
    call GetTicks
    sub ax, cx
    cmp ax, dx
    jae .d
    push cx
    push dx
    call SchedTick
    pop dx
    pop cx
    test al, al
    jnz .w
    sti
    hlt
    jmp .w
.d:
    ret
.task:
    call GetTicks
    call CurTask
    mov [bx+TK_START], ax
    mov [bx+TK_DUR], dx
    mov byte [bx+TK_STATE], ST_SLEEP
    ret

st_save:
    mov di, strbuf
    call EvalStr
    call SkipWs
    cmp byte [es:si], ','
    jne .syn
    inc si
    mov di, printbuf
    call EvalStr
    mov dx, ax
    mov si, strbuf
    mov di, fn83
    call To83
    jc .syn
    mov si, printbuf
    mov di, T_TMP
    mov cx, dx
.c:
    test cx, cx
    jz .w
    mov al, [si]
    mov [es:di], al
    inc si
    inc di
    dec cx
    jmp .c
.w:
    mov ax, es
    mov [xfer_seg], ax
    mov word [xfer_off], T_TMP
    mov si, fn83
    call SaveFile
    ret
.syn:
    jmp ErrSyntax

st_load:
    call SkipWs
    mov di, idbuf
    call GetIdent
    test cx, cx
    jz .syn
    cmp byte [id_dollar], 0
    je .syn
    call FindVar
    push di
    call SkipWs
    cmp byte [es:si], ','
    jne .syn
    inc si
    mov di, strbuf
    call EvalStr
    mov si, strbuf
    mov di, fn83
    call To83
    jc .empty
    mov si, fn83
    call FindEntry
    jc .empty
    mov ax, es
    mov [xfer_seg], ax
    mov word [xfer_off], T_TMP
    mov word [xfer_max], 512
    call LoadFile
    jc .empty
    mov cx, ax
    pop di
    add di, 14
    mov si, T_TMP
    xor bx, bx
.c:
    test cx, cx
    jz .e
    mov al, [es:si]
    cmp al, 0x0A
    je .e
    cmp al, 13
    je .e
    cmp bx, 63
    jae .e
    mov [es:di], al
    inc si
    inc di
    inc bx
    dec cx
    jmp .c
.e:
    mov byte [es:di], 0
    ret
.empty:
    pop di
    mov byte [es:di+14], 0
    ret
.syn:
    jmp ErrSyntax

; ---- tables ---------------------------------------------------
kw_table:
    dw k_print, st_print
    dw k_input, st_input
    dw w_if, st_if
    dw w_else, st_else
    dw w_while, st_while
    dw w_for, st_for
    dw w_end, st_end
    dw k_break, st_break
    dw k_continue, st_continue
    dw k_goto, st_goto
    dw k_gosub, st_gosub
    dw k_return, st_return
    dw k_let, st_let
    dw k_sleep, st_sleep
    dw k_stop, st_stop
    dw k_exit, st_stop
    dw k_cls, st_cls
    dw k_save, st_save
    dw k_load, st_load
    dw k_rem, st_rem
    dw 0

fn_table:
    dw k_len, f_len
    dw k_asc, f_asc
    dw k_val, f_val
    dw k_rnd, f_rnd
    dw k_abs, f_abs
    dw k_ticks, f_ticks
    dw k_key, f_key
    dw k_exists, f_exists
    dw 0

sfn_table:
    dw k_chr, sf_chr
    dw k_str, sf_str
    dw k_mid, sf_mid
    dw 0

w_or        db "or", 0
w_and       db "and", 0
w_not       db "not", 0
w_then      db "then", 0
w_to        db "to", 0
w_step      db "step", 0
w_if        db "if", 0
w_else      db "else", 0
w_while     db "while", 0
w_for       db "for", 0
w_end       db "end", 0
k_print     db "print", 0
k_input     db "input", 0
k_break     db "break", 0
k_continue  db "continue", 0
k_goto      db "goto", 0
k_gosub     db "gosub", 0
k_return    db "return", 0
k_let       db "let", 0
k_sleep     db "sleep", 0
k_stop      db "stop", 0
k_exit      db "exit", 0
k_cls       db "cls", 0
k_save      db "save", 0
k_load      db "load", 0
k_rem       db "rem", 0
k_len       db "len", 0
k_asc       db "asc", 0
k_val       db "val", 0
k_rnd       db "rnd", 0
k_abs       db "abs", 0
k_ticks     db "ticks", 0
k_key       db "key", 0
k_exists    db "exists", 0
k_chr       db "chr", 0
k_str       db "str", 0
k_mid       db "mid", 0

; ------------------------------------------------------------
; Pulsar editor (buffer at EDSEG:0, direct video via FS)
; ------------------------------------------------------------
EDMAX       equ 0x6F00

cmd_edit:
    mov di, fn83
    call To83
    jc near need_arg
    mov si, fn83
    mov di, ed_name
    mov cx, 11
.cn:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    loop .cn
    mov si, ed_name
    mov di, ed_nametxt
    call Name83Text
    mov ax, EDSEG
    mov es, ax
    mov word [ed_len], 0
    mov byte [es:0], 0
    mov si, ed_name
    call FindEntry
    jc .go
    mov ax, EDSEG
    mov [xfer_seg], ax
    mov word [xfer_off], 0
    mov word [xfer_max], EDMAX
    call LoadFile
    jc near disk_err
    mov bx, ax
    mov byte [es:bx], 0
    call EdStripCR
.go:
    xor ax, ax
    mov [ed_cur], ax
    mov [ed_top], ax
    mov [ed_left], ax
    mov [ed_msg], ax
    mov byte [ed_mod], 0
    mov ax, VIDEO
    mov fs, ax
    mov ax, 0x0003
    int 0x10
    call EdLoop
    mov ax, 0x0003
    int 0x10
    ret

EdStripCR:
    push si
    push di
    xor si, si
    xor di, di
.l:
    mov al, [es:si]
    test al, al
    jz .d
    inc si
    cmp al, 13
    je .l
    mov [es:di], al
    inc di
    jmp .l
.d:
    mov byte [es:di], 0
    mov [ed_len], di
    pop di
    pop si
    ret

EdLineStart:                    ; AX offset -> AX start of its line
    push si
    mov si, ax
.l:
    test si, si
    jz .d
    cmp byte [es:si-1], 0x0A
    je .d
    dec si
    jmp .l
.d:
    mov ax, si
    pop si
    ret

EdLineEnd:                      ; AX offset -> AX offset of LF/NUL ending the line
    push si
    mov si, ax
.l:
    mov al, [es:si]
    test al, al
    jz .d
    cmp al, 0x0A
    je .d
    inc si
    jmp .l
.d:
    mov ax, si
    pop si
    ret

EdFixView:
    push ax
    push bx
    push cx
    push si
    mov ax, [ed_cur]
    cmp ax, [ed_top]
    jae .again
    call EdLineStart
    mov [ed_top], ax
.again:
    mov si, [ed_top]
    mov bx, [ed_cur]
    xor cx, cx
.cnt:
    cmp si, bx
    jae .cd
    cmp byte [es:si], 0x0A
    jne .n
    inc cx
.n:
    inc si
    jmp .cnt
.cd:
    cmp cx, 23
    jb .rowok
    mov ax, [ed_top]
    call EdLineEnd
    inc ax
    mov [ed_top], ax
    jmp .again
.rowok:
    mov [ed_row], cx
    mov ax, [ed_cur]
    call EdLineStart
    mov bx, [ed_cur]
    sub bx, ax
    mov [ed_col], bx
    mov ax, [ed_left]
    cmp bx, ax
    jae .h1
    mov [ed_left], bx
    jmp .h2
.h1:
    mov cx, ax
    add cx, 80
    cmp bx, cx
    jb .h2
    mov ax, bx
    sub ax, 79
    mov [ed_left], ax
.h2:
    xor cx, cx
    xor si, si
    mov bx, [ed_cur]
.ln:
    cmp si, bx
    jae .ld
    cmp byte [es:si], 0x0A
    jne .l2
    inc cx
.l2:
    inc si
    jmp .ln
.ld:
    inc cx
    mov [ed_line], cx
    pop si
    pop cx
    pop bx
    pop ax
    ret

VStr:                           ; SI string, DI video offset, AH attribute
    push ax
.l:
    mov al, [si]
    test al, al
    jz .d
    mov [fs:di], ax
    add di, 2
    inc si
    jmp .l
.d:
    pop ax
    ret

EdDraw:
    pusha
    call EdFixView
    xor di, di
    mov ax, 0x7020
    mov cx, 80
.t:
    mov [fs:di], ax
    add di, 2
    loop .t
    mov di, 2
    mov ah, 0x70
    mov si, msg_ed_title
    call VStr
    mov si, ed_nametxt
    call VStr
    cmp byte [ed_mod], 0
    je .nomod
    mov si, msg_ed_mod
    call VStr
.nomod:
    mov di, 120
    mov si, msg_ed_ln
    call VStr
    mov ax, [ed_line]
    xor dx, dx
    call NumToStr
    mov si, numbuf
    mov ah, 0x70
    call VStr
    mov si, msg_ed_col
    call VStr
    mov ax, [ed_col]
    inc ax
    xor dx, dx
    call NumToStr
    mov si, numbuf
    mov ah, 0x70
    call VStr
    mov si, [ed_top]
    mov bx, 1
.row:
    mov ax, 160
    mul bx
    mov di, ax
    mov cx, [ed_left]
.sk:
    test cx, cx
    jz .st
    mov al, [es:si]
    test al, al
    jz .st
    cmp al, 0x0A
    je .st
    inc si
    dec cx
    jmp .sk
.st:
    mov cx, 80
.ch:
    mov al, ' '
    mov dl, [es:si]
    test dl, dl
    jz .put
    cmp dl, 0x0A
    je .put
    mov al, dl
    inc si
.put:
    mov ah, 0x07
    mov [fs:di], ax
    add di, 2
    loop .ch
.skl:
    mov dl, [es:si]
    test dl, dl
    jz .nx
    inc si
    cmp dl, 0x0A
    jne .skl
.nx:
    inc bx
    cmp bx, 24
    jb .row
    mov di, 24*160
    mov ax, 0x7020
    mov cx, 80
.b:
    mov [fs:di], ax
    add di, 2
    loop .b
    mov di, 24*160+2
    mov ah, 0x70
    mov si, [ed_msg]
    test si, si
    jnz .m
    mov si, msg_ed_help
.m:
    call VStr
    mov word [ed_msg], 0
    mov dh, [ed_row]
    inc dh
    mov ax, [ed_col]
    sub ax, [ed_left]
    mov dl, al
    mov ah, 2
    xor bh, bh
    int 0x10
    popa
    ret

EdInsert:                       ; AL = char
    push bx
    push si
    mov bx, [ed_len]
    cmp bx, EDMAX
    jae .r
    mov si, bx
.sh:
    mov ah, [es:si]
    mov [es:si+1], ah
    cmp si, [ed_cur]
    je .ins
    dec si
    jmp .sh
.ins:
    mov si, [ed_cur]
    mov [es:si], al
    inc word [ed_cur]
    inc word [ed_len]
    mov byte [ed_mod], 1
.r:
    pop si
    pop bx
    ret

EdDelete:                       ; delete char under cursor
    push si
    push ax
    mov si, [ed_cur]
    cmp si, [ed_len]
    jae .r
.l:
    mov al, [es:si+1]
    mov [es:si], al
    inc si
    test al, al
    jnz .l
    dec word [ed_len]
    mov byte [ed_mod], 1
.r:
    pop ax
    pop si
    ret

EdUp:
    mov ax, [ed_cur]
    call EdLineStart
    mov bx, ax
    mov cx, [ed_cur]
    sub cx, bx
    test bx, bx
    jz .r
    mov ax, bx
    dec ax
    mov dx, ax
    call EdLineStart
    mov bx, dx
    sub bx, ax
    cmp cx, bx
    jbe .c
    mov cx, bx
.c:
    add ax, cx
    mov [ed_cur], ax
.r:
    ret

EdDown:
    mov ax, [ed_cur]
    call EdLineStart
    mov cx, [ed_cur]
    sub cx, ax
    mov ax, [ed_cur]
    call EdLineEnd
    mov si, ax
    cmp byte [es:si], 0
    je .r
    inc ax
    mov dx, ax
    call EdLineEnd
    sub ax, dx
    cmp cx, ax
    jbe .c
    mov cx, ax
.c:
    add dx, cx
    mov [ed_cur], dx
.r:
    ret

EdSave:
    pusha
    mov ax, EDSEG
    mov [xfer_seg], ax
    mov word [xfer_off], 0
    mov dx, [ed_len]
    mov si, ed_name
    call SaveFile
    jc .e
    mov byte [ed_mod], 0
    mov word [ed_msg], msg_ed_saved
    jmp .r
.e:
    mov word [ed_msg], msg_ed_fail
.r:
    popa
    ret

EdLoop:
.draw:
    call EdDraw
.key:
    call GetKey
    test al, al
    jnz .ascii
    cmp ah, 0x48
    je .up
    cmp ah, 0x50
    je .down
    cmp ah, 0x4B
    je .left
    cmp ah, 0x4D
    je .right
    cmp ah, 0x47
    je .home
    cmp ah, 0x4F
    je .end
    cmp ah, 0x49
    je near .pgup
    cmp ah, 0x51
    je near .pgdn
    cmp ah, 0x53
    je near .del
    cmp ah, 0x3C
    je near .save
    jmp .key
.ascii:
    cmp al, 27
    je near .esc
    cmp al, 0x13
    je near .save
    cmp al, 8
    je .bs
    cmp al, 13
    je near .enter
    cmp al, 9
    je near .tab
    cmp al, 32
    jb .key
    cmp al, 126
    ja .key
    call EdInsert
    jmp .draw
.up:
    call EdUp
    jmp .draw
.down:
    call EdDown
    jmp .draw
.left:
    cmp word [ed_cur], 0
    je .draw
    dec word [ed_cur]
    jmp .draw
.right:
    mov ax, [ed_cur]
    cmp ax, [ed_len]
    jae near .draw
    inc word [ed_cur]
    jmp .draw
.home:
    mov ax, [ed_cur]
    call EdLineStart
    mov [ed_cur], ax
    jmp .draw
.end:
    mov ax, [ed_cur]
    call EdLineEnd
    mov [ed_cur], ax
    jmp .draw
.pgup:
    mov cx, 20
.pu:
    push cx
    call EdUp
    pop cx
    loop .pu
    jmp .draw
.pgdn:
    mov cx, 20
.pd:
    push cx
    call EdDown
    pop cx
    loop .pd
    jmp .draw
.del:
    call EdDelete
    jmp .draw
.bs:
    cmp word [ed_cur], 0
    je near .draw
    dec word [ed_cur]
    call EdDelete
    jmp .draw
.enter:
    mov al, 0x0A
    call EdInsert
    jmp .draw
.tab:
    mov cx, 4
.tb:
    push cx
    mov al, ' '
    call EdInsert
    pop cx
    loop .tb
    jmp .draw
.save:
    call EdSave
    jmp .draw
.esc:
    cmp byte [ed_mod], 0
    je .exit
    mov word [ed_msg], msg_ed_ask
    call EdDraw
    call GetKey
    or al, 0x20
    cmp al, 'y'
    je .sy
    cmp al, 'n'
    je .exit
    jmp .draw
.sy:
    call EdSave
    cmp byte [ed_mod], 0
    jne near .draw
.exit:
    ret

; ------------------------------------------------------------
; Command table
; ------------------------------------------------------------
cmd_table:
    dw n_help, cmd_help
    dw n_ls, cmd_ls
    dw n_dir, cmd_ls
    dw n_cat, cmd_cat
    dw n_type, cmd_cat
    dw n_cp, cmd_cp
    dw n_copy, cmd_cp
    dw n_mv, cmd_mv
    dw n_ren, cmd_mv
    dw n_rm, cmd_rm
    dw n_del, cmd_rm
    dw n_touch, cmd_touch
    dw n_edit, cmd_edit
    dw n_pulsar, cmd_edit
    dw n_plb, cmd_plb
    dw n_run, cmd_run
    dw n_ps, cmd_ps
    dw n_kill, cmd_kill
    dw n_killall, cmd_killall
    dw n_fg, cmd_fg
    dw n_df, cmd_df
    dw n_disk, cmd_disk
    dw n_drive, cmd_drive
    dw n_format, cmd_format
    dw n_fsck, cmd_fsck
    dw n_sec, cmd_sec
    dw n_hd, cmd_hd
    dw n_mem, cmd_mem
    dw n_ver, cmd_ver
    dw n_sysfetch, cmd_sysfetch
    dw n_neofetch, cmd_sysfetch
    dw n_time, cmd_time
    dw n_date, cmd_date
    dw n_uptime, cmd_uptime
    dw n_echo, cmd_echo
    dw n_clear, cmd_clear
    dw n_reboot, cmd_reboot
    dw n_poweroff, cmd_poweroff
    dw n_shutdown, cmd_poweroff
    dw 0

n_help      db "help", 0
n_ls        db "ls", 0
n_dir       db "dir", 0
n_cat       db "cat", 0
n_type      db "type", 0
n_cp        db "cp", 0
n_copy      db "copy", 0
n_mv        db "mv", 0
n_ren       db "ren", 0
n_rm        db "rm", 0
n_del       db "del", 0
n_touch     db "touch", 0
n_edit      db "edit", 0
n_pulsar    db "pulsar", 0
n_plb       db "plb", 0
n_run       db "run", 0
n_ps        db "ps", 0
n_kill      db "kill", 0
n_killall   db "killall", 0
n_fg        db "fg", 0
n_df        db "df", 0
n_disk      db "disk", 0
n_drive     db "drive", 0
n_format    db "format", 0
n_fsck      db "fsck", 0
n_sec       db "sec", 0
n_hd        db "hd", 0
n_mem       db "mem", 0
n_ver       db "ver", 0
n_sysfetch  db "sysfetch", 0
n_neofetch  db "neofetch", 0
n_time      db "time", 0
n_date      db "date", 0
n_uptime    db "uptime", 0
n_echo      db "echo", 0
n_clear     db "clear", 0
n_reboot    db "reboot", 0
n_poweroff  db "poweroff", 0
n_shutdown  db "shutdown", 0

; ------------------------------------------------------------
; Messages
; ------------------------------------------------------------
auto_name   db "AUTOEXECPLB"
sys_name    db "KERNEL  BIN"
auto_cmd    db "plb AUTOEXEC.PLB", 0

msg_banner  db 10
            db "  ___ ___ _                  ___  ___", 10
            db " / __| _ \ |_  ___ _ _ __ _ / _ \/ __|", 10
            db " \__ \  _/ ' \/ -_) '_/ _` | (_) \__ \", 10
            db " |___/_| |_||_\___|_| \__,_|\___/|___/  v3.0", 10
            db 10
            db " Plumbum shell + PLB language. Type 'help'.", 10, 10, 0
msg_nomount db "No FAT12 filesystem found on this drive.", 10, 0
msg_prompt  db ":\> ", 0
msg_ctrlc   db "^C", 10, 0
msg_diskerr db "Disk error.", 10, 0
msg_diskfull db "Disk full.", 10, 0
msg_dirfull db "Root directory is full.", 10, 0
msg_notfound db "File not found.", 10, 0
msg_needarg db "Missing argument.", 10, 0
msg_exists  db "Target already exists.", 10, 0
msg_use_cp  db "Usage: cp SOURCE DEST", 10, 0
msg_use_mv  db "Usage: mv OLD NEW", 10, 0
msg_use_drive db "Usage: drive a|b|c", 10, 0
msg_dirtag  db "<DIR>", 10, 0
msg_files   db " file(s), ", 0
msg_bytes   db " bytes, ", 0
msg_kbfree  db " KB free", 10, 0
msg_kb      db " KB", 0
msg_drive   db "Drive ", 0
msg_fat12   db ": FAT12, total ", 0
msg_used    db "  used: ", 0
msg_free    db "  free: ", 0
msg_biosdrv db ": (BIOS drive 0x", 0
msg_d_spt   db "  sectors/track : ", 0
msg_d_heads db "  heads         : ", 0
msg_d_total db "  total sectors : ", 0
msg_d_spc   db "  sect/cluster  : ", 0
msg_d_fat   db "  FAT starts at : ", 0
msg_d_spf   db "  sectors/FAT   : ", 0
msg_d_root  db "  root dir at   : ", 0
msg_d_data  db "  data area at  : ", 0
msg_d_ncl   db "  clusters      : ", 0
msg_mountfail db "Cannot mount that drive.", 10, 0
msg_curdrive db "Current drive: ", 0
msg_fmt_ask db "Delete ALL files (KERNEL.BIN is kept unless 'format -all')? [y/N] ", 0
msg_fmt_done db "Done.", 10, 0
msg_cancel  db "Cancelled.", 10, 0
msg_fk_cross db "Cross-linked file: ", 0
msg_fk_bad  db "Bad cluster in file: ", 0
msg_fk_files db "Files checked    : ", 0
msg_fk_err  db "Errors found     : ", 0
msg_fk_lost db "Lost clusters    : ", 0
msg_fk_fixed db "Lost clusters were freed.", 10, 0
msg_mem1    db "Conventional memory: ", 0
msg_mem2    db " KB", 10, "Task memory reserved: ", 0
msg_mem3    db " KB", 10, 0
msg_ver     db "SpheraOS 3.0 - Plumbum shell, PLB interpreter, FAT12, multitasking", 10, 0
msg_up      db "up ", 0
msg_bye     db "Powering off...", 10, 0
msg_notask  db "No free task slots (kill something).", 10, 0
msg_notask2 db "No such task.", 10, 0
msg_started db "[started] pid ", 0
msg_killed  db "Killed.", 10, 0
msg_ps_hdr  db "PID  STATE  MODE NAME", 10, 0
ps_run      db "run    ", 0
ps_sleep    db "sleep  ", 0
ps_dead     db "dying  ", 0
ps_fg       db "fg   ", 0
ps_bg       db "bg   ", 0

msg_fetch_logo db 10
            db "   .-''''-.      ", 0
msg_f_os    db "SpheraOS 3.0", 10
            db "  /  .--.  \     ", 0
msg_f_kern  db "Shell: Plumbum  Lang: PLB", 10
            db " |  (    )  |    ", 0
msg_f_up    db "Uptime: ", 0
msg_f_mem   db "  \  '--'  /     Memory: ", 0
msg_f_disk  db "   '-....-'      Drive : ", 0
msg_f_colon db ":  FAT12", 0
msg_f_tasks db "                 Tasks : ", 0

msg_err_pre db "plb error: ", 0
msg_atline  db " at line ", 0
msg_syntax  db "syntax error", 0
msg_unknown db "unknown command or statement", 0
msg_toomany db "too many variables", 0
msg_ctlfull db "blocks nested too deep", 0
msg_noblock db "unexpected end/else/return", 0
msg_noend   db "missing end", 0
msg_noloop  db "break/continue outside loop", 0
msg_nolabel db "label not found", 0
msg_divzero db "division by zero", 0
msg_unkfunc db "unknown function", 0
msg_intr    db "interrupted", 0

msg_ed_title db "Pulsar | ", 0
msg_ed_mod  db " [modified]", 0
msg_ed_ln   db "Ln ", 0
msg_ed_col  db "  Col ", 0
msg_ed_help db "F2/Ctrl+S Save   ESC Exit   Arrows Home End PgUp PgDn Del", 0
msg_ed_saved db "File saved.", 0
msg_ed_fail db "SAVE FAILED!", 0
msg_ed_ask  db "Unsaved changes. Save before exit? (y = save, n = discard, other = back)", 0

msg_help    db "SpheraOS commands:", 10
            db " files : ls cat cp mv rm touch edit hd run", 10
            db " tasks : plb FILE [&]   ps   kill N   killall   fg N", 10
            db " disk  : df disk drive a|b|c format [-all] fsck [-f] sec N", 10
            db " system: mem uptime time date ver sysfetch clear echo", 10
            db "         reboot poweroff", 10
            db 10
            db "Plumbum is also a language: type statements right here:", 10
            db "   x = 6 * 7        print x        for i = 1 to 3", 10
            db "Scripts are .plb files: edit hello.plb, then plb hello.plb", 10
            db "Add '&' to run a script in the background.", 10
            db "'help plb' shows the language reference.", 10, 0

msg_plbhelp db "Plumbum (PLB) language", 10
            db " x = 5   s$ = ", '"hi"', "   x += 1      ints and strings (name$)", 10
            db " print a, ", '"text"', ", s$;       ; at the end = no newline", 10
            db " input ", '"Name? "', ", n$      read a line (int var parses a number)", 10
            db " if c [then stmt] / else / end    while c ... end", 10
            db " for i = 1 to 9 [step 2] ... end  break  continue", 10
            db " goto L   L:   gosub L   return   stop   sleep SEC   cls", 10
            db " save ", '"f"', ", s$      load s$, ", '"f"', "      tiny file I/O", 10
            db " ops: + - * / %  == != < > <= >=  and or not ( )", 10
            db " funcs: len asc val rnd(n) abs ticks() key() exists(", '"f"', ")", 10
            db "        chr(n) str(n) mid(s$, start, count)", 10
            db " comments: # ...      shell commands work in scripts too", 10
            db " run: plb file.plb      background: plb file.plb &", 10, 0

; ------------------------------------------------------------
; End of code. Build fails here if the kernel outgrows 40 KB.
; ------------------------------------------------------------
times 0xA000-($-$$) db 0

; ------------------------------------------------------------
; BSS (not stored in the file). 0xA000-0xA7FF is cleared at boot.
; ------------------------------------------------------------
absolute 0xA000
bss_start:
bdrive      resb 1
dir_ok      resb 1
fat_ok      resb 1
dop         resb 1
pr_nl       resb 1
id_dollar   resb 1
as_op       resb 1
as_str      resb 1
fsck_fix    resb 1
fmt_all     resb 1
bgflag      resb 1
st_slot     resb 1
wt_slot     resb 1
wt_ran      resb 1
ed_mod      resb 1
bss_pad     resb 1
cur_task    resw 1
cur_line    resw 1
slice_sp    resw 1
stmt_start  resw 1
tw_si       resw 1
for_step    resw 1
nowt        resw 1
seed        resw 1
boot_t      resw 2
spc         resw 1
rsvd        resw 1
nfats       resw 1
rootent     resw 1
totsec      resw 1
spf         resw 1
spt         resw 1
heads       resw 1
root_start  resw 1
root_secs   resw 1
data_start  resw 1
ncl         resw 1
maxcl       resw 1
cluster_bytes resw 1
xfer_seg    resw 1
xfer_off    resw 1
xfer_max    resw 1
lf_size     resw 1
lf_clu      resw 1
sf_size     resw 1
sf_name     resw 1
sf_ent      resw 1
sf_prev     resw 1
sf_first    resw 1
sf_cur      resw 1
sf_ptr      resw 1
sf_left     resw 1
ls_files    resw 1
ls_bytes    resw 2
ls_col      resb 1
fk_files    resw 1
fk_err      resw 1
fk_lost     resw 1
hd_base     resw 1
hd_seg      resw 1
ed_len      resw 1
ed_cur      resw 1
ed_top      resw 1
ed_left     resw 1
ed_row      resw 1
ed_col      resw 1
ed_line     resw 1
ed_msg      resw 1
inbuf       resb 128
cmdbuf      resb 128
hist        resb 128
strbuf      resb 260
printbuf    resb 260
fbuf        resb 260
idbuf       resb 12
idbuf2      resb 12
fn83        resb 12
fn83b       resb 12
numbuf      resb 12
tmpname     resb 16
ed_name     resb 12
ed_nametxt  resb 16
tasks       resb 192
bss_small_end:

absolute 0xA800
dirbuf      resb 7168
fatbuf      resb 6144
secbuf      resb 512
fsck_map    resb 512
