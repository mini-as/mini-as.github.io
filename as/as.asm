;===========================================
;
; Minis assembler 0.10
; Executed only from MSDOS 2.0+ / Dos emulators.
; Copyright (c) 2021-2024 Maghdouri Mohamed
; All rights reserved.
; See LICENSE.TXT
; Date: 27-04-2024
; https://mini-as.github.io
;
; First version self compile.
;
;
;===========================================
	
	org 0x100
	use16
	
	jmp start

	db 'minis assembler 0.10',0
	db 'Copyright (c) 2021-2024 Maghdouri Mohamed',0
	db 'All rights reserved.',0
	
start:
	mov dx, asm_
	call print_string

	call get_cmd
	call alloc_memory
	
	call preprocessor
	call assembler
	call create_binary
	
	call get_binary_size
	mov dx, succ_
	call print_string
	mov al, 0 ; AL = return code
exit:
	call free_memory
	mov ah, 0x4C ; terminate with return code
	int 0x21
	
	
;--------------------------------	
; memory map:
	
; memory_start (size = 512 KB)
	; source_start
	; source_end
	; db 0
	; binary_start
	; binary_end
	; label_start (size = 100 KB)
	; label_end
; memory_end
;--------------------------------

	
alloc_memory:
	mov ebx, 0xFFFF
	add ebx, 0x10F ; size of the PSP (0x100) + next paragraph
	shr ebx, 4     ; bx = paragraphs to keep
	mov ah, 0x4A   ; resize memory block
	int 0x21
	jc not_enough_memory
	mov ah, 0x48   ; allocate memory
	mov bx, 0x8000 ; allocate 512 KB
	int 0x21
	jc not_enough_memory ; function fails ?
	movzx edx, bx ; bx = size of largest available block
	shl edx, 4
	movzx ebx, ax ; ax = segment of allocated block
	shl ebx, 4
	mov dword [memory_start], ebx
	add ebx, edx
	mov dword [memory_end], ebx
	ret
	
	
free_memory:
	push eax
	mov eax, dword [memory_start]
	shr eax, 4
	cmp eax, 0
	je no_alloc_memory
	mov es, ax
	mov ah, 0x49 ; free memory
	int 0x21
	no_alloc_memory:
	pop eax
	ret
	
; dx = string pointer
print_string:
	mov ah, 9
	int 0x21
	ret

print_error:
	call print_string
	mov eax, 1
	jmp exit

get_cmd:
	mov esi, 0x81
	call skip_space
	mov edi, save_cmd
	mov dword [input_file], edi
	copy_cmd1:
	lodsb
	cmp al, ' '
	je copy_cmd11
	cmp al, 0
	je usage_error
	cmp al, 13
	je usage_error
	stosb
	jmp copy_cmd1
	copy_cmd11:
	xor al,al
	stosb
	call skip_space
	mov dword [output_file], edi
	mov ecx, esi
	copy_cmd2:
	lodsb
	cmp al, ' '
	je copy_cmd22
	cmp al, 0
	je copy_cmd22
	cmp al, 13
	je copy_cmd22
	stosb
	jmp copy_cmd2
	copy_cmd22:
	xor al,al
	stosb
	dec esi
	sub ecx, esi
	cmp ecx, 0
	je usage_error
	ret

open_file:
	mov ah, 0x3D ; open existing file
	mov al, 0x00 ; access and sharing modes
	int 0x21
	mov ebx, eax ; eax = file pointer
	ret

create_file:
	mov ah, 0x3C ; create or truncate file
	mov cx, 0 ; file attribute
	int 0x21
	mov ebx, eax ; eax = file handle
	ret

write_file:
	pushad
	mov esi, edx
	mov edx, ecx
	shr ecx, 12
	inc ecx
	and edx, 0xFFF
	write_file_loop:
	push ecx
	push edx
	mov eax, dword [esp+4]
	cmp eax, 1
	jne write_file_
	mov ecx, dword [esp]
	jmp write_file_end
	write_file_:
	mov ecx, 4096
	write_file_end:
	push ecx
	cld
	mov edi, com_end
	rep
	movs byte [edi], [esi]
	pop ecx
	mov ah, 0x40 ; write to file or device
	mov dx, com_end
	int 0x21
	pop edx
	pop ecx
	loop write_file_loop
	popad
	ret
	
read_file:
	pushad
	mov edi, edx
	mov edx, ecx
	shr ecx, 12
	inc ecx
	and edx, 0xFFF
	read_file_loop:
	push ecx
	push edx
	mov eax, dword [esp+4]
	cmp eax, 1
	jne read_file_
	mov ecx, dword [esp]
	jmp read_file_end
	read_file_:
	mov ecx, 4096
	read_file_end:
	push ecx
	mov ah, 0x3F ; read from file or device
	mov dx, com_end
	int 0x21
	;jc file_error
	pop ecx
	cld
	mov esi, com_end
	rep
	movs byte [edi], [esi]
	pop edx
	pop ecx
	loop read_file_loop
	popad
	ret

close_file:
	mov ah, 0x3E ; close file
	int 0x21
	ret
	
lseek_file:
	mov ah, 0x42 ; set current file position
	mov ecx, 0
	int 0x21
	push dx
	push ax
	pop eax
	ret
	
preprocessor:
	mov edx, dword [input_file]
	call open_file
	jc no_source_file
	mov eax, 2 ; end of file
	mov edx, 0
	call lseek_file
	push eax
	mov eax, 0 ; start of file
	mov edx, 0
	call lseek_file
	pop ecx ; file size
	cmp ecx, 0x35000
	jae not_enough_memory
	mov edx, dword [memory_start]
	mov dword [source_start], edx
	mov dword [source_end], edx
	add dword [source_end], ecx
	mov eax, dword [memory_end]
	sub eax, 0x19000 ; buffer size of labels = 100 KB
	mov dword [label_start], eax
	mov dword [label_end], eax
	call read_file
	call close_file
	ret
	
assembler:
	mov dx, msgas_
	mov ah, 9
	int 0x21
	mov eax, dword [label_start]
	mov byte [eax], 0
	next_pass:
	mov eax, dword [label_start]
	mov dword [label_end], eax
	mov esi, dword [source_start]
	mov edi, dword [source_end]
	mov al, 0
	stos byte [edi]
	mov dword [binary_start], edi
	mov byte [code_type], 16
	mov dword [org_value], 0
	mov dword [line_number], 0
	mov dword [need_pass], 0
	inc dword [count_pass]
	cmp dword [count_pass], 20
	jae create_failed
	assemble_next_line:
	call assemble_line
	mov eax, edi ; check binary file limits
	add eax, 50
	cmp eax, dword [label_start]
	jge not_enough_memory
	cmp esi, dword [source_end] ; end of file
	jb assemble_next_line
	cmp dword [need_pass], 1
	je next_pass
	mov dword [binary_end], edi
	ret
	
create_binary:
	mov edx, dword [output_file]
	call create_file
	jc create_failed
	mov edx, dword [binary_start]
	mov ecx, dword [binary_end]
	sub ecx, edx
	mov dword [binary_size], ecx
	call write_file
	jc create_failed
	call close_file
	ret
	
assemble_line:
	inc dword [line_number]
	call skip_space
	call get_symbol_size ; get_symbol

	cmp byte [esi], ';' ; comment
	je skip_comment
	cmp byte [esi], 0 ; end of file
	je assemble_line_ok
	cmp byte [esi], 13 ; new line
	je next_line
	cmp byte [esi], 10 ; new line
	je next_line
	;cmp al, ':' ; label ( al register from get_symbol_size )
	cmp byte [esi+ecx], ':'
	je check_label
	
	mov edx, instructions
	call find_symbol
	jc unknown_symbol
	call eax
	
	skip_next_line:
	add esi, ecx    ; esi = pointer of last operand, ecx = size of last operand
	call skip_space
	
	cmp byte [esi], ';' ; comment
	je skip_comment
	cmp byte [esi], 0 ; end of file
	je assemble_line_ok
	cmp byte [esi], 13 ; new line
	je next_line
	cmp byte [esi], 10 ; new line
	je next_line
	jmp extra_character
	assemble_line_ok:
	ret
	
next_line:
	lods byte [esi]
	cmp al, 13
	je line_feed
	cmp al, 10
	je line_ret
	dec esi
	jmp line_end
	line_feed:
	lods byte [esi]
	cmp al, 10
	je line_end
	dec esi
	jmp line_end
	line_ret:
	lods byte [esi]
	cmp al, 13
	je line_end
	dec esi
	jmp line_end
	line_end:
	jmp assemble_line_ok
	
; skip this symbol and find next symbol
; in:   esi = start of this symbol    ecx = size of this symbol
; ret:  esi = start of next symbol    ecx = size of next symbol
skip_symbol:
	add esi, ecx
	call skip_space
	call get_symbol_size ; get_symbol
	ret
	
skip_comment:
	lods byte [esi]
	cmp al, 0
	je assemble_line_ok
	cmp al, 10
	je next_line
	cmp al, 13 ; new line
	je next_line
	jmp skip_comment
	
skip_space:
	lods byte [esi]
	cmp al, ' ' 
	je skip_space
	cmp al, 0x09 ; tab
	je skip_space
	dec esi ; lodsb inc esi
	ret
	
; ret: ecx = symbol size
get_symbol_size:
	push esi ; esi = start of symbol
	get_symbol_end:
	lods byte [esi]
	cmp al, 0 ; end of file
	je get_symbol_ok
	cmp al, 13 ; new line
	je get_symbol_ok
	cmp al, 10 ; new line
	je get_symbol_ok
	cmp al, ' ' ; space
	je get_symbol_ok
	cmp al, 0x09 ; tab
	je get_symbol_ok
	cmp al, 0x27 ; string
	je string_start
	cmp al, ':' ; label
	je get_symbol_ok
	cmp al, ',' ; operand
	je get_symbol_ok
	cmp al, ';' ; comment
	je get_symbol_ok
	cmp al, '[' ; memory
	je get_symbol_ok
	cmp al, ']' ; memory
	je get_symbol_ok
	cmp al, '+' ; add
	je get_symbol_ok
	cmp al, '-' ; sub
	je get_symbol_ok
	cmp al, '*' ; mul
	je get_symbol_ok
	
	jmp get_symbol_end
	string_start:
	lods byte [esi]
	cmp al, 13
	je missing_quote
	cmp al, 0
	je missing_quote
	cmp al, 0x27
	jne string_start
	inc esi ; to get length from ' to '
	get_symbol_ok:
	dec esi ; lodsb inc esi
	sub esi, dword [esp]
	mov ecx, esi
	pop esi
	ret
	

get_signed_number:
	cmp byte [esi], '+'
	je signed_number
	cmp byte [esi], '-'
	je signed_number
	jmp get_number
	
	signed_number:
	push edx
	movzx edx, byte [esi]
	push edx
	inc esi ; skip sign
	call skip_space
	call get_symbol_size
	
	call get_number
	jc no_positive_number
	
	pop edx
	cmp dl, '+'
	je positive_number
	not eax
	inc eax
	positive_number:
	pop edx
	clc
	ret
	no_positive_number:
	pop edx
	pop edx
	stc
	ret
	
; ret: eax = number
get_number:
	cmp word [esi], '0x'
	je get_hex
	cmp byte [esi], '0'
	jb no_number
	cmp byte [esi], '9'
	ja no_number
	cmp byte [esi+ecx-1], 'b'
	je get_bin
	
	jmp get_dec
	
get_dec:
	pushad
	cmp ecx, 10
	ja value_exceeds_range
	cmp ecx, 1
	jb invalid_operand
	mov dword [dec_number], 0
	xor edx, edx
	add esi, ecx
	mov ebx, 1
	valid_dec:
	dec esi
	movzx eax, byte [esi]
	cmp al, '0'
	jb invalid_operand
	cmp al, '9'
	ja invalid_operand
	sub al, '0'
	mul ebx
	imul ebx, 10
	add dword [dec_number], eax
	jc value_exceeds_range
	loop valid_dec
	mov ebx, dword [dec_number]
	mov dword [esp+28], ebx
	popad
	clc
	ret

dec_number: 
dd 0
	
get_hex:
	pushad
	push esi
	push ecx
	cmp ecx, 3
	jb invalid_operand
	add esi, 2
	sub ecx, 2
	cmp ecx, 8
	ja value_exceeds_range ; invalid_operand
	mov ebx, 0
	valid_hex:
	lods byte [esi]
	cmp al, '0'
	jb invalid_operand
	cmp al, '9'
	ja valid_hex_a
	sub al, '0'
	jmp valid_hex_ok
	valid_hex_a:
	cmp al, 'A'
	jb invalid_operand
	cmp al, 'F'
	ja invalid_operand
	sub al, 55
	valid_hex_ok:
	shl ebx, 4
	add bl, al
	loop valid_hex
	pop ecx
	pop esi
	mov dword [esp+28], ebx
	popad
	clc
	ret
	
get_bin:
	pushad
	cmp ecx, 33
	ja value_exceeds_range
	cmp ecx, 2
	jb invalid_operand
	dec ecx
	clc
	mov ebx, 0
	valid_bin:
	shl ebx, 1
	movzx eax, byte [esi]
	cmp al, '0'
	jb invalid_operand
	cmp al, '1'
	ja invalid_operand
	sub al, '0'
	or ebx, eax
	inc esi
	loop valid_bin
	valid_bin_ret:
	mov dword [esp+28], ebx
	popad
	clc
	ret
	
no_number:
	stc
	ret
	
check_label:
	cmp dword [count_pass], 1
	ja update_label
	
	call valid_label
	mov edx, dword [label_start]
	call find_symbol
	jnc label_already_defined
	call check_reserved_word
	
	update_label:
	call save_label
	inc ecx ; add (:) end label
	jmp skip_next_line
	
;in: esi = string start    ecx = string lentgh
valid_label:
	pushad
	cmp ecx, 32
	jg invalid_label
	cmp ecx, 1
	jl invalid_label
	lods byte [esi]
	dec esi
	cmp al, '9' ; label must not start with number
	jle invalid_label
	valid_label_char:
	lods byte [esi]
	cmp al, '_'
	je next_label_char
	cmp al, 'a'
	jl valid_label_upper
	cmp al, 'z'
	jg invalid_label
	next_label_char:
	loop valid_label_char
	popad
	ret
	valid_label_upper:
	cmp al, 'Z'
	jg invalid_label
	cmp al, 'A'
	jl valid_label_number
	jmp next_label_char
	valid_label_number:
	cmp al, '0'
	jl invalid_label
	cmp al, '9'
	jg invalid_label
	jmp next_label_char
	
check_reserved_word:
	mov edx, operand_size
	call find_symbol
	jnc reserved_word
	mov edx, instructions
	call find_symbol
	jnc reserved_word
	mov edx, all_registers
	call find_symbol
	jnc reserved_word
	ret

save_label:
	pushad
	mov edx, edi
	mov edi, dword [label_end]
	mov eax, edi
	add eax, 40
	cmp eax, dword [memory_end]
	jae not_enough_memory
	sub edx, dword [binary_start] ; get current address value
	cmp dword [count_pass], 1
	ja update_label_value
	mov eax, ecx
	stos byte [edi]
	save_label_string:
	lods byte [esi]
	stos byte [edi]
	loop save_label_string
	add edx, dword [org_value]
	mov eax, edx
	stos dword [edi]
	mov eax, 0
	stos byte [edi]
	dec edi
	mov dword [label_end], edi
	popad
	ret
	update_label_value:
	add edx, dword [org_value]
	mov eax, dword [edi+ecx+1]
	cmp eax, edx
	je label_not_changed
	mov dword [need_pass], 1
	mov dword [edi+ecx+1], edx
	label_not_changed:
	add edi, 5
	add edi, ecx
	mov dword [label_end], edi
	popad
	ret

find_symbol:
	pushad
	mov edi, edx
	mov ebp, esi
	mov ebx, ecx
	mov dh, byte [esi]
	mov dl, cl
	xor eax, eax
	clc
	cld
	next_symbol:
	push edi
	mov cx, word [edi]
	cmp cl, 0
	je no_symbol_found
	mov al, cl
	cmp cx, dx
	je check_symbol
	pop edi
	add edi, eax
	add edi, 5
	jmp next_symbol
	check_symbol:
	mov esi, ebp
	mov ecx, ebx
	inc edi
	rep
	cmps byte [esi], [edi]
	je yes_symbol_found
	pop edi
	add edi, eax
	add edi, 5
	jmp next_symbol
	no_symbol_found:
	pop edi
	popad
	stc
	ret
	yes_symbol_found:
	pop edi
	add edi, eax
	inc edi
	mov eax, dword [edi]
	mov dword [esp+28], eax
	popad
	clc
	ret

address_size_prefix_16:
	push eax
	cmp byte [code_type], 16
	je asp16_ok
	mov al, 0x67
	stos byte [edi]
	asp16_ok:
	pop eax
	ret
	

address_size_prefix_32:
	push eax
	cmp byte [code_type], 32
	je asp32_ok
	mov al, 0x67
	stos byte [edi]
	asp32_ok:
	pop eax
	ret
	
	
operand_size_prefix_16:
	push eax
	cmp byte [code_type], 16
	je osp16_ok
	mov al, 0x66
	stos byte [edi]
	osp16_ok:
	pop eax
	ret
	
operand_size_prefix_32:
	push eax
	cmp byte [code_type], 32
	je osp32_ok
	mov al, 0x66
	stos byte [edi]
	osp32_ok:
	pop eax
	ret
	
find_source_operand:
	add esi, ecx
	call skip_space
	cmp byte [esi], ','
	jne invalid_operand
	inc esi
	call skip_space
	call get_symbol_size
	ret
	
get_binary_size:
	mov eax, dword [binary_size]
	mov edi, succ_
	mov esi, edi
	add esi, 9
	add edi, 18
	mov ecx, 10
	call convert_number
	ret
	
get_line_number:
	mov edi, line_
	mov esi, edi
	add esi, 8  ; start
	add edi, 14 ; end
	mov ecx, 7  ; size
convert_number:
	mov ebx, 10
	save_number:
	xor edx,edx
	div ebx
	add dl, '0'
	mov byte [edi], dl
	dec edi
	loop save_number
	mov edi, esi
	skip_number:
	lods byte [esi]
	cmp al, '0'
	je skip_number
	dec esi
	shift_number:
	lods byte [esi]
	stos byte [edi]
	cmp al, 0
	jne shift_number
	ret

usage_error:
	mov dx, usage_
	je print_error
	
not_enough_memory:
	mov dx, nem_
	jmp print_error
	
no_source_file:
	mov dx, nosf_
	jmp print_error
	
create_failed:
	mov dx, ecf_
	jmp print_error
	
display_line_error:
	mov eax, dword [line_number]
	call get_line_number
	mov dx, line_
	call print_string
	mov eax, 1
	jmp exit
	
unknown_symbol:
	mov dx, uns_
	call print_string
	jmp display_line_error
	
extra_character:
	mov dx, ecol_
	call print_string
	jmp display_line_error
	
invalid_operand:
	mov dx, eivo_
	call print_string
	jmp display_line_error
	
invalid_address:
	mov dx, eiva_
	call print_string
	jmp display_line_error
	
unvalid_size_operand:
	mov dx, eios_
	call print_string
	jmp display_line_error
	
missing_quote:
	mov dx, emeq_
	call print_string
	jmp display_line_error
	
invalid_label:
	mov dx, einl_
	call print_string
	jmp display_line_error

label_already_defined:
	mov dx, elad_
	call print_string
	jmp display_line_error
	
value_exceeds_range:
	mov dx, ever_
	call print_string
	jmp display_line_error
	
operand_size_ns:
	mov dx, eons_
	call print_string
	jmp display_line_error
	
reserved_word:
	mov dx, erwl_
	call print_string
	jmp display_line_error
	
binary_file_nf:
	mov dx, bfnf_
	call print_string
	jmp display_line_error

	
	; 0x66 Operand-size override
	; 0x67 Address-size override
	
	; segment override prefix
	; es = 0x26
	; cs = 0x2E
	; ss = 0x36
	; ds = 0x3E
	; fs = 0x64
	; gs = 0x65
	
		
operand_size:
	db 4,'byte'
	dd 1
	db 4,'word'
	dd 2
	db 5,'dword'
	dd 4
	db 5,'pword'
	dd 6
	db 0
	
; register bit assignments, register type,0,0
all_registers:
register_8: ; Type = 1
	db 2,'al',0,1,0,0
	db 2,'cl',1,1,0,0
	db 2,'dl',2,1,0,0
	db 2,'bl',3,1,0,0
	db 2,'ah',4,1,0,0
	db 2,'ch',5,1,0,0
	db 2,'dh',6,1,0,0
	db 2,'bh',7,1,0,0
register_16: ; Type = 2
	db 2,'ax',0,2,0,0
	db 2,'cx',1,2,0,0
	db 2,'dx',2,2,0,0
	db 2,'bx',3,2,0,0
	db 2,'sp',4,2,0,0
	db 2,'bp',5,2,0,0
	db 2,'si',6,2,0,0
	db 2,'di',7,2,0,0
register_32: ; Type = 3
	db 3,'eax',0,3,0,0
	db 3,'ecx',1,3,0,0
	db 3,'edx',2,3,0,0
	db 3,'ebx',3,3,0,0
	db 3,'esp',4,3,0,0
	db 3,'ebp',5,3,0,0
	db 3,'esi',6,3,0,0
	db 3,'edi',7,3,0,0
register_seg: ; Type = 4
	db 2,'es',0,4,0x26,0
	db 2,'cs',1,4,0x2E,0
	db 2,'ss',2,4,0x36,0
	db 2,'ds',3,4,0x3E,0
	db 2,'fs',4,4,0x64,0
	db 2,'gs',5,4,0x65,0
register_control: ; Type = 5
	db 3,'cr0',0,5,0,0
	db 3,'cr2',2,5,0,0
	db 3,'cr3',3,5,0,0
	db 0
	
register_index:
	db 3,'eax',0,3,0,0
	db 3,'ecx',1,3,0,0
	db 3,'edx',2,3,0,0
	db 3,'ebx',3,3,0,0
	db 3,'esp',4,3,0,0
	db 3,'ebp',5,3,0,0
	db 3,'esi',6,3,0,0
	db 3,'edi',7,3,0,0
	db 2,'bx',7,2,0,0
	db 2,'bp',6,2,0,0
	db 2,'si',4,2,0,0
	db 2,'di',5,2,0,0
	db 0
	
instructions:
	db 3,'aaa'
	dd aaa_
	db 3,'aad'
	dd aad_
	db 3,'aam'
	dd aam_
	db 3,'aas'
	dd aas_
	db 3,'adc'
	dd adc_
	db 3,'add'
	dd add_
	db 3,'and'
	dd and_
	db 4,'arpl'
	dd arpl_
	db 2,'bt'
	dd bt_
	db 3,'btc'
	dd btc_
	db 3,'btr'
	dd btr_
	db 3,'bts'
	dd bts_
	db 3,'bsf'
	dd bsf_
	db 3,'bsr'
	dd bsr_
	db 5,'bound'
	dd bound_
	db 6,'binary'
	dd binary_
	db 3,'cbw'
	dd cbw_
	db 3,'clc'
	dd clc_
	db 3,'cld'
	dd cld_
	db 3,'cli'
	dd cli_
	db 3,'cmc'
	dd cmc_
	db 3,'cmp'
	dd cmp_
	db 3,'cwd'
	dd cwd_
	db 3,'cdq'
	dd cdq_
	db 4,'call'
	dd call_
	db 4,'cwde'
	dd cwde_
	db 4,'clts'
	dd clts_
	db 4,'cmps'
	dd cmps_
	db 5,'cmpsb'
	dd cmpsb_
	db 5,'cmpsw'
	dd cmpsw_
	db 5,'cmpsd'
	dd cmpsd_
	db 2,'db'
	dd db_
	db 2,'dw'
	dd dw_
	db 2,'dd'
	dd dd_
	db 3,'daa'
	dd daa_
	db 3,'das'
	dd das_
	db 3,'dec'
	dd dec_
	db 3,'div'
	dd div_
	db 5,'enter'
	dd enter_
	db 3,'hlt'
	dd hlt_
	db 2,'in'
	dd in_
	db 3,'inc'
	dd inc_
	db 3,'int'
	dd int_
	db 4,'idiv'
	dd idiv_
	db 4,'imul'
	dd imul_
	db 4,'insb'
	dd insb_
	db 4,'insw'
	dd insw_
	db 4,'insd'
	dd insd_
	db 4,'int3'
	dd int3_
	db 4,'into'
	dd into_
	db 4,'iret'
	dd iret_
	db 5,'iretd'
	dd iretd_
	db 2,'ja'
	dd ja_
	db 2,'jb'
	dd jb_
	db 2,'jc'
	dd jc_
	db 2,'je'
	dd je_
	db 2,'jz'
	dd je_
	db 2,'jg'
	dd jg_
	db 2,'jl'
	dd jl_
	db 2,'jo'
	dd jo_
	db 2,'jp'
	dd jp_
	db 2,'js'
	dd js_
	db 3,'jae'
	dd jae_
	db 3,'jbe'
	dd jbe_
	db 3,'jge'
	dd jge_
	db 3,'jle'
	dd jle_
	db 3,'jna'
	dd jna_
	db 3,'jnb'
	dd jnb_
	db 3,'jnc'
	dd jnc_
	db 3,'jne'
	dd jne_
	db 3,'jng'
	dd jng_
	db 3,'jnl'
	dd jnl_
	db 3,'jno'
	dd jno_
	db 3,'jnp'
	dd jnp_
	db 3,'jns'
	dd jns_
	db 3,'jnz'
	dd jne_
	db 3,'jpe'
	dd jp_
	db 3,'jpo'
	dd jpo_
	db 3,'jmp'
	dd jmp_
	db 4,'jcxz'
	dd jcxz_
	db 4,'jnae'
	dd jnae_
	db 4,'jnbe'
	dd jnbe_
	db 4,'jnge'
	dd jnge_
	db 4,'jnle'
	dd jnle_
	db 5,'jecxz'
	dd jecxz_
	db 3,'lar'
	dd lar_
	db 3,'lds'
	dd lds_
	db 3,'lss'
	dd lss_
	db 3,'les'
	dd les_
	db 3,'lfs'
	dd lfs_
	db 3,'lgs'
	dd lgs_
	db 3,'lea'
	dd lea_
	db 3,'lsl'
	dd lsl_
	db 3,'ltr'
	dd ltr_
	db 4,'lahf'
	dd lahf_
	db 4,'lgdt'
	dd lgdt_
	db 4,'lidt'
	dd lidt_
	db 4,'lldt'
	dd lldt_
	db 4,'lmsw'
	dd lmsw_
	db 4,'lock'
	dd lock_
	db 4,'lods'
	dd lods_
	db 4,'loop'
	dd loop_
	db 5,'leave'
	dd leave_
	db 5,'lodsb'
	dd lodsb_
	db 5,'lodsw'
	dd lodsw_
	db 5,'lodsd'
	dd lodsd_
	db 3,'mov'
	dd mov_
	db 3,'mul'
	dd mul_
	db 4,'movs'
	dd movs_
	db 5,'movsb'
	dd movsb_
	db 5,'movsw'
	dd movsw_
	db 5,'movsd'
	dd movsd_
	db 5,'movsx'
	dd movsx_
	db 5,'movzx'
	dd movzx_
	db 3,'neg'
	dd neg_
	db 3,'nop'
	dd nop_
	db 3,'not'
	dd not_
	db 2,'or'
	dd or_
	db 3,'org'
	dd org_
	db 3,'out'
	dd out_
	db 5,'outsb'
	dd outsb_
	db 5,'outsw'
	dd outsw_
	db 5,'outsd'
	dd outsd_
	db 3,'pop'
	dd pop_
	db 4,'popa'
	dd popa_
	db 4,'popf'
	dd popf_
	db 4,'push'
	dd push_
	db 5,'popad'
	dd popad_
	db 5,'pushf'
	dd pushf_
	db 5,'pusha'
	dd pusha_
	db 6,'pushad'
	dd pushad_
	db 3,'rcl'
	dd rcl_
	db 3,'rcr'
	dd rcr_
	db 3,'rol'
	dd rol_
	db 3,'ror'
	dd ror_
	db 3,'rep'
	dd rep_
	db 3,'ret'
	dd ret_
	db 4,'repe'
	dd rep_
	db 4,'repz'
	dd rep_
	db 4,'retw'
	dd retw_
	db 4,'retd'
	dd retd_
	db 5,'repne'
	dd repne_
	db 5,'repnz'
	dd repne_
	db 3,'sal'
	dd sal_
	db 3,'sar'
	dd sar_
	db 3,'shl'
	dd shl_
	db 3,'shr'
	dd shr_
	db 3,'sbb'
	dd sbb_
	db 3,'stc'
	dd stc_
	db 3,'std'
	dd std_
	db 3,'sti'
	dd sti_
	db 3,'str'
	dd str_
	db 3,'sub'
	dd sub_
	db 4,'sahf'
	dd sahf_
	db 4,'seta'
	dd seta_
	db 6, 'setnbe'
	dd setnbe_
	db 5, 'setae'
	dd setae_
	db 5, 'setnb'
	dd setnb_
	db 5, 'setnc'
	dd setnc_
	db 4, 'setb'
	dd setb_
	db 4, 'setc'
	dd setc_
	db 6, 'setnae'
	dd setnae_
	db 5, 'setbe'
	dd setbe_
	db 5, 'setna'
	dd setna_
	db 4, 'sete'
	dd sete_
	db 4, 'setz'
	dd setz_
	db 4, 'setg'
	dd setg_
	db 6, 'setnle'
	dd setnle_
	db 5, 'setge'
	dd setge_
	db 5, 'setnl'
	dd setnl_
	db 4, 'setl'
	dd setl_
	db 6, 'setnge'
	dd setnge_
	db 5, 'setle'
	dd setle_
	db 5, 'setng'
	dd setng_
	db 5, 'setne'
	dd setne_
	db 5, 'setnz'
	dd setnz_
	db 5, 'setno'
	dd setno_
	db 5, 'setnp'
	dd setnp_
	db 5, 'setpo'
	dd setpo_
	db 5, 'setns'
	dd setns_
	db 4, 'seto'
	dd seto_
	db 4, 'setp'
	dd setp_
	db 5, 'setpe'
	dd setpe_
	db 4, 'sets'
	dd sets_
	db 4,'sgdt'
	dd sgdt_
	db 4,'sidt'
	dd sidt_
	db 4,'sldt'
	dd sldt_
	db 4,'smsw'
	dd smsw_
	db 4,'stos'
	dd stos_
	db 5,'scasb'
	dd scasb_
	db 5,'scasw'
	dd scasw_
	db 5,'scasd'
	dd scasd_
	db 5,'stosb'
	dd stosb_
	db 5,'stosw'
	dd stosw_
	db 5,'stosd'
	dd stosd_
	db 4,'test'
	dd test_
	db 5,'times'
	dd times_
	db 5,'use16'
	dd use16_
	db 5,'use32'
	dd use32_
	db 4,'verr'
	dd verr_
	db 4,'verw'
	dd verw_
	db 4,'wait'
	dd wait_
	db 3,'xor'
	dd xor_
	db 5,'xlatb'
	dd xlatb_
	db 0

org_value:
dd 0

org_:
	call skip_symbol
	call imm_number
	mov dword [org_value], eax
	retd
	
use16_:
	mov byte [code_type], 16
	retd
	
use32_:
	mov byte [code_type], 32
	retd
	
db_:
	call skip_symbol
	db_save:
	cmp byte [esi], 0x27
	jne db_number
	push esi
	push ecx
	inc esi ; skipe '
	save_string:
	lods byte [esi]
	cmp al, 13
	je missing_quote
	cmp al, 0
	je missing_quote
	cmp al, 0x27
	je save_string_end
	mov edx, edi ; check binary file limits
	inc edx
	cmp edx, dword [label_start]
	jge not_enough_memory
	stos byte [edi]
	jmp save_string
	save_string_end:
	pop ecx
	pop esi
	jmp db_next
	
	db_number:
	call get_number
	jc db_label
	db_label_ok:
	cmp eax, 0xFF
	ja value_exceeds_range
	mov edx, edi ; check binary file limits
	inc edx
	cmp edx, dword [label_start]
	jge not_enough_memory
	stos byte [edi]
	db_next:
	mov ebx, esi
	add esi, ecx
	call skip_space
	cmp byte [esi], ','
	jne db_end
	inc esi
	call skip_space
	call get_symbol_size
	jmp db_save
	db_end:
	mov esi, ebx
	retd
	db_label:
	mov edx, dword [label_start]
	call find_symbol
	jnc db_label_ok ; jnc = yes label found
	cmp dword [count_pass], 2
	jge invalid_operand
	mov dword [need_pass], 1
	mov eax, 0
	jmp db_label_ok
	
dw_:
	call skip_symbol
	
	dw_save:
	call get_number
	jc dw_label
	dw_label_ok:
	cmp eax, 0xFFFF
	ja value_exceeds_range
	mov edx, edi ; check binary file limits
	add edx, 2
	cmp edx, dword [label_start]
	jge not_enough_memory
	stos word [edi]
	mov ebx, esi
	add esi, ecx
	call skip_space
	cmp byte [esi], ','
	jne dw_end
	inc esi
	call skip_space
	call get_symbol_size
	jmp dw_save
	dw_end:
	mov esi, ebx
	retd
	dw_label:
	mov edx, dword [label_start]
	call find_symbol
	jnc dw_label_ok ; jnc = yes label found
	cmp dword [count_pass], 2
	jge invalid_operand
	mov dword [need_pass], 1
	mov eax, 0
	jmp dw_label_ok
	
dd_:
	call skip_symbol
	
	dd_save:
	call get_number
	jc dd_label
	
	dd_label_ok:
	cmp eax, 0xFFFFFFFF
	ja value_exceeds_range
	mov edx, edi ; check binary file limits
	add edx, 4
	cmp edx, dword [label_start]
	jge not_enough_memory
	stos dword [edi]
	mov ebx, esi
	add esi, ecx
	call skip_space
	cmp byte [esi], ','
	jne dd_end
	inc esi
	call skip_space
	call get_symbol_size
	jmp dd_save
	dd_end:
	mov esi, ebx
	retd
	dd_label:
	mov edx, dword [label_start]
	call find_symbol
	jnc dd_label_ok ; jnc = yes label found
	cmp dword [count_pass], 2
	jge invalid_operand
	mov dword [need_pass], 1
	mov eax, 0
	jmp dd_label_ok
	
times_:
	call skip_symbol
	call get_number
	jc invalid_operand
	cmp eax, 0
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	;push dword [line_number]
	push eax
	call skip_symbol
	cmp al, ':' ; label not allowed
	je invalid_operand
	mov edx, instructions
	call find_symbol
	pop ebx
	jc unknown_symbol
	push eax
	push esi
	push ecx
	times_loop:
	mov ecx, dword [esp]
	mov esi, dword [esp+4]
	mov eax, dword [esp+8]
	push ebx
	call eax ; dword eax
	pop ebx
	mov edx, edi ; check binary file limits
	add edx, 50
	cmp edx, dword [label_start]
	jge not_enough_memory
	dec ebx
	cmp ebx, 0
	jg times_loop
	pop eax ; just pop registers
	pop eax
	pop eax
	;pop dword [line_number]
	retd
	
bt_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xA3
	mov byte [opcode+2], 4
	jmp bt_crs
	
btc_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xBB
	mov byte [opcode+2], 7
	jmp bt_crs
	
btr_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xB3
	mov byte [opcode+2], 6
	jmp bt_crs
	
bts_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xAB
	mov byte [opcode+2], 5
	jmp bt_crs
	
bt_crs:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, operand_size
	call find_symbol
	jc bt_reg
	
	push eax
	call get_address
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc bt_mem_imm8
	pop ebx
	
	cmp ebx, 2
	je bt_m16_r16
	cmp ebx, 4
	je bt_m32_r32
	jmp unvalid_size_operand
	
	bt_m16_r16:
	cmp ah, 2
	jne invalid_operand
	call operand_size_prefix_16
	jmp bt_m_reg
	
	bt_m32_r32:
	cmp ah, 3
	jne invalid_operand
	call operand_size_prefix_32
	
	bt_m_reg:
	mov bl, al
	shl bl, 3
	or bl, byte [mod_rm_byte]
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, bl
	stos byte [edi]
	call sib_disp
	retd
	
	bt_mem_imm8:
	pop ebx
	cmp ebx, 2
	je bt_m16_imm8
	cmp ebx, 4
	je bt_m32_imm8
	jmp unvalid_size_operand
	
	bt_m16_imm8:
	call operand_size_prefix_16
	jmp bt_m_imm8
	
	bt_m32_imm8:
	call operand_size_prefix_32
	
	bt_m_imm8:
	mov bl, byte [opcode+2]
	shl bl, 3
	or bl, byte [mod_rm_byte]
	mov ax, 0xBA0F
	stos word [edi]
	mov al, bl
	stos byte [edi]
	call sib_disp
	call get_imm
	cmp eax, -0x100
	jl value_exceeds_range
	cmp eax, 0xFF
	jg value_exceeds_range
	stos byte [edi]
	retd
	
	bt_reg:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	
	push eax
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc bt_reg_imm8
	pop ebx
	
	cmp bh, 2
	je bt_r16_r16
	cmp bh, 3
	je bt_r32_r32
	jmp invalid_operand
	
	bt_r16_r16:
	cmp bh, ah
	jne invalid_operand
	call operand_size_prefix_16
	jmp bt_reg_reg
	
	bt_r32_r32:
	cmp bh, ah
	jne invalid_operand
	call operand_size_prefix_32
	
	bt_reg_reg:
	shl al, 3
	or al, 11000000b
	or bl, al
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, bl
	stos byte [edi]
	retd
	
	bt_reg_imm8:
	pop ebx
	cmp bh, 2
	je bt_r16_imm8
	cmp bh, 3
	je bt_r32_imm8
	jmp invalid_operand
	
	bt_r16_imm8:
	call operand_size_prefix_16
	jmp bt_r_imm8
	
	bt_r32_imm8:
	call operand_size_prefix_32
	
	bt_r_imm8:
	mov al, byte [opcode+2]
	shl al, 3
	or al, 11000000b
	or bl, al
	mov ax, 0xBA0F
	stos word [edi]
	mov al, bl
	stos byte [edi]
	call get_imm
	cmp eax, -0x100
	jl value_exceeds_range
	cmp eax, 0xFF
	jg value_exceeds_range
	stos byte [edi]
	retd
	
bsf_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xBC
	jmp bsfr_

bsr_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xBD
	jmp bsfr_

bsfr_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	
	push eax
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc bsf_reg
	push eax
	call get_address
	pop eax
	pop ebx
	
	cmp bh, 2
	je bsf_r16_m16
	cmp bh, 3
	je bsf_r32_m32
	jmp unvalid_size_operand
	
	bsf_r16_m16:
	cmp eax, 2
	jne unvalid_size_operand
	call operand_size_prefix_16
	jmp bsf_r_m
	
	bsf_r32_m32:
	cmp eax, 4
	jne unvalid_size_operand
	call operand_size_prefix_32
	
	bsf_r_m:
	shl bl, 3
	or bl, byte [mod_rm_byte]
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, bl
	stos byte [edi]
	call sib_disp
	retd
	
	bsf_reg:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	pop ebx
	
	cmp bh, 2
	je bsf_r16_r16
	cmp bh, 3
	je bsf_r32_r32
	jmp invalid_operand
	
	bsf_r16_r16:
	cmp bh, ah
	jne invalid_operand
	call operand_size_prefix_16
	jmp bsf_r_r
	
	bsf_r32_r32:
	cmp bh, ah
	jne invalid_operand
	call operand_size_prefix_32
	
	bsf_r_r:
	shl bl, 3
	or bl, 11000000b
	or bl, al
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, bl
	stos byte [edi]
	retd
	
bound_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	
	push eax
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc invalid_operand
	push eax
	call get_address
	pop eax
	pop ebx
	
	cmp eax, 2
	je bound_r16_m16
	cmp eax, 4
	je bound_r32_m32
	jmp unvalid_size_operand
	
	bound_r16_m16:
	call operand_size_prefix_16
	cmp bh, 2
	je bound_r_m
	jmp unvalid_size_operand
	
	bound_r32_m32:
	call operand_size_prefix_32
	cmp bh, 3
	jne unvalid_size_operand
	
	bound_r_m:
	shl bl, 3
	or bl, byte [mod_rm_byte]
	mov al, 0x62
	stos byte [edi]
	mov al, bl
	stos byte [edi]
	call sib_disp
	retd
	
binary_:
	call skip_symbol
	cmp byte [esi], 0x27
	jne invalid_operand
	cmp ecx, 2
	jbe invalid_operand
	cmp ecx, 34
	ja invalid_operand
	push esi
	push ecx
	inc esi
	push edi
	mov edi, bin_name
	mov dword [input_bin], edi
	copy_binary_name:
	lods byte [esi]
	cmp al, 0x27
	je copy_binary_ok
	cmp al, 0
	je invalid_operand
	cmp al, 13
	je invalid_operand
	stos byte [edi]
	jmp copy_binary_name
	copy_binary_ok:
	xor al,al
	stos byte [edi]
	pop edi
	mov edx, dword [input_bin]
	call open_file
	jc binary_file_nf
	mov eax, 2
	mov edx, 0
	call lseek_file
	push eax
	mov eax, 0
	mov edx, 0
	call lseek_file
	pop ecx ; file size
	mov edx, edi ; check binary file limits
	add edx, ecx
	cmp edx, dword [label_start]
	jge not_enough_memory
	push ecx
	mov edx, edi
	call read_file
	call close_file
	pop ecx
	add edi, ecx
	pop ecx
	pop esi
	retd
	
aaa_:
	mov al, 0x37
	stos byte [edi]
	retd
	
aad_:
	mov ax, 0x0AD5
	stos word [edi]
	retd
	
aam_:
	mov ax, 0x0AD4
	stos word [edi]
	retd

aas_:
	mov al, 0x3F
	stos byte [edi]
	retd
	
adc_:
	mov byte [opcode], 0x10
	mov byte [opcode+1], 0x02
	jmp same_code_01
	
add_:
	mov byte [opcode], 0x00
	mov byte [opcode+1], 0x00
	jmp same_code_01
	
and_:
	mov byte [opcode], 0x20
	mov byte [opcode+1], 0x04
	jmp same_code_01
	
same_code_01:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, operand_size
	call find_symbol
	jc sc01_reg ; operand size found ?
	cmp eax, 1
	je sc01_m8
	cmp eax, 2
	je sc01_m16
	cmp eax, 4
	je sc01_m32
	jmp unvalid_size_operand
	
	sc01_m8:
	call get_address
	call find_source_operand
	
	mov edx, all_registers
	call find_symbol
	jc sc01_m8_imm8
	cmp ah, 1
	jne invalid_operand
	
	sc01_m8_r8:
	mov ah, al
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, byte [opcode] 
	stos word [edi]
	call sib_disp
	retd
	
	sc01_m8_imm8:
	call get_imm
	cmp eax, -0x100
	jl value_exceeds_range
	cmp eax, 0xFF
	jg value_exceeds_range
	push eax
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, 0x80
	stos word [edi]
	call sib_disp
	pop eax
	stos byte [edi]
	retd
	
	sc01_m16:
	call get_address
	call operand_size_prefix_16
	call find_source_operand
	
	mov edx, all_registers
	call find_symbol
	jc sc01_m16_imm16
	cmp ah, 2
	jne invalid_operand
	
	sc01_m16_r16:
	mov ah, al
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, byte [opcode]
	add al, 1 ;inc al
	stos word [edi]
	call sib_disp
	retd
	
	
	sc01_m16_imm16:
	call get_imm
	;jc invalid_operand
	cmp eax, -0x10000
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	push eax
	cmp ax, -80
	jae sc01_m16_simm8
	cmp ax, 0x7F
	jbe sc01_m16_simm8
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, 0x81
	stos word [edi]
	call sib_disp
	pop eax
	stos word [edi]
	retd
	
	; sign extended immediate byte
	sc01_m32_simm8:
	sc01_m16_simm8:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, 0x83
	stos word [edi]
	call sib_disp
	pop eax
	stos byte [edi]
	retd
	
	sc01_m32:
	call get_address
	call operand_size_prefix_32
	call find_source_operand
	
	mov edx, all_registers
	call find_symbol
	jc sc01_m32_imm32
	cmp ah, 3
	jne invalid_operand
	
	sc01_m32_r32:
	mov ah, al
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, byte [opcode]
	add al, 1 ;inc al
	stos word [edi]
	call sib_disp
	retd
	
	sc01_m32_imm32:
	call get_imm
	;jc invalid_operand
	;cmp eax, 0xFFFFFFFF
	;ja unvalid_size_operand
	push eax
	cmp eax, -0x80
	jae sc01_m32_simm8
	cmp eax, 0x7F
	jbe sc01_m32_simm8
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, 0x81
	stos word [edi]
	call sib_disp
	pop eax
	stos dword [edi]
	retd
	
	sc01_reg:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	je sc01_r8
	cmp ah, 2
	je sc01_r16
	cmp ah, 3
	je sc01_r32
	jmp invalid_operand
	
	sc01_r8:
	push eax ; eax=distination register code
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc sc01_r8_m8 ; sc01_al_imm8
	cmp ah, 1
	jne invalid_operand
	
	sc01_r8_r8:
	push eax
	mov al, 0x00
	add al, byte [opcode]
	stos byte [edi]
	pop eax
	shl al, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stos byte [edi]
	retd
	
	sc01_r8_m8:
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, operand_size
	call find_symbol
	jc sc01_al_imm8
	cmp eax, 1
	jne unvalid_size_operand
	call get_address
	mov al, byte [opcode]
	add al, 0x02
	stos byte [edi]
	pop eax ; now eax=distination register code
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	sc01_al_imm8:
	call get_imm
	cmp eax, -0x100
	jl value_exceeds_range
	cmp eax, 0xFF
	jg value_exceeds_range
	mov edx, eax
	pop eax
	cmp al, 0
	jne sc01_r8_imm8
	mov eax, edx
	shl eax, 8
	mov al, 0x04
	add al, byte [opcode]
	stos word [edi]
	retd
	
	sc01_r8_imm8:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, al
	or ah, 11000000b
	mov al, 0x80
	stos word [edi]
	mov eax, edx
	stos byte [edi]
	retd
	
	sc01_r16:
	call operand_size_prefix_16
	push eax ; eax=distination register code
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc sc01_r16_m16 ;sc01_ax_imm16
	cmp ah, 2
	jne invalid_operand
	
	sc01_r16_r16:
	push eax
	mov al, 0x01
	add al, byte [opcode]
	stos byte [edi]
	pop eax
	shl al, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stos byte [edi]
	retd
	
	sc01_r16_m16:
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, operand_size
	call find_symbol
	jc sc01_ax_imm16
	cmp eax, 2
	jne unvalid_size_operand
	call get_address
	mov al, byte [opcode]
	add al, 0x03
	stos byte [edi]
	pop eax ; now eax=distination register code
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	sc01_ax_imm16:
	call get_imm
	;jc invalid_operand
	pop edx  ; edx=distination register code
	cmp eax, -0x10000
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	push eax
	cmp ax, -0x80
	jae sc01_r16_imm8
	cmp ax, 0x7F
	jbe sc01_r16_imm8
	cmp dl, 0
	jne sc01_r16_imm16
	mov al, 0x05
	add al, byte [opcode]
	stos byte [edi]
	pop eax
	stos word [edi]
	retd
	
	sc01_r16_imm16:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, dl
	or ah, 11000000b
	mov al, 0x81
	stos word [edi]
	pop eax
	stos word [edi]
	retd
	
	; sign extended immediate byte
	sc01_r32_imm8:
	sc01_r16_imm8:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, dl
	or ah, 11000000b
	mov al, 0x83
	stos word [edi]
	pop eax
	stos byte [edi]
	retd
	
	sc01_r32:
	call operand_size_prefix_32
	push eax ; eax=distination register code
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc sc01_r32_m32 ; sc01_eax_imm32
	cmp ah, 3
	jne invalid_operand
	
	sc01_r32_r32:
	push eax
	mov al, 0x01
	add al, byte [opcode]
	stos byte [edi]
	pop eax
	shl al, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stos byte [edi]
	retd
	
	sc01_r32_m32:
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, operand_size
	call find_symbol
	jc sc01_eax_imm32
	cmp eax, 4
	jne unvalid_size_operand
	call get_address
	mov al, byte [opcode]
	add al, 0x03
	stos byte [edi]
	pop eax ; now eax=distination register code
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	sc01_eax_imm32:
	call get_imm
	pop edx  ; edx=distination register code
	;jc invalid_operand
	;cmp eax, 0xFFFFFFFF
	;ja unvalid_size_operand
	push eax
	cmp eax, -0x80
	jae sc01_r32_imm8
	cmp eax, 0x7F
	jbe sc01_r32_imm8
	cmp dl, 0 ; check if eax distination ?
	jne sc01_r32_imm32
	mov al, 0x05
	add al, byte [opcode]
	stos byte [edi]
	pop eax
	stos dword [edi]
	retd
	
	sc01_r32_imm32:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, dl
	or ah, 11000000b
	mov al, 0x81
	stos word [edi]
	pop eax
	stos dword [edi]
	retd
	
arpl_:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc arpl_reg
	cmp eax, 2
	jne unvalid_size_operand
	call get_address
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	jne invalid_operand
	shl al, 3
	or al, byte [mod_rm_byte]
	mov ah, al
	mov al, 0x63
	stos word [edi]
	call sib_disp
	retd
	
	arpl_reg:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	jne invalid_operand
	push eax
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	jne invalid_operand
	pop ebx
	shl al, 3
	or al, bl
	or al, 11000000b
	mov ah, al
	mov al, 0x63
	stos word [edi]
	retd
	
call_:
	mov byte [opcode], 0xE8
	mov byte [opcode+1], 2
	mov byte [opcode+2], 0x9A
	jmp jmp_call

	
cbw_:
	call operand_size_prefix_16
	mov al, 0x98
	stos byte [edi]
	retd
	
cwde_:
	call operand_size_prefix_32
	mov al, 0x98
	stos byte [edi]
	retd
	
clc_:
	mov al, 0xF8
	stos byte [edi]
	retd
	
cld_:
	mov al, 0xFC
	stos byte [edi]
	retd
	
cli_:
	mov al, 0xFA
	stos byte [edi]
	retd
	
clts_:
	mov ax, 0x060F
	stos word [edi]
	retd

cmc_:
	mov al, 0xF5
	stos byte [edi]
	retd
	
cmp_:
	mov byte [opcode], 0x38
	mov byte [opcode+1], 0x07
	jmp same_code_01
	
cmps_:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc invalid_operand ; operand size found ?
	push eax
	call get_address
	cmp byte [address_type], 1
	jne invalid_address
	push eax
	call find_source_operand
	mov ecx, 0
	push edi
	call get_address
	pop edi
	cmp byte [address_type], 1
	jne invalid_address
	cmp byte [segment_byte], 0
	je cmps_no_seg
	cmp byte [segment_byte], 0x26
	jne invalid_address
	cmps_no_seg:
	pop edx
	cmp ax, 0x0307
	je cmps_ma32_ma32
	cmp ax, 0x0205
	je cmps_ma16_ma16
	jmp invalid_address
	cmps_ma32_ma32:
	cmp dx, 0x0306
	jne invalid_address
	jmp cmps_m_m
	cmps_ma16_ma16:
	cmp dx, 0x0204
	jne invalid_address
	cmps_m_m:
	pop eax
	cmp eax, 1
	je cmps_m8
	cmp eax, 2
	je cmps_m16
	cmp eax, 4
	je cmps_m32
	jmp unvalid_size_operand
	cmps_m8:
	jmp cmpsb_
	cmps_m16:
	jmp cmpsw_
	cmps_m32:
	jmp cmpsd_
	
cmpsb_:
	mov al, 0xA6
	stos byte [edi]
	retd
	
cmpsw_:
	call operand_size_prefix_16
	mov al, 0xA7
	stos byte [edi]
	retd
	
cmpsd_:
	call operand_size_prefix_32
	mov al, 0xA7
	stos byte [edi]
	retd
	
cwd_:
	call operand_size_prefix_16
	mov al, 0x99
	stos byte [edi]
	retd
	
cdq_:
	call operand_size_prefix_32
	mov al, 0x99
	stos byte [edi]
	retd
	
daa_:
	mov al, 0x27
	stos byte [edi]
	retd
	
das_:
	mov al, 0x2F
	stos byte [edi]
	retd
	
dec_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	je dec_r16
	cmp ah, 3
	je dec_r32
	jmp invalid_operand
	
	dec_r16:
	call operand_size_prefix_16
	add al, 0x48
	stos byte [edi]
	retd
	
	dec_r32:
	call operand_size_prefix_32
	add al, 0x48
	stos byte [edi]
	retd
	
div_:
	mov byte [opcode], 0xF6
	mov byte [opcode+1], 0x06
	jmp same_code_02
	
enter_:
	call skip_symbol
	call get_number
	jc invalid_operand
	cmp eax, 0xFFFF
	ja value_exceeds_range
	push eax
	call find_source_operand
	call get_number
	jc invalid_operand
	cmp eax, 0xFF
	ja value_exceeds_range
	pop ebx
	mov cl, al
	mov al, 0xC8
	stos byte [edi]
	mov ax, bx
	stos word [edi]
	mov al, cl
	stos byte [edi]
	retd
	
hlt_:
	mov al, 0xF4
	stos byte [edi]
	retd
	
idiv_:
	mov byte [opcode], 0xF6
	mov byte [opcode+1], 0x07
	jmp same_code_02
	

imul_:
	mov byte [opcode], 0xF6
	mov byte [opcode+1], 0x05
	
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	je imul_r8
	cmp ah, 2
	je imul_r16
	cmp ah, 3
	je imul_r32
	jmp invalid_operand
	
	imul_r8:
	jmp sc02_r8
	
	imul_r16:
	push eax
	call operand_size_prefix_16
	add esi, ecx
	call skip_space
	mov ecx, 0
	cmp byte [esi], ','
	jne sc02__r16
	inc esi
	call skip_space
	call get_symbol_size
	
	call get_number
	jc invalid_operand
	cmp eax, -0x80  ; 128 bytes before the end of the instruction
	jl imul_r16_imm16
	cmp eax, 0x7F   ; 127 bytes after the end of the instruction
	jg imul_r16_imm16
	
	imul_r32_imm8:
	imul_r16_imm8:
	pop edx
	push eax
	mov al, 0x6B
	stos byte [edi]
	mov ebx, edx
	shl bl, 3
	or bl, dl
	or bl, 11000000b
	mov al, bl
	stos byte [edi]
	pop eax
	stos byte [edi]
	retd
	
	imul_r16_imm16:
	cmp eax, -0x8000 ; -32768
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	pop edx
	push eax
	mov al, 0x69
	stos byte [edi]
	mov ebx, edx
	shl bl, 3
	or bl, dl
	or bl, 11000000b
	mov al, bl
	stos byte [edi]
	pop eax
	stos word [edi]
	retd
	
	imul_r32:
	push eax
	call operand_size_prefix_32
	add esi, ecx
	call skip_space
	mov ecx, 0
	cmp byte [esi], ','
	jne sc02__r32
	inc esi
	call skip_space
	call get_symbol_size
	
	call get_number
	jc invalid_operand
	cmp eax, -0x80  ; 128 bytes before the end of the instruction
	jl imul_r32_imm32
	cmp eax, 0x7F   ; 127 bytes after the end of the instruction
	jg imul_r32_imm32
	
	jmp imul_r32_imm8
	
	imul_r32_imm32:
	pop edx
	push eax
	mov al, 0x69
	stos byte [edi]
	mov ebx, edx
	shl bl, 3
	or bl, dl
	or bl, 11000000b
	mov al, bl
	stos byte [edi]
	pop eax
	stos dword [edi]
	retd

	
same_code_02:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	je sc02_r8
	cmp ah, 2
	je sc02_r16
	cmp ah, 3
	je sc02_r32
	jmp invalid_operand
	
	sc02_r8:
	push eax
	mov al, byte [opcode]
	stos byte [edi]
	pop eax
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or al, bl
	stos byte [edi]
	retd
	
	sc02_r16:
	push eax
	call operand_size_prefix_16
	sc02__r16:
	mov al, byte [opcode]
	add al, 1
	stos byte [edi]
	pop eax
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or al, bl
	stos byte [edi]
	retd
	
	sc02_r32:
	push eax
	call operand_size_prefix_32
	sc02__r32:
	mov al, byte [opcode]
	add al, 1
	stos byte [edi]
	pop eax
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or al, bl
	stos byte [edi]
	retd
	
in_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand

	cmp ah, 1
	je in_al_imm8
	cmp ah, 2
	je in_ax_imm8
	cmp ah, 3
	je in_eax_imm8
	jmp invalid_operand
	
	in_al_imm8:
	cmp al, 0
	jne invalid_operand
	call find_source_operand
	mov al, 0xE4
	stos byte [edi]
	call get_number
	jc invalid_operand
	cmp eax, 0xFF
	ja value_exceeds_range
	stos byte [edi]
	retd
	
	in_ax_imm8:
	cmp al, 0
	jne invalid_operand
	call operand_size_prefix_16
	call find_source_operand
	mov al, 0xE5
	stos byte [edi]
	call get_number
	jc invalid_operand
	cmp eax, 0xFF
	ja value_exceeds_range
	stos byte [edi]
	retd
	
	in_eax_imm8:
	cmp al, 0
	jne invalid_operand
	call operand_size_prefix_32
	call find_source_operand
	mov al, 0xE5
	stos byte [edi]
	call get_number
	jc invalid_operand
	cmp eax, 0xFF
	ja value_exceeds_range
	stos byte [edi]
	retd
	
inc_:
	call skip_symbol
	
	mov edx, operand_size
	call find_symbol
	jc inc_reg ; operand size found ?
	cmp eax, 1
	je inc_m8
	cmp eax, 2
	je inc_m16
	cmp eax, 4
	je inc_m32
	jmp unvalid_size_operand
	
	inc_reg:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	je inc_r16
	cmp ah, 3
	je inc_r32
	jmp invalid_operand
	
	inc_m8:
	call skip_symbol
	call get_address
	mov ah, 0
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, 0xFE
	stos word [edi]
	call sib_disp
	retd
	
	inc_m16:
	call skip_symbol
	call operand_size_prefix_16
	call get_address
	mov ah, 0
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, 0xFF
	stos word [edi]
	call sib_disp
	retd
	
	inc_m32:
	call skip_symbol
	call operand_size_prefix_32
	call get_address
	mov ah, 0
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, 0xFF
	stos word [edi]
	call sib_disp
	retd
	
	inc_r16:
	call operand_size_prefix_16
	add al, 0x40
	stos byte [edi]
	retd
	
	inc_r32:
	call operand_size_prefix_32
	add al, 0x40
	stos byte [edi]
	retd
	
insb_:
	mov al, 0x6C
	stos byte [edi]
	retd
	
insw_:
	call operand_size_prefix_16
	mov al, 0x6D
	stos byte [edi]
	retd
	
insd_:
	call operand_size_prefix_32
	mov al, 0x6D
	stos byte [edi]
	retd
	
int_:
	call skip_symbol
	call get_number
	jc invalid_operand
	cmp eax, 0xFF
	ja value_exceeds_range
	shl eax, 8
	mov al, 0xCD
	stos word [edi]
	retd
	
int3_:
	mov al, 0xCC
	stos byte [edi]
	retd
	
into_:
	mov al, 0xCE
	stos byte [edi]
	retd

iretd_:
	call operand_size_prefix_32
iret_:
	mov al, 0xCF
	stos byte [edi]
	retd
	
ja_:
	mov byte [opcode], 0x77
	jmp jcc_
	
jae_:
	mov byte [opcode], 0x73
	jmp jcc_
	
jb_:
	mov byte [opcode], 0x72
	jmp jcc_
	
jbe_:
	mov byte [opcode], 0x76
	jmp jcc_
	
jc_:
	mov byte [opcode], 0x72
	jmp jcc_
	
jcxz_:
	call address_size_prefix_16
	mov byte [opcode], 0xE3
	jmp jcc_
	
jecxz_:
	call address_size_prefix_32
	mov byte [opcode], 0xE3
	jmp jcc_
	
je_:
	mov byte [opcode], 0x74
	jmp jcc_
	
jg_:
	mov byte [opcode], 0x7F
	jmp jcc_
	
jge_:
	mov byte [opcode], 0x7D
	jmp jcc_
	
jl_:
	mov byte [opcode], 0x7C
	jmp jcc_
	
jle_:
	mov byte [opcode], 0x7E
	jmp jcc_

jna_:
	mov byte [opcode], 0x76
	jmp jcc_
	
jnae_:
	mov byte [opcode], 0x72
	jmp jcc_
	
jnb_:
	mov byte [opcode], 0x73
	jmp jcc_
	
jnbe_:
	mov byte [opcode], 0x77
	jmp jcc_
	
jnc_:
	mov byte [opcode], 0x73
	jmp jcc_
	
jne_:
	mov byte [opcode], 0x75
	jmp jcc_
	
jng_:
	mov byte [opcode], 0x7E
	jmp jcc_
	
jnge_:
	mov byte [opcode], 0x7C
	jmp jcc_
	
jnl_:
	mov byte [opcode], 0x7D
	jmp jcc_
	
jnle_:
	mov byte [opcode], 0x7F
	jmp jcc_
	
jno_:
	mov byte [opcode], 0x71
	jmp jcc_
	
jnp_:
	mov byte [opcode], 0x7B
	jmp jcc_
	
jns_:
	mov byte [opcode], 0x79
	jmp jcc_
	
jo_:
	mov byte [opcode], 0x70
	jmp jcc_
	
jp_:
	mov byte [opcode], 0x7A
	jmp jcc_
	
jpo_:
	mov byte [opcode], 0x7B
	jmp jcc_
	
js_:
	mov byte [opcode], 0x78
	jmp jcc_
	

jcc_:
	call skip_symbol
	
	jcc_rel8:
	call imm_number
	mov ebx, edi
	add ebx, 2 ; 2 = size of instruction
	sub ebx, dword [binary_start]
	sub eax, ebx
	sub eax, dword [org_value]
	cmp eax, -0x80  ; 128 bytes before the end of the instruction
	jl jcc_rel16
	cmp eax, 0x7F   ; 127 bytes after the end of the instruction
	jg jcc_rel16
	shl eax, 8
	mov al, byte [opcode]
	stos word [edi]
	retd
	
	jcc_rel16:
	cmp byte [code_type], 32
	je jcc_rel32
	call operand_size_prefix_16
	sub eax, 2 ; 2+2=4 = size of instruction	
	cmp eax, -0x8000 ; -32768
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	cmp byte [opcode], 0xE3
	je value_exceeds_range
	shl eax, 16
	mov al, 0x0F
	mov ah, byte [opcode]
	add ah, 0x10
	stos dword [edi]
	retd
	
	jcc_rel32:
	call operand_size_prefix_32
	sub eax, 4 ; 2+4=6 = size of instruction
	cmp byte [opcode], 0xE3
	je value_exceeds_range
	push eax
	mov al, 0x0F
	mov ah, byte [opcode]
	add ah, 0x10
	stos word [edi]
	pop eax
	stos dword [edi]
	retd
	
	
jmp_:
	mov byte [opcode], 0xE9
	mov byte [opcode+1], 4
	mov byte [opcode+2], 0xEA
	
jmp_call:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	cmp word [esi], '0x'
	je jmp_ptr16
	
	mov edx, operand_size
	call find_symbol
	jc jmp_reg
	cmp eax, 2
	je jmp_m16
	cmp eax, 4
	je jmp_m32
	jmp unvalid_size_operand
	
	jmp_m16:
	call skip_symbol
	call operand_size_prefix_16
	cmp byte [esi], '['
	jne invalid_operand
	call get_address
	mov ah, byte [opcode+1] ; 2
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, 0xFF
	stos word [edi]
	call sib_disp
	retd
	
	jmp_m32:
	call skip_symbol
	call operand_size_prefix_32
	cmp byte [esi], '['
	jne invalid_operand
	call get_address
	mov ah, byte [opcode+1] ; 2
	shl ah, 3
	or ah, byte [mod_rm_byte]
	mov al, 0xFF
	stos word [edi]
	call sib_disp
	retd
	
	
	jmp_reg:
	mov edx, all_registers
	call find_symbol
	jc jmp_rel8
	
	jmp_r16:
	cmp ah, 2
	jne jmp_r32
	call operand_size_prefix_16
	mov ah, byte [opcode+1] ; 4
	shl ah, 3
	or ah, 11000000b
	or ah, al
	mov al, 0xFF
	stos word [edi]
	retd
	
	jmp_r32:
	cmp ah, 3
	jne invalid_operand
	call operand_size_prefix_32
	mov ah, byte [opcode+1] ; 4
	shl ah, 3
	or ah, 11000000b
	or ah, al
	mov al, 0xFF
	stos word [edi]
	retd
	
	jmp_rel8:
	call imm_number
	mov ebx, edi
	add ebx, 2 ; 2 = size of instruction
	sub ebx, dword [binary_start]
	sub eax, ebx
	sub eax, dword [org_value]
	cmp byte [opcode], 0xE8
	je call_rel16
	cmp eax, -0x80  ; 128 bytes before the end of the instruction
	jl jmp_rel16
	cmp eax, 0x7F   ; 127 bytes after the end of the instruction
	jg jmp_rel16
	shl eax, 8
	mov al, 0xEB
	stos word [edi]
	retd
	
	call_rel16:
	jmp_rel16: ; jmp near rel16
	cmp byte [code_type], 32
	je jmp_rel32
	;call operand_size_prefix_16
	sub eax, 1 ; 2+1=3 = size of instruction	
	cmp eax, -0x8000 ; -32768
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	push eax
	mov al, byte [opcode] ; 0xE9
	stos byte [edi]
	pop eax
	stos word [edi]
	retd
	
	jmp_rel32: ; jmp near rel32
	;call operand_size_prefix_32
	sub eax, 3 ; 2+3=5 = size of instruction
	push eax
	mov al, byte [opcode] ; 0xE9
	stos byte [edi]
	pop eax
	stos dword [edi]
	retd
	
	jmp_ptr16:
	call get_number
	jc invalid_operand
	cmp eax, 0
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	push eax
	add esi, ecx
	cmp byte [esi], ':'
	jne invalid_operand
	inc esi
	call skip_space
	call get_symbol_size
	mov edx, operand_size
	call find_symbol
	jc operand_size_ns
	cmp eax, 2
	je jmp_ptr16_16
	cmp eax, 4
	je jmp_ptr16_32
	jmp unvalid_size_operand

	jmp_ptr16_16: ; jmp far dword
	call skip_symbol
	call get_number
	jc invalid_operand
	cmp eax, 0
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	call operand_size_prefix_16
	push eax
	mov al, byte [opcode+2] ; 0xEA
	stos byte [edi]
	pop eax
	stos word [edi]
	pop eax
	stos word [edi]
	retd
	
	jmp_ptr16_32: ; jmp far pword
	call skip_symbol
	call get_number
	jc invalid_operand
	call operand_size_prefix_32
	push eax
	mov al, byte [opcode+2] ; 0xEA
	stos byte [edi]
	pop eax
	stos dword [edi]
	pop eax
	stos word [edi]
	retd
	
lar_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 2
	jmp lar_lsl
	
lsl_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 3
	jmp lar_lsl

lar_lsl:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	
	push eax
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc lar_r_m
	pop ebx
	
	cmp ah, 2
	jne unvalid_size_operand
	cmp bh, 2
	je lar_r16_r16
	cmp bh, 3
	je lar_r32_r16
	jmp unvalid_size_operand
	
	lar_r16_r16:
	call operand_size_prefix_16
	jmp lar_r_r
	
	lar_r32_r16:
	call operand_size_prefix_32
	
	lar_r_r:
	shl bl, 3
	or bl, 11000000b
	or bl, al
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, bl
	stos byte [edi]
	retd
	
	lar_r_m:
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc invalid_operand
	push eax
	call get_address
	pop eax
	
	pop ebx
	
	cmp eax, 2
	jne unvalid_size_operand ; check again
	cmp bh, 2
	je lar_r16_m16
	cmp bh, 3
	je lar_r32_m16
	jmp unvalid_size_operand
	
	lar_r16_m16:
	call operand_size_prefix_16
	jmp lar_reg_mem
	
	lar_r32_m16:
	call operand_size_prefix_32
	
	lar_reg_mem:
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, byte [mod_rm_byte]
	shl bl, 3
	or al, bl
	stos byte [edi]
	call sib_disp
	retd
	
lds_:
	mov byte [opcode], 0xC5
	jmp l_s_
	
lss_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xB2
	jmp l_s_
	
les_:
	mov byte [opcode], 0xC4
	jmp l_s_
	
lfs_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xB4
	jmp l_s_
	
lgs_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xB5
	jmp l_s_
	
	
l_s_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	
	push eax
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc invalid_operand
	push eax
	call get_address
	pop eax
	pop ebx
	
	cmp eax, 4
	je l_s_r16_m1616
	cmp eax, 6
	je l_s_r32_m1632
	jmp unvalid_size_operand
	
	l_s_r16_m1616:
	cmp bh, 2
	jne invalid_operand
	call operand_size_prefix_16
	jmp l_s_reg_mem
	
	l_s_r32_m1632:
	cmp bh, 3
	jne invalid_operand
	call operand_size_prefix_32
	
	l_s_reg_mem:
	cmp byte [opcode], 0x0F
	je lsfg_reg_mem
	mov al, byte [opcode]
	stos byte [edi]
	jmp lsfg_reg
	lsfg_reg_mem:
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	lsfg_reg:
	mov al, byte [mod_rm_byte]
	shl bl, 3
	or al, bl
	stos byte [edi]
	call sib_disp
	retd
	
lea_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	
	push eax
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc invalid_operand
	call get_address
	pop ebx
	cmp bh, 2
	je lea_r16_m
	cmp bh, 3
	je lea_r32_m
	jmp unvalid_size_operand
	
	lea_r16_m:
	call operand_size_prefix_16
	jmp lea_r_m
	lea_r32_m:
	call operand_size_prefix_32
	
	lea_r_m:
	mov al, 0x8D
	stos byte [edi]
	mov al, byte [mod_rm_byte]
	shl bl, 3
	or al, bl
	stos byte [edi]
	call sib_disp
	retd
	
ltr_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0
	mov byte [opcode+2], 3
	jmp oss_word
	
str_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0
	mov byte [opcode+2], 1
	jmp oss_word
	
lldt_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0
	mov byte [opcode+2], 2
	jmp oss_word
	
lmsw_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 1
	mov byte [opcode+2], 6
	jmp oss_word
	
sldt_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0
	mov byte [opcode+2], 0
	jmp oss_word
	
smsw_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 1
	mov byte [opcode+2], 4
	jmp oss_word
	
verr_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0
	mov byte [opcode+2], 4
	jmp oss_word
	
verw_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0
	mov byte [opcode+2], 5
	jmp oss_word

oss_word:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc ltr_r16
	cmp eax, 2
	jne unvalid_size_operand
	call get_address
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, byte [opcode+2]
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	ltr_r16:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	jne unvalid_size_operand
	mov al, byte [opcode+2]
	shl al, 3
	or al, 11000000b
	mov bl, al
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, bl
	stos byte [edi]
	retd
	
	
lahf_:
	mov al, 0x9F
	stos byte [edi]
	retd
	
leave_:
	mov al, 0xC9
	stos byte [edi]
	retd
	
lgdt_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 1
	mov byte [opcode+2], 2
	jmp lsdt_
	
lidt_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 1
	mov byte [opcode+2], 3
	jmp lsdt_
	
sgdt_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 1
	mov byte [opcode+2], 0
	jmp lsdt_
	
sidt_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 1
	mov byte [opcode+2], 1
	jmp lsdt_
	
	
lsdt_:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc invalid_operand
	cmp eax, 6
	jne unvalid_size_operand
	call get_address
	
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, byte [opcode+2]
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	
lock_:
	mov al, 0xF0
	stos byte [edi]
	retd
	
lods_:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc invalid_operand ; operand size found ?
	push eax
	call get_address
	cmp byte [address_type], 1
	jne invalid_address
	cmp ax, 0x0306
	je lods_m
	cmp ax, 0x0204
	je lods_m
	jmp invalid_address
	lods_m:
	pop eax
	cmp eax, 1
	je lods_m8
	cmp eax, 2
	je lods_m16
	cmp eax, 4
	je lods_m32
	jmp unvalid_size_operand
	lods_m8:
	jmp lodsb_
	lods_m16:
	jmp lodsw_
	lods_m32:
	jmp lodsd_
	
lodsb_:
	mov al, 0xAC
	stos byte [edi]
	retd
	
lodsw_:
	call operand_size_prefix_16
	mov al, 0xAD
	stos byte [edi]
	retd
	
lodsd_:
	call operand_size_prefix_32
	mov al, 0xAD
	stos byte [edi]
	retd
	
loop_:
	call skip_symbol
	call imm_number
	mov ebx, edi
	add ebx, 2 ; 2 = size of instruction
	sub ebx, dword [binary_start]
	sub eax, ebx
	sub eax, dword [org_value]
	cmp eax, -0x80  ; 128 bytes before the end of the instruction
	jl value_exceeds_range
	cmp eax, 0x7F   ; 127 bytes after the end of the instruction
	jg value_exceeds_range
	shl eax, 8
	mov al, 0xE2
	stos word [edi]
	retd
	
	
;=================================
; add prefix ( Segment / address )
; to instruction
; and ret values of:
; mod_rm_byte db 0
; sib_byte    db 0
; disp_byte   dd 0
;=================================
get_address:
	add esi, ecx
	call skip_space
	cmp byte [esi], '['
	jne invalid_address
	inc esi
	call skip_space
	call get_symbol_size
	
	mov byte [segment_byte], 0
	mov byte [address_type], 0
	mov byte [mod_rm_byte], 0
	mov byte [sib_byte], 0
	mov byte [sib_size], 0
	mov dword [disp_byte], 0
	mov byte [disp_size], 0
	mov byte [disp_sign], 0
	
	mov edx, all_registers
	call find_symbol
	jc no_segment_reg
	cmp ah, 4
	jne no_segment_reg
	shr eax, 16
	
	mov byte [segment_byte], al
	cmp al, 0x3E
	je defaut_segment
	stos byte [edi]
	defaut_segment:
	
	call skip_symbol  ; check again
	cmp al, ':'
	jne invalid_address
	inc esi
	call skip_space
	call get_symbol_size
	no_segment_reg:
	
	mov edx, register_index
	call find_symbol
	jc disp_address ; just address alone
	
	or byte [mod_rm_byte], al ; save it in case no other index register found
	push eax
	
	cmp ah, 3
	je reg_index_32
	cmp ah, 2
	jne invalid_address
	
	reg_index_16:
	call address_size_prefix_16
	add esi, ecx
	call skip_space
	cmp byte [esi], ']'
	je check_bp   ; just index register alone
	cmp byte [esi], '+'
	je get_disp
	cmp byte [esi], '-'
	je get_disp
	jmp invalid_address
	
	reg_index_32:
	call address_size_prefix_32
	add esi, ecx
	call skip_space
	cmp byte [esi], ']'
	je check_esp_ebp   ; just index register alone
	cmp byte [esi], '+'
	je get_disp
	cmp byte [esi], '-'
	je get_disp
	
	jmp invalid_address
	
	check_esp_ebp:
	mov eax, dword [esp]
	cmp al, 5
	je bp_ebp
	cmp al, 4
	jne index_register_alone ; ret_address_end
	
	or byte [mod_rm_byte], 00000100b ; MODRM_RM_SIB
	mov byte [sib_byte], 0x24 ;fx; fix butter
	mov byte [sib_size], 1
	jmp ret_address_end
	
	check_bp:
	mov eax, dword [esp]
	cmp al, 6
	jne index_register_alone ; ret_address_end
	
	bp_ebp:
	mov dword [disp_byte], 0
	mov byte [disp_size], 1
	or byte [mod_rm_byte], 01000000b ; MEMORY_DISP_8
	mov ecx, 1 ; to skipe  ']'
	pop eax
	ret
	
	index_register_alone:
	mov byte [address_type], 1
	
	ret_address_end:
	mov ecx, 1 ; to skipe  ']'
	pop eax
	ret
	
	
address_type:
db 0

disp_sign:
db 0
disp_size:
db 0	
sib_size:
db 0

prefix_byte:
dd 0

mod_rm_byte:
db 0
sib_byte:
db 0
disp_byte:
dd 0

segment_byte:
db 0
rex_byte:
db 0
imm_byte:
dd 0

; MEMORY_        = 00000000b
; MEMORY_DISP_8  = 01000000b
; MEMORY_DISP_16 = 10000000b
; MEMORY_DISP_32 = 10000000b
; REGISTER_      = 11000000b
; DISP_16        = 00000110b
; DISP_32        = 00000101b
; MODRM_RM_SIB   = 00000100b
; SCALE_FACTOR_1 = 00000000b
; SCALE_FACTOR_2 = 01000000b
; SCALE_FACTOR_4 = 10000000b
; SCALE_FACTOR_8 = 11000000b


get_sib:
	cmp al, 4
	je invalid_address
	or byte [mod_rm_byte], 00000100b ; MODRM_RM_SIB
	shl al, 3
	or al, dl
	mov byte [sib_byte], al
	mov byte [sib_size], 1
	
	add esi, ecx
	call skip_space
	cmp byte [esi], ']'
	je ret_address_end
	cmp byte [esi], '+'
	je no_address_end
	cmp byte [esi], '-'
	je no_address_end
	cmp byte [esi], '*'
	jne invalid_address
	inc esi ; skip sign
	call skip_space
	call get_symbol_size
	
	call get_number
	jc invalid_address
	cmp eax, 1
	je check_address_end
	cmp eax, 0
	je sib_scale_1
	cmp eax, 2
	je sib_scale_2
	cmp eax, 4
	je sib_scale_4
	cmp eax, 8
	je sib_scale_8
	jmp invalid_address
	
	sib_scale_1:
	mov byte [sib_byte], 0
	mov byte [sib_size], 0
	mov byte [mod_rm_byte], dl
	jmp check_address_end
	sib_scale_2:
	or byte [sib_byte], 01000000b ; SCALE_FACTOR_2
	jmp check_address_end
	sib_scale_4:
	or byte [sib_byte], 10000000b ; SCALE_FACTOR_4
	jmp check_address_end
	sib_scale_8:
	or byte [sib_byte], 11000000b ; SCALE_FACTOR_8
	jmp check_address_end
	
	
get_disp:
	mov al, byte [esi]
	mov byte [disp_sign], al
	
	inc esi ; skip sign
	call skip_space
	call get_symbol_size
	
	mov edx, register_index
	call find_symbol
	jnc reg_index ;check_disp_number
	mov edx, dword [esp]
	cmp dh, 3
	jne check_disp_number
	cmp dl, 4 ; esp ?
	jne check_disp_number
	
	or byte [mod_rm_byte], 00000100b ; MODRM_RM_SIB
	mov al, 4
	shl al, 3
	or al, dl
	mov byte [sib_byte], al
	mov byte [sib_size], 1
	jmp check_disp_number
	
	reg_index:
	mov byte [mod_rm_byte], 0 ; not needed we found other
	cmp byte [disp_sign], '-'
	je invalid_address
	mov edx, dword [esp]
	cmp ah, dh
	jne invalid_address
	cmp ah, 3
	je get_sib
	mov dh, al
	cmp dx, 0x0407
	je bx_si
	cmp dx, 0x0704
	je bx_si
	cmp dx, 0x0507
	je bx_di
	cmp dx, 0x0705
	je bx_di
	cmp dx, 0x0406
	je bp_si
	cmp dx, 0x0604
	je bp_si
	cmp dx, 0x0506
	je bp_di
	cmp dx, 0x0605
	je bp_di
	jmp invalid_address
	
	bx_si:
	or byte [mod_rm_byte], 000b
	jmp check_address_end
	bx_di:
	or byte [mod_rm_byte], 001b
	jmp check_address_end
	bp_si:
	or byte [mod_rm_byte], 010b
	jmp check_address_end
	bp_di:
	or byte [mod_rm_byte], 011b
	jmp check_address_end
	
	check_address_end:
	add esi, ecx
	call skip_space
	cmp byte [esi], ']'
	je ret_address_end
	cmp byte [esi], '+'
	je no_address_end
	cmp byte [esi], '-'
	je no_address_end
	jmp invalid_address
	
	no_address_end:
	mov al, byte [esi]
	mov byte [disp_sign], al
	inc esi ; skip sign
	call skip_space
	call get_symbol_size
	
	check_disp_number:
	call get_number
	jc invalid_operand
	
	check_disp_sign:
	cmp byte [disp_sign], '+'
	je disp_number_positive
	not eax
	inc eax
	disp_number_positive:
	mov dword [disp_byte], eax
	
	cmp ax, -0x80
	jl mod_disp_16
	cmp ax, 0x7F
	jg mod_disp_16
	
	mod_disp_8:
	mov byte [disp_size], 1
	or byte [mod_rm_byte], 01000000b ; MEMORY_DISP_8
	jmp mod_disp_ok
	
	mod_disp_16:
	mov edx, dword [esp]
	cmp dh, 3
	je mod_disp_32
	cmp eax, -0x8000 ; -32768
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	mov byte [disp_size], 2
	or byte [mod_rm_byte], 10000000b ; MEMORY_DISP_16
	jmp mod_disp_ok
	
	mod_disp_32:
	mov byte [disp_size], 4
	or byte [mod_rm_byte], 10000000b ; MEMORY_DISP_32
	jmp mod_disp_ok
	
	mod_disp_ok:
	add esi, ecx
	call skip_space
	cmp byte [esi], ']'
	jne invalid_address
	jmp ret_address_end

sib_disp:
	mov al, byte [sib_byte]
	cmp byte [sib_size], 0
	je no_sib
	stos byte [edi]
	no_sib:
	mov eax, dword [disp_byte]
	cmp byte [disp_size], 0
	je no_disp
	cmp byte [disp_size], 1
	je sto_disp_8
	cmp byte [disp_size], 2
	je sto_disp_16
	cmp byte [disp_size], 4
	je sto_disp_32
	jmp no_disp
	sto_disp_8:
	stos byte [edi]
	ret
	sto_disp_16:
	stos word [edi]
	ret
	sto_disp_32:
	stos dword [edi]
	ret
	no_disp:
	ret
	
disp_address:
	call imm_number

	no_disp_label:
	cmp eax, -0x8000 ; -32768
	jl disp_address_32
	cmp eax, 0xFFFF
	jg disp_address_32
	cmp byte [code_type], 32
	je disp_address_32
	
	disp_address_16:
	call address_size_prefix_16
	mov dword [disp_byte], eax
	or byte [mod_rm_byte], 00000110b ; DISP_16 ; ModRM.rm = [BP] or [DISP16]
	mov byte [disp_size], 2
	jmp disp_address_end
	
	disp_address_32:
	call address_size_prefix_32
	mov dword [disp_byte], eax
	or byte [mod_rm_byte], 00000101b ; DISP_32 ; ModRM.rm = [EBP] or [DISP32]
	mov byte [disp_size], 4
	disp_address_end:
	push eax
	
	mov byte [address_type], 2
	
	add esi, ecx
	call skip_space
	cmp byte [esi], ']'
	jne invalid_address
	jmp ret_address_end
	
get_imm:
	cmp byte [esi], 0x27 ; '
	jne imm_number
	push ecx
	cmp ecx, 2 ; no char just two ''
	jbe invalid_operand
	cmp ecx, 6 ; 2+4=6 above 4 chars
	ja value_exceeds_range
	sub ecx, 2
	cmp ecx, 4
	jne imm_123_char
	mov eax, dword [esi+1] ; skip '
	pop ecx
	ret
	imm_123_char:
	shl ecx, 3
	xor ebx, ebx
	mov ebx, 1
	shl ebx, cl
	dec ebx
	mov eax, dword [esi+1] ; skip '
	and eax, ebx
	pop ecx
	ret
	imm_number:
	xor eax, eax
	imm_number_start:
	mov ebx, eax
	call get_signed_number
	jc imm_label
	
	after_imm_number:
	add eax, ebx
	;jc value_exceeds_range
	
	push eax
	push ebx
	call skip_symbol
	pop ebx
	pop eax
	cmp byte [esi], '+'
	je imm_number_start
	cmp byte [esi], '-'
	je imm_number_start
	
	imm_label_ok:
	mov ecx, 0
	ret
	imm_label:
	mov edx, dword [label_start]
	call find_symbol
	jnc imm_label_found ; jnc = yes label found
	cmp dword [count_pass], 2
	jge invalid_operand
	mov dword [need_pass], 1
	mov eax, 0
	imm_label_found:
	jmp after_imm_number
	
	
mov_:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, operand_size
	call find_symbol
	jc mov_reg ; operand size found ?
	cmp eax, 1
	je mov_m8
	cmp eax, 2
	je mov_m16
	cmp eax, 4
	je mov_m32
	jmp unvalid_size_operand
	
	mov_reg:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	je mov_r8
	cmp ah, 2
	je mov_r16
	cmp ah, 3
	je mov_r32
	cmp ah, 4
	je mov_seg
	cmp ah, 5
	je mov_cr_r32
	jmp invalid_operand
	
	mov_r8:
	push eax ; eax=distination register code
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, all_registers
	call find_symbol
	jc mov_r8_
	cmp ah, 1
	jne mov_r8_
	
	mov_r8_r8:
	mov ah, al
	shl ah, 3
	or ah, 11000000b ; Mod.R/M.mod = 11: Register
	pop ebx          ; now ebx=distination register code
	or ah, bl
	mov al, 0x88
	stos word [edi]
	retd
	
	mov_r8_:
	mov edx, operand_size
	call find_symbol
	jc mov_r8_imm8
	cmp eax, 1
	jne unvalid_size_operand
	call get_address
	
	mov_al_mof8:
	mov eax, dword [esp]
	cmp al, 0
	jne mov_r8_m8
	cmp byte [address_type], 2
	jne mov_r8_m8
	mov al, 0xA0
	stos byte [edi]
	pop eax ; not needed 
	call sib_disp
	retd
	
	mov_r8_m8:
	mov al, 0x8A
	stos byte [edi]
	pop eax ; now eax=distination register code
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	mov_r8_imm8:
	call get_imm
	cmp eax, -0x80
	jl value_exceeds_range
	cmp eax, 0xFF
	jg value_exceeds_range
	pop ebx ; now ebx=distination register code
	add bl, 0xB0
	shl eax, 8
	mov al, bl
	stos word [edi]
	retd
	
	mov_m8:
	call get_address
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc mov_m8_imm8
	cmp ah, 1
	jne mov_m8_imm8
	
	mov_mof8_al:
	cmp al, 0
	jne mov_m8_r8
	cmp byte [address_type], 2
	jne mov_m8_r8
	mov al, 0xA2
	stos byte [edi]
	call sib_disp
	retd
	
	mov_m8_r8:
	push eax
	mov al, 0x88
	stos byte [edi]
	pop eax
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	mov_m8_imm8:
	call get_imm
	cmp eax, -0x80
	jl value_exceeds_range
	cmp eax, 0xFF
	jg value_exceeds_range
	push eax
	mov ah, byte [mod_rm_byte]
	mov al, 0xC6
	stos word [edi]
	call sib_disp
	pop eax
	stos byte [edi]
	retd
	
	mov_r16:
	push eax
	;call operand_size_prefix_16
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, all_registers
	call find_symbol
	jc mov_r16_
	cmp ah, 4
	je mov_r16_seg
	cmp ah, 2
	jne mov_r16_
	
	mov_r16_r16:
	call operand_size_prefix_16
	mov ah, al
	shl ah, 3
	or ah, 11000000b
	pop ebx
	or ah, bl
	mov al, 0x89
	stos word [edi]
	retd
	
	mov_r16_:
	mov edx, operand_size
	call find_symbol
	jc mov_r16_imm16
	cmp eax, 2
	jne unvalid_size_operand
	call get_address
	
	call operand_size_prefix_16
	
	mov_ax_mof16:
	mov eax, dword [esp]
	cmp al, 0
	jne mov_r16_m16
	cmp byte [address_type], 2
	jne mov_r16_m16
	mov al, 0xA1
	stos byte [edi]
	pop eax ; not needed 
	call sib_disp
	retd
	
	mov_r16_m16:
	mov al, 0x8B
	stos byte [edi]
	pop eax
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	mov_r16_seg:
	call operand_size_prefix_16
	
	mov ah, al
	shl ah, 3
	or ah, 11000000b
	pop ebx
	or ah, bl
	mov al, 0x8C
	stos word [edi]
	retd
	
	mov_r16_imm16:
	call operand_size_prefix_16
	
	call get_imm
	cmp eax, -0x8000
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	pop ebx
	add bl, 0xB8
	push eax
	mov al, bl
	stos byte [edi]
	pop eax
	stos word [edi]
	retd
	
	mov_m16:
	call get_address
	call operand_size_prefix_16
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc mov_m16_imm16
	cmp ah, 2
	jne mov_m16_imm16
	
	mov_mof16_ax:
	cmp al, 0
	jne mov_m16_r16
	cmp byte [address_type], 2
	jne mov_m16_r16
	mov al, 0xA3
	stos byte [edi]
	call sib_disp
	retd
	
	mov_m16_r16:
	push eax
	mov al, 0x89
	stos byte [edi]
	pop eax
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	mov_m16_imm16:
	call get_imm
	cmp eax, -0x8000
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	push eax
	mov ah, byte [mod_rm_byte]
	mov al, 0xC7
	stos word [edi]
	call sib_disp
	pop eax
	stos word [edi]
	retd
	
	mov_r32:
	push eax
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, all_registers
	call find_symbol
	jc mov_r32_cr
	cmp ah, 3
	jne mov_r32_cr
	
	mov_r32_r32:
	call operand_size_prefix_32
	mov ah, al
	shl ah, 3
	or ah, 11000000b
	pop ebx
	or ah, bl
	mov al, 0x89
	stos word [edi]
	retd
	
	mov_r32_cr:
	mov edx, all_registers
	call find_symbol
	jc mov_r32_
	cmp ah, 5
	jne mov_r32_
	push eax
	mov ax, 0x200F
	stos word [edi]
	pop eax
	shl al, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stos byte [edi]
	retd
	
	mov_r32_:
	mov edx, operand_size
	call find_symbol
	jc mov_r32_imm32
	cmp eax, 4
	jne unvalid_size_operand
	call get_address
	
	call operand_size_prefix_32
	
	mov_eax_mof32:
	mov eax, dword [esp]
	cmp al, 0
	jne mov_r32_m32
	cmp byte [address_type], 2
	jne mov_r32_m32
	mov al, 0xA1
	stos byte [edi]
	pop eax ; not needed 
	call sib_disp
	retd
	
	mov_r32_m32:
	mov al, 0x8B
	stos byte [edi]
	pop eax
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	mov_r32_imm32:
	call get_imm
	;cmp eax, 0xFFFFFFFF
	;ja unvalid_size_operand
	call operand_size_prefix_32
	pop ebx
	add bl, 0xB8
	push eax
	mov al, bl
	stos byte [edi]
	pop eax
	stos dword [edi]
	retd
	
	mov_m32:
	call get_address
	call operand_size_prefix_32
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc mov_m32_imm32
	cmp ah, 3
	jne mov_m32_imm32
	
	mov_mof32_eax:
	cmp al, 0
	jne mov_m32_r32
	cmp byte [address_type], 2
	jne mov_m32_r32
	mov al, 0xA3
	stos byte [edi]
	call sib_disp
	retd
	
	mov_m32_r32:
	push eax
	mov al, 0x89
	stos byte [edi]
	pop eax
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	mov_m32_imm32:
	call get_imm
	;cmp eax, 0xFFFFFFFF
	;ja unvalid_size_operand
	push eax
	mov ah, byte [mod_rm_byte]
	mov al, 0xC7
	stos word [edi]
	call sib_disp
	pop eax
	stos dword [edi]
	retd
	
	mov_seg:
	cmp al, 1
	je invalid_operand
	push eax
	call find_source_operand
	
	mov_seg_r16:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	jne invalid_operand
	pop ebx
	shl bl, 3
	or bl, 11000000b
	or bl, al
	mov ah, bl
	mov al, 0x8E
	stos word [edi]
	retd
	
	mov_cr_r32:
	push eax
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 3
	jne invalid_operand
	push eax
	mov ax, 0x220F
	stos word [edi]
	pop eax
	pop ebx
	shl bl, 3
	or bl, 11000000b
	or al, bl
	stos byte [edi]
	retd
	
movs_:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc invalid_operand ; operand size found ?
	push eax
	push edi
	call get_address
	pop edi
	cmp byte [address_type], 1
	jne invalid_address
	cmp byte [segment_byte], 0
	je movs_no_seg
	cmp byte [segment_byte], 0x26
	jne invalid_address
	movs_no_seg:
	cmp ax, 0x0307
	je movs_m
	cmp ax, 0x0205
	je movs_m
	jmp invalid_address
	movs_m:
	push eax
	call find_source_operand
	mov ecx, 0
	call get_address
	cmp byte [address_type], 1
	jne invalid_address
	pop edx
	cmp ax, 0x0306
	je movs_ma32_ma32
	cmp ax, 0x0204
	je movs_ma16_ma16
	jmp invalid_address
	movs_ma32_ma32:
	cmp dx, 0x0307
	jne invalid_address
	jmp movs_m_m
	movs_ma16_ma16:
	cmp dx, 0x0205
	jne invalid_address
	movs_m_m:
	pop eax
	cmp eax, 1
	je movs_m8
	cmp eax, 2
	je movs_m16
	cmp eax, 4
	je movs_m32
	jmp unvalid_size_operand
	movs_m8:
	jmp movsb_
	movs_m16:
	jmp movsw_
	movs_m32:
	jmp movsd_
	
movsb_:
	mov al, 0xA4
	stos byte [edi]
	retd
	
movsw_:
	call operand_size_prefix_16
	mov al, 0xA5
	stos byte [edi]
	retd
	
movsd_:
	call operand_size_prefix_32
	mov al, 0xA5
	stos byte [edi]
	retd
	
movsx_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xBE
	jmp mov_x_
	
movzx_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0xB6
	jmp mov_x_
	

mov_x_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	je mov_x_r16_
	cmp ah, 3
	je mov_x_r32_
	jmp invalid_operand
	
	mov_x_r16_:
	push eax
	call operand_size_prefix_16
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, operand_size
	call find_symbol
	jc mov_x_r16_r8
	cmp eax, 1
	jne unvalid_size_operand
	call get_address
	
	mov_x_r16_m8:
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	pop eax ; now eax=distination register code
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	mov_x_r16_r8:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	jne invalid_operand
	push eax
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	pop eax
	pop ebx ; now ebx=distination register code
	shl bl, 3
	or bl, 11000000b ; Mod.R/M.mod = 11: Register
	or al, bl
	stos byte [edi]
	retd
	
	mov_x_r32_:
	push eax
	call operand_size_prefix_32
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	
	mov edx, operand_size
	call find_symbol
	jc mov_x_r32_r8
	cmp eax, 1
	je mov_x_r32_m8
	cmp eax, 2
	je mov_x_r32_m16
	jmp unvalid_size_operand
	
	mov_x_r32_m8:
	call get_address
	mov ah, byte [opcode+1]
	jmp mov_x_r32_m8_16
	
	mov_x_r32_m16:
	call get_address
	mov ah, byte [opcode+1]
	add ah, 0x01
	
	mov_x_r32_m8_16:
	mov al, byte [opcode]
	stos word [edi]
	pop eax ; now eax=distination register code
	shl al, 3
	or al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	mov_x_r32_r8:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	je mov_x_r32_r16
	cmp ah, 1
	jne invalid_operand
	push eax
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	pop eax
	pop ebx ; now ebx=distination register code
	shl bl, 3
	or bl, 11000000b ; Mod.R/M.mod = 11: Register
	or al, bl
	stos byte [edi]
	retd
	
	mov_x_r32_r16:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	jne invalid_operand
	push eax
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	add ah, 1
	stos word [edi]
	pop eax
	pop ebx ; now ebx=distination register code
	shl bl, 3
	or bl, 11000000b ; Mod.R/M.mod = 11: Register
	or al, bl
	stos byte [edi]
	retd
	
mul_:
	mov byte [opcode], 0xF6
	mov byte [opcode+1], 0x04
	jmp same_code_02
	
neg_:
	mov byte [opcode], 0xF6
	mov byte [opcode+1], 0x03
	jmp same_code_02
	
nop_:
	mov al, 0x90
	stos byte [edi]
	retd
	
not_:
	mov byte [opcode], 0xF6
	mov byte [opcode+1], 0x02
	jmp same_code_02
	
or_:
	mov byte [opcode], 0x08
	mov byte [opcode+1], 0x01
	jmp same_code_01
	
out_:
	call skip_symbol
	call get_number
	jc invalid_operand
	cmp eax, 0xFF
	ja value_exceeds_range
	push eax
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	je out_imm8_al
	cmp ah, 2
	je out_imm8_ax
	cmp ah, 3
	je out_imm8_eax
	jmp invalid_operand
	
	out_imm8_al:
	cmp al, 0
	jne invalid_operand
	mov al, 0xE6
	stos byte [edi]
	pop eax
	stos byte [edi]
	retd
	
	out_imm8_ax:
	cmp al, 0
	jne invalid_operand
	call operand_size_prefix_16
	mov al, 0xE7
	stos byte [edi]
	pop eax
	stos byte [edi]
	retd
	
	out_imm8_eax:
	cmp al, 0
	jne invalid_operand
	call operand_size_prefix_32
	mov al, 0xE7
	stos byte [edi]
	pop eax
	stos byte [edi]
	retd
	
outsb_:
	mov al, 0x6E
	stos byte [edi]
	retd
	
outsw_:
	call operand_size_prefix_16
	mov al, 0x6F
	stos byte [edi]
	retd
	
outsd_:
	call operand_size_prefix_32
	mov al, 0x6F
	stos byte [edi]
	retd
	
pop_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	je pop_r16
	cmp ah, 3
	je pop_r32
	cmp ah, 4
	je pop_seg
	jmp invalid_operand
	
	pop_r16:
	call operand_size_prefix_16
	add al, 0x58
	stos byte [edi]
	retd
	
	pop_r32:
	call operand_size_prefix_32
	add al, 0x58
	stos byte [edi]
	retd
	
	pop_seg:
	cmp al, 0
	je pop_es
	cmp al, 2
	je pop_ss
	cmp al, 3
	je pop_ds
	cmp al, 4
	je pop_fs
	cmp al, 5
	je pop_gs
	jmp invalid_operand
	
	pop_es:
	mov al, 0x07
	stos byte [edi]
	retd
	pop_ss:
	mov al, 0x17
	stos byte [edi]
	retd
	pop_ds:
	mov al, 0x1F
	stos byte [edi]
	retd
	pop_fs:
	mov ax, 0xA10F
	stos word [edi]
	retd
	pop_gs:
	mov ax, 0xA90F
	stos word [edi]
	retd
	
popad_:
	call operand_size_prefix_32
popa_:
	mov al, 0x61
	stos byte [edi]
	retd
	
popf_:
	mov al, 0x9D
	stos byte [edi]
	retd
	
push_:
	call skip_symbol
	
	mov edx, operand_size
	call find_symbol
	jc push_reg ; operand size found ?
	cmp eax, 1
	je push_imm8
	cmp eax, 2
	je push_imm16
	cmp eax, 4
	je push_imm32
	jmp push_reg
	
	push_imm8:
	call skip_symbol
	call imm_number
	cmp eax, -0x80
	jl unvalid_size_operand
	cmp eax, 0x7F
	jg unvalid_size_operand
	shl eax, 8
	mov al, 0x6A
	stos word [edi]
	retd
	
	push_imm16:
	call skip_symbol
	call operand_size_prefix_16
	call imm_number
	cmp eax, -0x8000 ; -32768
	jl value_exceeds_range
	cmp eax, 0xFFFF
	jg value_exceeds_range
	push eax
	mov al, 0x68
	stos byte [edi]
	pop eax
	stos word [edi]
	retd
	
	push_imm32:
	call skip_symbol
	call operand_size_prefix_32
	call imm_number
	push eax
	mov al, 0x68
	stos byte [edi]
	pop eax
	stos dword [edi]
	retd
	
	push_reg:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	je push_r16
	cmp ah, 3
	je push_r32
	cmp ah, 4
	je push_seg
	jmp invalid_operand
	
	push_r16:
	call operand_size_prefix_16
	add al, 0x50
	stos byte [edi]
	retd
	
	push_r32:
	call operand_size_prefix_32
	add al, 0x50
	stos byte [edi]
	retd
	
	push_seg:
	cmp al, 0
	je push_es
	cmp al, 1
	je push_cs
	cmp al, 2
	je push_ss
	cmp al, 3
	je push_ds
	cmp al, 4
	je push_fs
	cmp al, 5
	je push_gs
	jmp invalid_operand
	
	push_es:
	mov al, 0x06
	stos byte [edi]
	retd
	push_cs:
	mov al, 0x0E
	stos byte [edi]
	retd
	push_ss:
	mov al, 0x16
	stos byte [edi]
	retd
	push_ds:
	mov al, 0x1E
	stos byte [edi]
	retd
	push_fs:
	mov ax, 0xA00F
	stos word [edi]
	retd
	push_gs:
	mov ax, 0xA80F
	stos word [edi]
	retd
	
pushad_:
	call operand_size_prefix_32
pusha_:
	mov al, 0x60
	stos byte [edi]
	retd
	
pushf_:
	mov al, 0x9C
	stos byte [edi]
	retd
	
rep_:
	mov al, 0xF3
	stos byte [edi]
	retd
		
repne_:
	mov al, 0xF2
	stos byte [edi]
	retd
	
ret_:
	mov al, 0xC3
	stos byte [edi]
	retd
	
retw_:
	call operand_size_prefix_16
	jmp ret_

retd_:
	call operand_size_prefix_32
	jmp ret_
	
sahf_:
	mov al, 0x9E
	stos byte [edi]
	retd
	
seta_:
setnbe_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x97
	jmp set_
	
setae_:
setnb_:
setnc_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x93
	jmp set_
	
setb_:
setc_:
setnae_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x92
	jmp set_
	
setbe_:
setna_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x96
	jmp set_
	
sete_:
setz_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x94
	jmp set_
	
setg_:
setnle_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x9F
	jmp set_
	
setge_:
setnl_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x9D
	jmp set_
	
setl_:
setnge_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x9C
	jmp set_
	
setle_:
setng_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x9E
	jmp set_
	
setne_:
setnz_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x95
	jmp set_
	
setno_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x91
	jmp set_
	
setnp_:
setpo_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x9B
	jmp set_
	
setns_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x99
	jmp set_
	
seto_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x90
	jmp set_
	
setp_:
setpe_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x9A
	jmp set_
	
sets_:
	mov byte [opcode], 0x0F
	mov byte [opcode+1], 0x98
	jmp set_

set_:
	call skip_symbol
	
	cmp byte [esi], '['
	je operand_size_ns
	
	set_mem:
	mov edx, operand_size
	call find_symbol
	jc set_reg
	cmp eax, 1
	jne unvalid_size_operand
	
	call get_address
	
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	mov al, byte [mod_rm_byte]
	stos byte [edi]
	call sib_disp
	retd
	
	set_reg:
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	jne invalid_operand
	
	push eax
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stos word [edi]
	pop eax
	or al, 11000000b
	stos byte [edi]
	retd
	
rcl_:
	mov byte [opcode], 0xC1
	mov byte [opcode+1], 2
	jmp shlr_
	
rcr_:
	mov byte [opcode], 0xC1
	mov byte [opcode+1], 3
	jmp shlr_
	
rol_:
	mov byte [opcode], 0xC1
	mov byte [opcode+1], 0
	jmp shlr_
	
ror_:
	mov byte [opcode], 0xC1
	mov byte [opcode+1], 1
	jmp shlr_
	
sal_:
	mov byte [opcode], 0xC1
	mov byte [opcode+1], 4
	jmp shlr_
	
sar_:
	mov byte [opcode], 0xC1
	mov byte [opcode+1], 7
	jmp shlr_
	
shl_:
	mov byte [opcode], 0xC1
	mov byte [opcode+1], 4
	jmp shlr_
	
shr_:
	mov byte [opcode], 0xC1
	mov byte [opcode+1], 5
	jmp shlr_

shlr_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	je shlr_r8
	cmp ah, 2
	je shlr_r16
	cmp ah, 3
	je shlr_r32
	jmp invalid_operand
	
	shlr_r8:
	push eax
	sub byte [opcode], 0x01
	jmp shlr
	
	shlr_r16:
	push eax
	call operand_size_prefix_16
	jmp shlr
	
	shlr_r32:
	push eax
	call operand_size_prefix_32
	jmp shlr
	
	shlr:
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc shlr_reg_imm
	cmp ah, 1
	jne invalid_operand
	cmp al, 1
	jne invalid_operand
	
	shlr_reg_cl:
	pop edx
	push eax
	mov al, 0x12
	jmp shlr_r_
	
	shlr_reg_imm:
	call get_number
	jc invalid_operand
	cmp eax, 0xFF
	ja value_exceeds_range
	pop edx
	push eax
	cmp eax, 1 ; Shift 1
	jne shlr_reg_imm8
	
	shlr_r_1:
	mov al, 0x10
	shlr_r_:
	add al, byte [opcode]
	stos byte [edi]
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or bl, dl
	mov al, bl
	stos byte [edi]
	pop eax
	retd
	
	shlr_reg_imm8:
	mov al, byte [opcode]
	stos byte [edi]
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or bl, dl
	mov al, bl
	stos byte [edi]
	pop eax
	stos byte [edi]
	retd
	
	
sbb_:
	mov byte [opcode], 0x18
	mov byte [opcode+1], 0x03
	jmp same_code_01
	
scasb_:
	mov al, 0xAE
	stos byte [edi]
	retd
	
scasw_:
	call operand_size_prefix_16
	mov al, 0xAF
	stos byte [edi]
	retd
	
scasd_:
	call operand_size_prefix_32
	mov al, 0xAF
	stos byte [edi]
	retd
	
stc_:
	mov al, 0xF9
	stos byte [edi]
	retd
	
std_:
	mov al, 0xFD
	stos byte [edi]
	retd
	
sti_:
	mov al, 0xFB
	stos byte [edi]
	retd
	
stos_:
	call skip_symbol
	cmp byte [esi], '['
	je operand_size_ns
	mov edx, operand_size
	call find_symbol
	jc invalid_operand ; operand size found ?
	push eax
	push edi
	call get_address
	pop edi	
	cmp byte [address_type], 1
	jne invalid_address
	cmp byte [segment_byte], 0
	je stos_no_seg
	cmp byte [segment_byte], 0x26
	jne invalid_address
	stos_no_seg:
	cmp ax, 0x0307
	je stos_ma32
	cmp ax, 0x0205
	je stos_ma16
	jmp invalid_address
	stos_ma16:
	call address_size_prefix_16
	jmp stos_m
	stos_ma32:
	call address_size_prefix_32
	stos_m:
	pop eax
	cmp eax, 1
	je stos_m8
	cmp eax, 2
	je stos_m16
	cmp eax, 4
	je stos_m32
	jmp unvalid_size_operand
	stos_m8:
	jmp stosb_
	stos_m16:
	jmp stosw_
	stos_m32:
	jmp stosd_
	
stosb_:
	mov al, 0xAA
	stos byte [edi]
	retd
	
stosw_:
	call operand_size_prefix_16
	mov al, 0xAB
	stos byte [edi]
	retd
	
stosd_:
	call operand_size_prefix_32
	mov al, 0xAB
	stos byte [edi]
	retd
	
sub_:
	mov byte [opcode], 0x28
	mov byte [opcode+1], 0x05
	jmp same_code_01
	
test_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	je test_r8
	cmp ah, 2
	je test_r16
	cmp ah, 3
	je test_r32
	jmp invalid_operand
	
	test_r8:
	push eax ; eax=distination register code
	call find_source_operand
	
	test_r8_r8:
	mov edx, all_registers
	call find_symbol
	jc test_al_imm8
	cmp ah, 1
	jne test_al_imm8
	push eax
	mov al, 0x84
	stos byte [edi]
	pop eax
	shl eax, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stos byte [edi]
	retd

	test_al_imm8:
	pop eax
	cmp al, 0
	jne test_r8_imm8
	call get_number
	jc invalid_operand
	cmp eax, 0xFF
	ja value_exceeds_range
	shl eax, 8
	mov al, 0xA8
	stos word [edi]
	retd
	
	test_r8_imm8:
	mov ah, 0
	shl ah, 3
	or ah, al
	or ah, 11000000b
	mov al, 0xF6
	stos word [edi]
	call get_number
	jc invalid_operand
	cmp eax, 0xFF
	ja value_exceeds_range
	stos byte [edi]
	retd
	
	test_r16:
	call operand_size_prefix_16
	push eax ; eax=distination register code
	call find_source_operand
	
	test_r16_r16:
	mov edx, all_registers
	call find_symbol
	jc test_ax_imm16
	cmp ah, 2
	jne test_ax_imm16
	push eax
	mov al, 0x85
	stos byte [edi]
	pop eax
	shl eax, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stos byte [edi]
	retd

	test_ax_imm16:
	pop eax
	cmp al, 0
	jne test_r16_imm16
	call get_number
	jc invalid_operand
	cmp eax, 0xFFFF
	ja value_exceeds_range
	push eax
	mov al, 0xA9
	stos byte [edi]
	pop eax
	stos word [edi]
	retd
	
	test_r16_imm16:
	mov ah, 0
	shl ah, 3
	or ah, al
	or ah, 11000000b
	mov al, 0xF7
	stos word [edi]
	call get_number
	jc invalid_operand
	cmp eax, 0xFFFF
	ja value_exceeds_range
	stos word [edi]
	retd
	
	test_r32:
	call operand_size_prefix_32
	push eax ; eax=distination register code
	call find_source_operand
	
	test_r32_r32:
	mov edx, all_registers
	call find_symbol
	jc test_eax_imm32
	cmp ah, 3
	jne test_eax_imm32
	push eax
	mov al, 0x85
	stos byte [edi]
	pop eax
	shl eax, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stos byte [edi]
	retd

	test_eax_imm32:
	pop eax
	cmp al, 0
	jne test_r32_imm32
	call get_number
	jc invalid_operand
	push eax
	mov al, 0xA9
	stos byte [edi]
	pop eax
	stos dword [edi]
	retd
	
	test_r32_imm32:
	mov ah, 0
	shl ah, 3
	or ah, al
	or ah, 11000000b
	mov al, 0xF7
	stos word [edi]
	call get_number
	jc invalid_operand
	stos dword [edi]
	retd
	
wait_:
	mov al, 0x9B
	stos byte [edi]
	retd
	
xlatb_:
	mov al, 0xD7
	stos byte [edi]
	retd
	
xor_:
	mov byte [opcode], 0x30
	mov byte [opcode+1], 0x06
	jmp same_code_01
	

	

asm_:
db 'minis assembler version 0.10',13,10,'$'
usage_:
db 'usage: as source binary',13,10,'$'
nem_:
db 'error: not enough memory.',13,10,'$'
nosf_:
db 'error: source file not found.',13,10,'$'
ecf_:
db 'error: create file failed.',13,10,'$'
uns_:
db 'error: unknown instruction.',13,10,'$'
ecol_:
db 'error: extra characters on line.',13,10,'$'
eivo_:
db 'error: invalid operand.',13,10,'$'
eiva_:
db 'error: invalid address.',13,10,'$'
eios_:
db 'error: invalid size of operand.',13,10,'$'
emeq_:
db 'error: missing end quote.',13,10,'$'
einl_:
db 'error: invalid label.',13,10,'$'
elad_:
db 'error: label already defined.',13,10,'$'
ever_:
db 'error: value exceeds range.',13,10,'$'
eons_:
db 'error: operand size not specified.',13,10,'$'
erwl_:
db 'error: reserved word used as label.',13,10,'$'
bfnf_:
db 'error: binary file not found.',13,10,'$'
line_:
db 'line : [       ]',13,10,'$'
succ_:
db 'success:            bytes.',13,10,'$'
msgas_:
db 'assembling...',13,10,'$'



line_number:
dd 0
code_type:
db 0

memory_start:
dd 0
memory_end:
dd 0
source_start:
dd 0
source_end:
dd 0
binary_start:
dd 0
binary_end:
dd 0
label_start:
dd 0
label_end:
dd 0

count_pass:
dd 0
need_pass:
dd 0

input_file:
dd 0
output_file:
dd 0
input_bin:
dd 0

opcode:
db 0,0,0

bcount:
dd 0
binary_size:
dd 0

bin_name:
times 32 db 0

save_cmd:
times 255 db 0

com_end:

