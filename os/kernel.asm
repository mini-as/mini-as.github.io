;=====================================
;
; minis kernel version 0.03
; Copyright (c) 2021-2023 Maghdouri Mohamed
; All rights reserved.
; see LICENSE.TXT
; Date: 11-11-2023
; https://mini-as.github.io
;
; compile with minis assembler 0.09a
;
;=====================================	

	use16
	jmp byte start_rm
	
gdt_start:
	; null descriptor 
	dd 0x00,0x00 

; code descriptor 0x8
	dw 0xFFFF ; limit low
	dw 0x00   ; base low
	db 0x00   ; base middle
	db 0x9A   ; access
	db 0xCF   ; granularity
	db 0x00   ; base high
 
; data descriptor 0x10
	dw 0xFFFF ; limit low
	dw 0x00   ; base low
	db 0x00   ; base middle
	db 0x92   ; access
	db 0xCF   ; granularity
	db 0x00	  ; base high
gdt_end:

gdt_r: 
	dw 0x17 	; limit (Size of GDT)
	dd 0x10002  ; base of GDT at gdt_start
	
bps:
	dd 0x00
bpp:
	dd 0x00
lfb:
	dd 0x00
ppf:
	dd 0x00
scx:
	dd 0x280 ; screen x = 640
scy:
	dd 0x1E0 ; screen y = 480

msg:
	db 'minis kernel version 0.03',0x0D , 0x0A, 0x00
	
vesa_err:
	db 'error: vesa!',0x00 ,0x0D ,0x0A
	
vesa_error:
	mov si, vesa_err
	call word print
	v_err:
	jmp byte v_err
	
; print string
print:
	lodsb
	cmp al, 0x00
	je byte print_ok
	mov ah, 0x0E
	int 0x10
	jmp byte print
print_ok:
	ret
	
; start real mode code (16 bit)
start_rm:
	cli
	mov ax, 0x1000
	mov ds, ax
	mov es, ax
	mov ax, 0x0000
	mov ss, ax
	mov sp, 0xFFFF
	sti
	
	mov si, msg
	call word print
	
	mov ax, 0x4F00
	mov di, temp_data
	int 0x10
	cmp ax, 0x004F
	jne byte vesa_error

; 0x112 ,  640 ,  480
; 0x115 ,  800 ,  600
; 0x118 , 1024 ,  768
; 0x11B , 1280 , 1024
	
	mov ax, 0x4F01
	mov cx, 0x112 ; mode
	mov di, temp_data
	int 0x10
	cmp ax, 0x004F
	jne byte vesa_error
	
	add di, 0x10
	mov bx, bps ; 0x20
	mov ax, word [di]
	mov word [bx], ax
	add di, 0x09
	mov bx, bpp ; 0x24
	mov al, byte [di]
	mov byte [bx], al
	add di, 0x0F
	mov bx, lfb ; 0x28
	mov eax, dword [di]
	mov dword [bx], eax
	
	mov ax, 0x4F02
	mov bx, 0x112 ; mode
	add bx, 0x4000
	int 0x10
	cmp ax, 0x004F
	jne byte vesa_error
	
; enable protected mode (32 bit)
	cli
	
	call word enable_line
	mov eax, gdt_r
	lgdt pword [eax] ; load GDT into GDTR
	
	mov edx, cr0
	or edx, 0x01
	mov cr0, edx
	jmp	0x08: dword 0x1012E ; start_pm: = 0x1012E
	
	
; Enables A20 line through output port
enable_line:
	cli
	call word wait_input

	mov al, 0xD0
	out 0x64, al ; tell controller to read output port
	call word wait_output

	in al, 0x60
	push eax ; get output port data
	call word wait_input

	mov al, 0xD1
	out 0x64, al ; tell controller to write output port
	call word wait_input

	pop eax
	or al, 0x02 ; set bit 1 (enable a20)
	out 0x60, al ; write out data back to the output port

	call word wait_input

	ret

; wait for input buffer to be clear
wait_input:
	in al, 0x64
	test al, 0x02
	jnz byte wait_input
	ret

; wait for output buffer to be clear
wait_output:
	in al, 0x64
	test al, 0x01
	jz byte wait_output
	ret
	
; start protected mode code (32 bit)
use32	
start_pm:
	mov ax, 0x10
	mov ds, ax
	mov ss, ax
	mov es, ax
	mov gs, ax
	mov fs, ax
	mov esp, 0xFFFF
	
	mov edx, bpp
	add edx, 0x10000
	mov edx, dword [edx]
	cmp edx, 0x18
	je byte bpp_a
	
	mov edx, ppf
	add edx, 0x10000
	mov eax, put_pixel_b
	add eax, 0x10000
	mov dword [edx], eax
	jmp byte bpp_b
	
	bpp_a:
	mov edx, ppf
	add edx, 0x10000
	mov eax, put_pixel_a
	add eax, 0x10000
	mov dword [edx], eax
	
	bpp_b:
	
	call dword init_pic
	call dword init_pit
	
	call dword build_idt
	mov eax, idt_r
	add eax, 0x10000
	lidt pword [eax]
	
	call dword print_desktop
	
	mov eax, 0x140
	mov ebx, 0xF0
	mov esi, mouse
	call dword draw_icon
	
	mov eax, 0x7
	mov ebx, 0x50
	mov esi, cmd_
	call dword draw_icon
	
	; unmask IRQs
	mov al, 0x00
	out 0xA1, al
	out 0x21, al
	
	mov ecx, 0x20
	send_ei:
	call dword end_int
	loop byte send_ei
	
	sti ; life back :-)
	
	hlt
	here:
	jmp byte here
	
; Initialize Programmable Interrupt Controller (8259A)
init_pic:
	; Send initialization Control Word 1
	mov al, 0x11
	out 0x20, al
	out 0xA0, al
	
	; Send initialization control word 2
	mov al, 0x20
	out 0x21, al
	mov al, 0x28
	out 0xA1, al
	
	; Send initialization control word 3
	mov al, 0x04
	out 0x21, al
	mov al, 0x02
	out 0xA1, al
	
	; Send Initialization control word 4. Enables i86 mode
	mov al, 0x01
	out 0x21, al
	out 0xA1, al
	ret
	
; Initialize Programmable Interval Timer (8253)
; set timer to 100Hz
init_pit:
	mov al, 0x34 ; Send OCW = 00110100b = Counter 0, Load LSB first then MSB, Mode 2, Binary
	out 0x43, al
	mov al, 0x9B ; lsb 1193180 / 100Hz = 11931 = 0x2E9B
	out 0x40, al
	mov al, 0x2E ; msb
	out 0x40, al
	ret
	
build_idt:
    mov ebx, interrupt_routines
    add ebx, 0x10000
    mov edi, idt_start
    add edi, 0x10000
    mov ecx, 0xFF
    idt_descriptor:
    mov eax, dword [ebx]
    add eax, 0x10000
    mov word [edi], ax
	add edi, 0x02
	mov dx, 0x08
    mov word [edi], dx
	add edi, 0x02
	mov dl, 0x00
    mov byte [edi], dl
	add edi, 0x01
	mov dl, 0x8E ; 10001110b
    mov byte [edi], dl
	add edi, 0x01
    shr eax, 0x10
    mov word [edi], ax
    add edi, 0x02
    add ebx, 0x04
    loop byte idt_descriptor
    ret
	
print_desktop:
	mov eax, 0x00
	mov ebx, 0x00
	mov ecx, 0x005353
	
	print_dx:
	call dword put_pixel
	mov edx, scx
	add edx, 0x10000
	mov edx, dword [edx]
	inc eax
	cmp eax, edx
	jl byte print_dx
	mov eax, 0x00
	inc ebx
	mov edx, scy
	add edx, 0x10000
	mov edx, dword [edx]
	cmp ebx, edx
	jl byte print_dx
	ret
	
draw_icon:
    add esi, 0x10000
    mov edi, esi
    add edi, 0x12 ; bmp width
    mov ecx, dword [edi]
    add edi, 0x04 ; bmp height
    mov edx, dword [edi]
    add ebx, edx
    dec ebx
    add esi, 0x36 ; start of pixels
    mov edi, eax
    
    shl edx, 0x10
    mov dx, cx
    draw_icon_line:
    push cx
    mov ecx, dword [esi]
    and ecx, 0x00FFFFFF
    cmp ecx, 0x00FFFFFF
    je byte no_draw_icon_line
    call dword put_pixel
    no_draw_icon_line:
    pop cx
    add esi, 0x03
    inc eax
    dec cx
    cmp cx, 0x00
    jg byte draw_icon_line
    
    mov cx, dx
    movzx eax, cx
    and eax, 0x03 ; fix 0 added
    add esi, eax
    mov eax, edi
    dec ebx
    sub edx, 0x10000
    cmp edx, 0xFFFF
    jg byte draw_icon_line
    
    ret



; eax = x ebx = y ecx = color (RGB)
put_pixel:
	pusha
	mov edx, ppf
	add edx, 0x10000
	mov edx, dword [edx]
	call dword edx
	popa
	ret

; eax = x ebx = y ecx = color (RGB)
; bpp = 24
; where = [ (x*3) + (y*bps) + lfb ]
put_pixel_a:
	mov edi, eax
	shl edi, 0x01
	add edi, eax
	mov eax, bps
	add eax, 0x10000
	mov eax, dword [eax]
	xor edx, edx
	mul ebx
	add edi, eax
	mov eax, lfb
	add eax, 0x10000
	mov eax, dword [eax]
	add edi, eax
	mov word [edi], cx
	shr ecx, 0x10
	add edi, 0x02
	mov byte [edi], cl
	ret
	
; eax = x ebx = y ecx = color (RGB)
; bpp = 32
; where = [ (x*4 + (y*bps) + lfb ]
put_pixel_b:
	mov edi, eax
	shl edi, 0x02
	mov eax, bps
	add eax, 0x10000
	mov eax, dword [eax]
	xor edx, edx
	mul ebx
	add edi, eax
	mov eax, lfb
	add eax, 0x10000
	mov eax, dword [eax]
	add edi, eax
	mov dword [edi], ecx
	ret
	

idt_r:
	dw 0x07F7  ; ( idt_end - idt_start - 1 )  limit (Size of IDT)
	dd 0x10769 ; idt_start 0x10769                   base of IDT

interrupt_routines:
    times 0x20 dd irq_ 
    dd irq_0
    dd irq_1
    dd irq_2
    dd irq_3
    dd irq_4
    dd irq_5
    dd irq_6
    dd irq_7
    dd irq_8
    dd irq_9
    dd irq_10
    dd irq_11
    dd irq_12
    dd irq_13
    dd irq_14
    dd irq_15
    dd int_0x30
    times 0xCE dd irq_ 
    
idt_start: ; idt at address = 0x1078A
    times 0xFF dd 0x00, 0x00
idt_end:

irq_:
    pusha
    call dword end_int
    popa
    iret

irq_0:
	pusha
	call dword end_int
	popa
	iret

irq_1:
	pusha
    
    mov eax, 0x10
	mov ebx, 0x10
	mov ecx, 0xFFFFFF
	call dword put_pixel ; put pixel at screen to check if keyboard interrupt work
	
    call dword end_int
    popa
    iret
	
irq_2:
	pusha
    call dword end_int
    popa
    iret
	
irq_3:
	pusha
    call dword end_int
    popa
    iret
	
irq_4:
	pusha
    call dword end_int
    popa
    iret
	
irq_5:
	pusha
    call dword end_int
    popa
    iret
	
irq_6:
	pusha
    call dword end_int
    popa
    iret
	
irq_7:
	pusha
    call dword end_int
    popa
    iret
	
irq_8:
	pusha
    call dword end_int
    popa
    iret
	
irq_9:
	pusha
    call dword end_int
    popa
    iret
	
irq_10:
	pusha
    call dword end_int
    popa
    iret
	
irq_11:
	pusha
    call dword end_int
    popa
    iret
	
irq_12:
	pusha
    call dword end_int
    popa
    iret
	
irq_13:
	pusha
    call dword end_int
    popa
    iret
	
irq_14:
	pusha
    call dword end_int
    popa
    iret
	
irq_15:
	pusha
    call dword end_int
    popa
    iret
	
int_0x30:
	pusha
    call dword end_int
    popa
    iret
    
end_int:
    mov al, 0x20
    out 0x20, al
    out 0xA0, al
    ret


; I created mouse.bmp and cmd.bmp using Paint
mouse:	
binary 'mouse.bmp'

cmd_:
binary 'cmd.bmp'



temp_data:


