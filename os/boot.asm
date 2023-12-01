;=====================================
;
; minis operating system 0.03
; Copyright (c) 2021-2023 Maghdouri Mohamed
; All rights reserved.
; see LICENSE.TXT
; Date: 11-11-2023
; https://mini-as.github.io
;
; minis bootloader version 0.01
; boot sector for floppy 180 KB	
; 5.25-inch, 1-sided, 9-sector
; boot sector must be 512 bytes
; Date: 23-11-2021
;
; to build bootloader version 0.01
; use minis assembler version 0.09a
;
;=====================================	
	use16
	jmp byte start
	nop
	
	; BIOS Parameter Block start at offset 3 
	db 'MINIS   ' ; Oem ID
	dw 0x200 ; Bytes per Sector
	db 0x01 ; Sectors per Cluster
	dw 0x01 ; Reserved sectors 
	db 0x01 ; Number of FAT copies
	dw 0x10 ; Number of possible root entries
	dw 0x168 ; number of sectors
	db 0xFC	; 180 KB	5.25-inch, 1-sided, 9-sector
	dw 0x02 ; Sectors per FAT
	dw 0x09 ; Sectors per Track
	dw 0x01 ; Number of Heads
	dd 0x00 ; Hidden Sectors
	dd 0x00 ; Large number of sectors
	db 0x00 ; Drive Number
	db 0x00 ; Reserved
	db 0x29 ; Extended Boot Signature
	dd 0x00 ; Volume Serial Number
	db 'FLOPPY     ' ; Volume Label
	db 'FAT12   ' ; File System Type
	

start:
	cli
	mov ax, 0x07C0 ; segment where bootsector loaded
	mov ds, ax
	mov es, ax
	mov ax, 0x0000
	mov ss, ax
	mov sp, 0xFFFF
	sti
	
	mov si, msg
	call word print
	
	; load root directory to 7c00:0200
load_root:
	mov ax, 0x03 ; 2+1
	mov bx, 0x200
	mov cx, 0x01 ; (16*32)/512
	call word read
	
; search for kernel entry in root directory
	mov cx, 0x10 ; Number of possible root entries
	mov di, 0x200
find_kernel:
	push cx
	push di
	mov cx, 0x0B
	mov si, kernel
	rep
	cmpsb
	pop di
	pop cx
	je byte load_fat
	add di, 0x20
	loop byte find_kernel

	mov si, kernel_not_found
	call word print
	xor ax, ax
	int 0x16
	int 0x19


	; load fat to 7c00:0200
load_fat:
	add di, 0x1A
	mov dx, word [di]
	mov bx, cluster
	mov word [bx], dx
	mov cx, 0x02 ; Sectors per FAT
	mov ax, 0x01
	mov bx, 0x200
	call word read

; load kernel to 0x1000:0x0000
	mov ax, 0x1000
	mov es, ax
	mov bx, 0x00
	push bx
load:
	mov bx, cluster
	mov ax, word [bx]
	add ax, 0x02 ; -2+(boot+fat+root) = -2+(1+2+1) = 2
	pop bx  
	mov cx, 0x01
	call word read
	push bx
	mov bx, cluster
	mov ax, word [bx]
	mov cx, ax
	mov dx, ax
	shr dx, 0x01
	add cx, dx
	mov bx, 0x200
	add bx, cx
	mov dx, word [bx]
	test ax, 0x01
	jnz byte _odd
	_even:
	and dx, 0x0FFF
	jmp byte _done
	_odd:
	shr dx, 0x04
	_done:
	mov bx, cluster
	mov word [bx], dx
	cmp dx, 0x0FF0 ; EOF?
	jb byte load

	mov si, cr_lf
	call word print
	jmp 0x1000: word 0x0000
	
	
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
	
; read sectors
; ax=lba es:bx=memory cx=number of sectors to read
read:
	mov di, 0x05 ; try 5 times
	again:
	push ax
	push bx
	push cx
	xor dx, dx
	mov cx, 0x09 ; Sectors per Track
	div cx
	inc dx
	push dx
	xor dx, dx
	mov cx, 0x01 ; head number
	div cx
	pop cx     ; cl = sector
	mov ch, al ; ch = track
	mov dh, dl ; dh = head
	mov dl, 0x00
	mov ax, 0x201
	int 0x13 ; read sector int
	jnc byte read_ok
	xor ax, ax
	int 0x13
	dec di
	pop cx
	pop bx
	pop ax
	jnz byte again
	int 0x18
	read_ok:
	mov si, progress
	call word print
	pop cx
	pop bx
	pop ax
	add bx, 0x200
	inc ax
	loop byte read
	ret
	
msg:
	db 'Welcome To Minis.',0x0D, 0x0A
	db 'Loading ', 0x00
progress:
	db '.', 0x00
kernel_not_found:
	db 0x0D, 0x0A,'Error: kernel not found!', 0x00
kernel:
	db 'KERNEL     '
cluster:
	dw 0x00
cr_lf:
	db 0x0D, 0x0A, 0x00
	
	times 0x7B db 0x00 ; fill with 0 to = 512 bytes

	dw 0xAA55 ; Boot sector signature
	
	