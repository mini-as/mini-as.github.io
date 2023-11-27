;===========================================
;
; minis assembler 0.09
; Copyright (c) 2021-2023 Maghdouri Mohamed
; All rights reserved.
; see LICENSE.TXT
; Date: 11-11-2023
; https://mini-as.github.io
;
;
; compile with fasm version 1.73.31
;
;===========================================

	format PE console
	
	jmp start
	
	db 'minis assembler 0.09',0
	db 'Copyright (c) 2021-2023 Maghdouri Mohamed',0
	db 'All rights reserved.',0
	
start:
	mov esi, asm_
	call print

	call get_cmd
	
	call alloc_memory
	
	call preprocessor
	call assembler
	call binary_file
	
	call get_binary_size
	mov esi, succ_
	call print
	mov eax, 0
exit:
	push eax
	call [ExitProcess]
	
;--------------------------------	
; memory map:
	
; memory_start (size = 1 MB)
	; source_start
	; source_end
	; db 0
	; binary_start
	; binary_end
	; label_start (size = 100 KB)
	; label_end
; memory_end
;--------------------------------

MEM_COMMIT     = 0x1000
PAGE_READWRITE = 4
	
alloc_memory:
	mov eax, 0x100000 ; 1 MB
	mov [memory_end], eax
	push PAGE_READWRITE
	push MEM_COMMIT
	push eax
	push 0
	call [VirtualAlloc]
	or eax, eax
	jz not_enough_memory
	mov [memory_start], eax
	add eax, [memory_end]
	mov [memory_end], eax
	ret
	

STD_INPUT_HANDLE  = -10
STD_OUTPUT_HANDLE = -11
STD_ERROR_HANDLE  = -12

print:
	push STD_OUTPUT_HANDLE
	call [GetStdHandle]
	mov ebx, eax
	push esi
	string_0:
	lodsb
	cmp al, 0
	jne string_0
	dec esi ; lodsb inc esi
	sub esi, [esp]
	mov ecx, esi
	pop esi
	push 0 ;  pointer to an OVERLAPPED structure
	push bcount ; pointer to the variable that receives the number of bytes written 
	push ecx ; number of bytes to be written
	push esi ; pointer to string
	push ebx ; handle to the file
	call [WriteFile]
	ret

print_error:
	call print
	mov eax, 1
	jmp exit

get_cmd:
	call [GetCommandLine]
	mov esi, eax
	skip_as:
	lodsb
	cmp al, ' '
	jne skip_as
	dec esi
	call skip_space
	mov edi, save_cmd
	mov [input_file], edi
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
	mov [output_file], edi
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
	
	
CREATE_NEW        = 1
CREATE_ALWAYS     = 2
OPEN_EXISTING     = 3
OPEN_ALWAYS       = 4
TRUNCATE_EXISTING = 5

GENERIC_READ  = 0x80000000
GENERIC_WRITE = 0x40000000
	
open:
	push 0
	push 0
	push OPEN_EXISTING
	push 0
	push 0
	push GENERIC_READ
	push edx
	call [CreateFile]
	cmp eax, -1
	je file_error
	mov ebx, eax ; eax = file pointer
	clc
	ret
    file_error:
	stc
	ret
	
create:
	push 0
	push 0
	push CREATE_ALWAYS
	push 0
	push 0
	push GENERIC_WRITE
	push edx
	call [CreateFile]
	cmp eax, -1
	je file_error
	mov ebx, eax
	clc
	ret
	
write:
	push 0
	push bcount
	push ecx
	push edx
	push ebx
	call [WriteFile]
	or eax, eax
	jz file_error
	ret
	
read:
	mov	ebp,ecx
	push 0
	push bcount
	push ecx ; size
	push edx ; memory
	push ebx ; ebx = file pointer
	call [ReadFile]
	or eax, eax
	jz file_error
	cmp ebp,[bcount]
	jne file_error
	ret
	
close:
	push ebx
	call [CloseHandle]
	ret
	
lseek:
	push eax
	push 0
	push edx
	push ebx
	call [SetFilePointer]
	ret
	
preprocessor:
	mov edx, [input_file]
	call open
	jc no_source_file
	mov eax, 2
	mov edx, 0
	call lseek
	push eax
	mov eax, 0
	mov edx, 0
	call lseek
	pop ecx ; file size
	mov edx, [memory_start]
	mov [source_start], edx
	mov [source_end], edx
	add [source_end], ecx
	mov eax, [memory_end]
	sub eax, 0x19000 ; buffer size of labels = 100 KB
	mov [label_start], eax
	mov [label_end], eax
	call read
	call close
	ret
	
assembler:
	next_pass:
	mov eax, [label_start]
	mov [label_end], eax
	mov esi, [source_start]
	mov edi, [source_end]
	inc edi
	mov byte [edi], 0 ; end of file
	inc edi
	mov [binary_start], edi
	mov [code_type], 16
	mov [line_number], 0
	mov [need_pass], 0
	inc [count_pass]
	assemble_next_line:
	call assemble_line
	mov eax, edi ; check binary file limits
	add eax, 50
	cmp eax, [label_start]
	jge not_enough_memory
	cmp esi, [source_end] ; end of file
	jb assemble_next_line
	cmp [need_pass], 1
	je next_pass
	mov [binary_end], edi
	ret
	
binary_file:
	mov edx, [output_file]
	call create
	jc create_failed
	mov edx, [binary_start]
	mov ecx, [binary_end]
	sub ecx, edx
	mov dword [binary_size], ecx
	call write
	jc create_failed
	call close
	ret
	
assemble_line:
	inc [line_number]
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
	cmp al, ':' ; label ( al register from get_symbol_size )
	je check_label
	
	mov edx, instructions
	call find_symbol
	jc unknown_symbol
	call dword eax
	
	skip_next_line:
	;call skip_symbol
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
	lodsb
	cmp al, 13 ; new line
	je line_feed
	cmp al, 10 ; new line
	je line_ret
	dec esi
	jmp line_end
	line_feed:
	lodsb
	cmp al, 10
	je line_end
	dec esi
	jmp line_end
	line_ret:
	lodsb
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
	lodsb
	cmp al, 0 ; fix crushing bug whene source end with comment
	je assemble_line_ok
	cmp al, 13 ; new line
	jne skip_comment
	dec esi
	jmp next_line
	
skip_space:
	lodsb
	cmp al, ' ' 
	je skip_space
	cmp al, 0x09 ; tab
	je skip_space
	dec esi ; lodsb inc esi
	ret
	
; ret: ecx = symbol size
get_symbol_size:
;get_symbol:
	push esi ; esi = start of symbol
	get_symbol_end:
	lodsb
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
	jmp get_symbol_end
	string_start:
	lodsb
	cmp al, 13
	je missing_quote
	cmp al, 0
	je missing_quote
	cmp al, 0x27
	jne string_start
	inc esi ; to get length from ' to '
	get_symbol_ok:
	dec esi ; lodsb inc esi
	sub esi, [esp]
	mov ecx, esi
	pop esi
	ret
	
; ret: eax = number
get_number:
get_hex:
	pusha
	cmp word [esi], '0x'
	jne invalid_operand
	push esi ecx
	add esi, 2
	sub ecx, 2
	cmp ecx, 8
	ja invalid_operand
	mov ebx, 0
	valid_hex:
	lodsb
	cmp al, '0'
	jb invalid_operand
	cmp al, '9'
	ja valid_hex_A
	sub al, '0'
	jmp valid_hex_ok
	valid_hex_A:
	cmp al, 'A'
	jb invalid_operand
	cmp al, 'F'
	ja invalid_operand
	sub al, 55
	valid_hex_ok:
	shl ebx, 4
	add bl, al
	loop valid_hex
	pop ecx esi
	mov [esp+28], ebx
	popa
	ret
	
check_label:
	cmp [count_pass], 1
	jg skip_check_label
	call valid_label
	
	mov edx, [label_start]
	call find_symbol
	jnc label_already_defined
	
	call check_reserved_word
	call save_label
	skip_check_label:
	inc ecx ; add (:) end label
	jmp skip_next_line
	
;in: esi = string start    ecx = string lentgh
valid_label:
	pusha
	cmp ecx, 32
	jg invalid_label
	cmp ecx, 1
	jl invalid_label
	cmp byte [esi], '9' ; label must not start with number
	jle invalid_label
	valid_label_char:
	lodsb
	cmp al, '_'
	je next_label_char
	cmp al, 'a'
	jl valid_label_number ; invalid_label
	cmp al, 'z'
	jg invalid_label
	next_label_char:
	loop valid_label_char
	popa
	ret
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

; label lentgh (1-byte), label (max 32-bytes), value (4-bytes)
save_label:
	pusha
	mov edx, edi
	mov edi, [label_end]
	mov eax, edi ; check limits
	add eax, 40
	cmp eax, [memory_end]
	jge not_enough_memory
	sub edx, [binary_start] ; get current address value
	mov al, cl ; label lentgh
	stosb
	save_label_string:
	lodsb
	stosb
	loop save_label_string
	mov eax, edx
	stosd
	mov eax, 0 ; end of label table
	stosb
	dec edi
	mov [label_end], edi ; for next label
	popa
	ret
	
;===== search symbol inside symbol table =====
; in : esi = symbol pointer
;      ecx = symbol size
;      edx = symbol table pointer
; ret: symbol found ---------> clear carry flag, eax = dword after symbol
;      symbol not found -----> set carry flag
;=============================================
find_symbol:
	pusha ; Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI
	mov edi, edx
	clc
	next_symbol:
	push ecx esi edi
	movzx eax, byte [edi] ; number of characters
	cmp eax, 0 ; end of table
	je no_symbol_found
	cmp eax, ecx
	je check_symbol
	pop edi esi ecx
	movzx eax, byte [edi]
	add edi, eax
	add edi, 5 ; db,dd = 1+4=5
	jmp next_symbol
	check_symbol:
	inc edi
	rep cmpsb
	je yes_symbol_found
	pop edi esi ecx
	movzx eax, byte [edi]
	add edi, eax
	add edi, 5
	jmp next_symbol
	no_symbol_found:
	pop edi esi ecx
	popa
	stc
	ret
	yes_symbol_found:
	pop edi esi ecx
	movzx eax, byte [edi]
	add edi, eax
	inc edi
	mov eax, dword [edi]
	mov [esp+28], eax ; eax inside stack
	popa
	clc
	ret
	
	
address_size_prefix_16:
	push eax
	cmp [code_type], 16
	je asp16_ok
	mov al, 0x67
	stosb
	asp16_ok:
	pop eax
	ret
	

address_size_prefix_32:
	push eax
	cmp [code_type], 32
	je asp32_ok
	mov al, 0x67
	stosb
	asp32_ok:
	pop eax
	ret
	
	
operand_size_prefix_16:
	push eax
	cmp [code_type], 16
	je osp16_ok
	mov al, 0x66
	stosb
	osp16_ok:
	pop eax
	ret
	
operand_size_prefix_32:
	push eax
	cmp [code_type], 32
	je osp32_ok
	mov al, 0x66
	stosb
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
	call get_symbol_size ; get_symbol
	ret
	
get_binary_size:
	mov eax, [binary_size]
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
	mov [edi], dl
	dec edi
	loop save_number
	;mov esi, line_
	;add esi, 8
	mov edi, esi
	skip_number:
	lodsb
	cmp al, '0'
	je skip_number
	dec esi
	shift_number:
	lodsb
	stosb
	cmp al, 0
	jne shift_number
	ret

usage_error:
	mov esi, usage_
	je print_error
	
not_enough_memory:
	mov esi, nem_
	jmp print_error
	
no_source_file:
	mov esi, nosf_
	jmp print_error
	
create_failed:
	mov esi, ecf_
	jmp print_error
	
display_line_error:
	mov eax, [line_number]
	call get_line_number
	mov esi, line_
	call print
	mov eax, 1
	jmp exit
	
unknown_symbol:
	mov esi, uns_
	call print
	jmp display_line_error
	
extra_character:
	mov esi, ecol_
	call print
	jmp display_line_error
	
invalid_operand:
	mov esi, eivo_
	call print
	jmp display_line_error
	
unvalid_size_operand:
	mov esi, eios_
	call print
	jmp display_line_error
	
missing_quote:
	mov esi, emeq_
	call print
	jmp display_line_error
	
invalid_label:
	mov esi, einl_
	call print
	jmp display_line_error

label_already_defined:
	mov esi, elad_
	call print
	jmp display_line_error
	
relative_out_of_range:
	mov esi, erjr_
	call print
	jmp display_line_error
	
operand_size_ns:
	mov esi, eons_
	call print
	jmp display_line_error
	
reserved_word:
	mov esi, erwl_
	call print
	jmp display_line_error
	
binary_file_nf:
	mov esi, bfnf_
	call print
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
	;db 3,'esp',4,3,0,0  ; not yet
	;db 3,'ebp',5,3,0,0  ; not yet
	db 3,'esi',6,3,0,0
	db 3,'edi',7,3,0,0
	db 2,'bx',7,2,0,0
	;db 2,'bp',6,2,0,0  ; not yet
	db 2,'si',4,2,0,0
	db 2,'di',5,2,0,0
	db 0
	
	
instructions:
	db 5,'use16'
	dd use16_
	db 5,'use32'
	dd use32_
	db 2,'db'
	dd db_
	db 2,'dw'
	dd dw_
	db 2,'dd'
	dd dd_
	db 5,'times'
	dd times_
	db 6,'binary'
	dd binary_
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
	db 4,'call'
	dd call_
	db 3,'cbw'
	dd cbw_
	db 4,'cwde'
	dd cwde_
	db 3,'clc'
	dd clc_
	db 3,'cld'
	dd cld_
	db 3,'cli'
	dd cli_
	db 4,'clts'
	dd clts_
	db 3,'cmc'
	dd cmc_
	db 3,'cmp'
	dd cmp_
	db 5,'cmpsb'
	dd cmpsb_
	db 5,'cmpsw'
	dd cmpsw_
	db 5,'cmpsd'
	dd cmpsd_
	db 3,'cwd'
	dd cwd_
	db 3,'cdq'
	dd cdq_
	db 3,'daa'
	dd daa_
	db 3,'das'
	dd das_
	db 3,'dec'
	dd dec_
	db 3,'div'
	dd div_
	db 3,'hlt'
	dd hlt_
	db 4,'idiv'
	dd idiv_
	db 4,'imul'
	dd imul_
	db 2,'in'
	dd in_
	db 3,'inc'
	dd inc_
	db 4,'insb'
	dd insb_
	db 4,'insw'
	dd insw_
	db 4,'insd'
	dd insd_
	db 3,'int'
	dd int_
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
	db 3,'jae'
	dd jae_
	db 2,'jb'
	dd jb_
	db 3,'jbe'
	dd jbe_
	db 2,'jc'
	dd jc_
	db 4,'jcxz'
	dd jcxz_
	db 5,'jecxz'
	dd jecxz_
	db 2,'je'
	dd je_
	db 2,'jz'
	dd je_
	db 2,'jg'
	dd jg_
	db 3,'jge'
	dd jge_
	db 2,'jl'
	dd jl_
	db 3,'jle'
	dd jle_
	db 3,'jna'
	dd jna_
	db 4,'jnae'
	dd jnae_
	db 3,'jnb'
	dd jnb_
	db 4,'jnbe'
	dd jnbe_
	db 3,'jnc'
	dd jnc_
	db 3,'jne'
	dd jne_
	db 3,'jng'
	dd jng_
	db 4,'jnge'
	dd jnge_
	db 3,'jnl'
	dd jnl_
	db 4,'jnle'
	dd jnle_
	db 3,'jno'
	dd jno_
	db 3,'jnp'
	dd jnp_
	db 3,'jns'
	dd jns_
	db 3,'jnz'
	dd jne_
	db 2,'jo'
	dd jo_
	db 2,'jp'
	dd jp_
	db 3,'jpe'
	dd jp_
	db 3,'jpo'
	dd jpo_
	db 2,'js'
	dd js_
	db 3,'jmp'
	dd jmp_
	db 4,'lahf'
	dd lahf_
	db 5,'leave'
	dd leave_
	db 4,'lgdt'
	dd lgdt_
	db 4,'lidt'
	dd lidt_
	db 4,'lock'
	dd lock_
	db 5,'lodsb'
	dd lodsb_
	db 5,'lodsw'
	dd lodsw_
	db 5,'lodsd'
	dd lodsd_
	db 4,'loop'
	dd loop_
	db 3,'mov'
	dd mov_
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
	db 3,'mul'
	dd mul_
	db 3,'neg'
	dd neg_
	db 3,'nop'
	dd nop_
	db 3,'not'
	dd not_
	db 2,'or'
	dd or_
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
	db 5,'popad'
	dd popad_
	db 4,'popf'
	dd popf_
	db 4,'push'
	dd push_
	db 5,'pusha'
	dd pusha_
	db 6,'pushad'
	dd pushad_
	db 5,'pushf'
	dd pushf_
	db 3,'rep'
	dd rep_
	db 4,'repe'
	dd rep_
	db 4,'repz'
	dd rep_
	db 5,'repne'
	dd repne_
	db 5,'repnz'
	dd repne_
	db 3,'ret'
	dd ret_
	db 4,'sahf'
	dd sahf_
	db 3,'shl'
	dd shl_
	db 3,'shr'
	dd shr_
	db 3,'sbb'
	dd sbb_
	db 5,'scasb'
	dd scasb_
	db 5,'scasw'
	dd scasw_
	db 5,'scasd'
	dd scasd_
	db 3,'stc'
	dd stc_
	db 3,'std'
	dd std_
	db 3,'sti'
	dd sti_
	db 5,'stosb'
	dd stosb_
	db 5,'stosw'
	dd stosw_
	db 5,'stosd'
	dd stosd_
	db 3,'sub'
	dd sub_
	db 4,'test'
	dd test_
	db 4,'wait'
	dd wait_
	db 5,'xlatb'
	dd xlatb_
	db 3,'xor'
	dd xor_
	db 0
	
use16_:
	mov [code_type], 16
	ret
	
use32_:
	mov [code_type], 32
	ret	
	
db_:
	call skip_symbol
	db_save:
	cmp byte [esi], 0x27
	jne db_number
	push esi ecx
	inc esi ; skipe '
	save_string:
	lodsb
	cmp al, 13
	je missing_quote
	cmp al, 0
	je missing_quote
	cmp al, 0x27
	je save_string_end
	mov edx, edi ; check binary file limits
	inc edx
	cmp edx, [label_start]
	jge not_enough_memory
	stosb
	jmp save_string
	save_string_end:
	pop ecx esi
	jmp db_next
	db_number:
	cmp word [esi], '0x'
	jne db_label
	call get_number ; get_hex
	db_label_ok:
	cmp eax, 0xFF
	ja unvalid_size_operand
	mov edx, edi ; check binary file limits
	inc edx
	cmp edx, [label_start]
	jge not_enough_memory
	stosb
	db_next:
	mov ebx, esi
	add esi, ecx
	call skip_space
	cmp byte [esi], ','
	jne db_end
	inc esi
	call skip_space
	call get_symbol_size ; get_symbol
	jmp db_save
	db_end:
	mov esi, ebx
	ret
	db_label:
	mov edx, [label_start]
	call find_symbol
	jnc db_label_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov eax, 0
	jmp db_label_ok
	
dw_:
	call skip_symbol
	dw_save:
	cmp word [esi], '0x'
	jne dw_label
	call get_number ; get_hex
	dw_label_ok:
	cmp eax, 0xFFFF
	ja unvalid_size_operand
	mov edx, edi ; check binary file limits
	add edx, 2
	cmp edx, [label_start]
	jge not_enough_memory
	stosw
	mov ebx, esi
	add esi, ecx
	call skip_space
	cmp byte [esi], ','
	jne dw_end
	inc esi
	call skip_space
	call get_symbol_size ; get_symbol
	jmp dw_save
	dw_end:
	mov esi, ebx
	ret
	dw_label:
	mov edx, [label_start]
	call find_symbol
	jnc dw_label_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov eax, 0
	jmp dw_label_ok
	
dd_:
	call skip_symbol
	dd_save:
	cmp word [esi], '0x'
	jne dd_label
	call get_number ; get_hex
	dd_label_ok:
	cmp eax, 0xFFFFFFFF
	ja unvalid_size_operand
	mov edx, edi ; check binary file limits
	add edx, 4
	cmp edx, [label_start]
	jge not_enough_memory
	stosd
	mov ebx, esi
	add esi, ecx
	call skip_space
	cmp byte [esi], ','
	jne dd_end
	inc esi
	call skip_space
	call get_symbol_size  ; get_symbol
	jmp dd_save
	dd_end:
	mov esi, ebx
	ret
	dd_label:
	mov edx, [label_start]
	call find_symbol
	jnc dd_label_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov eax, 0
	jmp dd_label_ok
	
times_:
	call skip_symbol
	call get_number ; get_hex
	cmp eax, 0xFFFF
	ja unvalid_size_operand
	push [line_number]
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
	mov ecx, [esp]
	mov esi, [esp+4]
	mov eax, [esp+8]
	push ebx
	call dword eax
	pop ebx
	mov edx, edi ; check binary file limits
	add edx, 50
	cmp edx, [label_start]
	jge not_enough_memory
	dec ebx
	cmp ebx, 0
	jg times_loop
	pop eax ; just pop registers
	pop eax
	pop eax
	pop [line_number]
	ret
	
binary_:
	call skip_symbol
	cmp byte [esi], 0x27
	jne invalid_operand
	push esi
	push ecx
	inc esi
	push edi
	mov edi, bin_name
	mov [input_bin], edi
	copy_binary_name:
	lodsb
	cmp al, 0x27
	je copy_binary_ok
	cmp al, 0
	je invalid_operand
	cmp al, 13
	je invalid_operand
	stosb
	jmp copy_binary_name
	copy_binary_ok:
	xor al,al
	stosb
	pop edi
	mov edx, [input_bin]
	call open
	jc binary_file_nf
	mov eax, 2
	mov edx, 0
	call lseek
	push eax
	mov eax, 0
	mov edx, 0
	call lseek
	pop ecx ; file size
	mov edx, edi ; check binary file limits
	add edx, ecx
	cmp edx, [label_start]
	jge not_enough_memory
	push ecx
	mov edx, edi
	call read
	call close
	pop ecx
	add edi, ecx
	pop ecx
	pop esi
	ret
	
aaa_:
	mov al, 0x37
	stosb
	ret
	
aad_:
	mov ax, 0x0AD5
	stosw
	ret
	
aam_:
	mov ax, 0x0AD4
	stosw
	ret

aas_:
	mov al, 0x3F
	stosb
	ret
	
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
	jc sc01_al_imm8
	cmp ah, 1
	jne invalid_operand
	
	sc01_r8_r8:
	push eax
	mov al, 0x00
	add al, byte [opcode]
	stosb
	pop eax
	shl al, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stosb
	ret
	
	sc01_al_imm8:
	pop eax
	cmp al, 0
	jne sc01_r8_imm8
	call get_number ; get_hex
	cmp eax, 0xFF
	ja unvalid_size_operand
	shl eax, 8
	mov al, 0x04
	add al, byte [opcode]
	stosw
	ret
	
	sc01_r8_imm8:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, al
	or ah, 11000000b
	mov al, 0x80
	stosw
	call get_number ; get_hex
	cmp eax, 0xFF
	ja unvalid_size_operand
	stosb
	ret
	
	sc01_r16:
	call operand_size_prefix_16
	push eax ; eax=distination register code
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc sc01_ax_imm16
	cmp ah, 2
	jne invalid_operand
	
	sc01_r16_r16:
	push eax
	mov al, 0x01
	add al, byte [opcode]
	stosb
	pop eax
	shl al, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stosb
	ret
	
	sc01_ax_imm16:
	pop edx  ; edx=distination register code
	call get_number ; get_hex
	cmp eax, 0xFFFF
	ja unvalid_size_operand
	push eax
	
	cmp eax, -128
	jae sc01_r16_imm8
	cmp eax, 127
	jbe sc01_r16_imm8
	cmp dl, 0
	jne sc01_r16_imm16
	
	mov al, 0x05
	add al, byte [opcode]
	stosb
	pop eax
	stosw
	ret
	
	sc01_r16_imm16:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, dl
	or ah, 11000000b
	mov al, 0x81
	stosw
	pop eax
	stosw
	ret
	
	sc01_r16_imm8:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, dl
	or ah, 11000000b
	mov al, 0x83
	stosw
	pop eax
	stosb
	ret
	
	sc01_r32:
	call operand_size_prefix_32
	push eax ; eax=distination register code
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc sc01_eax_imm32
	cmp ah, 3
	jne invalid_operand
	
	sc01_r32_r32:
	push eax
	mov al, 0x01
	add al, byte [opcode]
	stosb
	pop eax
	shl al, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stosb
	ret
	
	sc01_eax_imm32:
	pop edx  ; edx=distination register code
	call get_number
	cmp eax, 0xFFFFFFFF
	ja unvalid_size_operand
	push eax
	
	cmp eax, -128
	jae sc01_r32_imm8
	cmp eax, 127
	jbe sc01_r32_imm8
	cmp dl, 0 ; check if eax distination ?
	jne sc01_r32_imm32
	
	mov al, 0x05
	add al, byte [opcode]
	stosb
	pop eax
	stosd
	ret
	
	sc01_r32_imm32:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, dl
	or ah, 11000000b
	mov al, 0x81
	stosw
	pop eax
	stosd
	ret
	
	sc01_r32_imm8:
	mov ah, byte [opcode+1]
	shl ah, 3
	or ah, dl
	or ah, 11000000b
	mov al, 0x83
	stosw
	pop eax
	stosb
	ret
	
call_:
	call skip_symbol
	mov edx, operand_size
	call find_symbol
	jc operand_size_ns
	cmp eax, 2
	je call_r16
	cmp eax, 4
	je call_r32
	jmp unvalid_size_operand
	
	
	call_r16:
	call skip_symbol
	call operand_size_prefix_16
	mov edx, all_registers
	call find_symbol
	jc call_rel16
	cmp ah, 2
	jne invalid_operand
	mov ah, 2
	shl ah, 3
	or ah, 11000000b
	or ah, al
	mov al, 0xFF
	stosw
	ret
	
	
	call_rel16:
	mov edx, [label_start]
	call find_symbol
	jnc call_rel16_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov al, 0xE8
	stosb
	mov eax, 0
	stosw
	ret
	
	call_rel16_ok:
	mov ebx, edi
	add ebx, 3 ; 3=size of instruction
	sub ebx, [binary_start]
	sub eax, ebx
	cmp eax, -32768 ; -32768 bytes before the end of the instruction
	jl relative_out_of_range
	cmp eax, +32767 ; +32767 bytes after the end of the instruction
	jg relative_out_of_range
	push eax
	mov al, 0xE8
	stosb
	pop eax
	stosw
	ret
	
	call_r32:
	call skip_symbol
	call operand_size_prefix_32
	mov edx, all_registers
	call find_symbol
	jc call_rel32
	cmp ah, 3
	jne invalid_operand
	mov ah, 2
	shl ah, 3
	or ah, 11000000b
	or ah, al
	mov al, 0xFF
	stosw
	ret
	
	call_rel32:
	mov edx, [label_start]
	call find_symbol
	jnc call_rel32_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov al, 0xE8
	stosb
	mov eax, 0
	stosd
	ret
	
	call_rel32_ok:
	mov ebx, edi
	add ebx, 5 ; 5=size of instruction
	sub ebx, [binary_start]
	sub eax, ebx
	cmp eax, -2147483648 ; -2147483648 bytes before the end of the instruction
	jl relative_out_of_range
	cmp eax, +2147483647 ; +2147483647 bytes after the end of the instruction
	jg relative_out_of_range
	push eax
	mov al, 0xE8
	stosb
	pop eax
	stosd
	ret
	
cbw_:
	call operand_size_prefix_16
	mov al, 0x98
	stosb
	ret
	
cwde_:
	call operand_size_prefix_32
	mov al, 0x98
	stosb
	ret
	
clc_:
	mov al, 0xF8
	stosb
	ret
	
cld_:
	mov al, 0xFC
	stosb
	ret
	
cli_:
	mov al, 0xFA
	stosb
	ret
	
clts_:
	mov ax, 0x060F
	stosw
	ret

cmc_:
	mov al, 0xF5
	stosb
	ret
	
cmp_:
	mov byte [opcode], 0x38
	mov byte [opcode+1], 0x07
	jmp same_code_01
	
cmpsb_:
	mov al, 0xA6
	stosb
	ret
	
cmpsw_:
	call operand_size_prefix_16
	mov al, 0xA7
	stosb
	ret
	
cmpsd_:
	call operand_size_prefix_32
	mov al, 0xA7
	stosb
	ret
	
cwd_:
	call operand_size_prefix_16
	mov al, 0x99
	stosb
	ret
	
cdq_:
	call operand_size_prefix_32
	mov al, 0x99
	stosb
	ret
	
daa_:
	mov al, 0x27
	stosb
	ret
	
das_:
	mov al, 0x2F
	stosb
	ret
	
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
	stosb
	ret
	
	dec_r32:
	call operand_size_prefix_32
	add al, 0x48
	stosb
	ret
	
div_:
	mov byte [opcode], 0xF6
	mov byte [opcode+1], 0x06
	jmp same_code_02
	
hlt_:
	mov al, 0xF4
	stosb
	ret
	
idiv_:
	mov byte [opcode], 0xF6
	mov byte [opcode+1], 0x07
	jmp same_code_02
	
imul_:
	mov byte [opcode], 0xF6
	mov byte [opcode+1], 0x05
	jmp same_code_02
	

	
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
	stosb
	pop eax
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or al, bl
	stosb
	ret
	
	sc02_r16:
	push eax
	call operand_size_prefix_16
	mov al, byte [opcode]
	add al, 1
	stosb
	pop eax
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or al, bl
	stosb
	ret
	
	sc02_r32:
	push eax
	call operand_size_prefix_32
	mov al, byte [opcode]
	add al, 1
	stosb
	pop eax
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or al, bl
	stosb
	ret
	
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
	stosb
	call get_number
	cmp eax, 0xFF
	ja unvalid_size_operand
	stosb
	ret
	
	in_ax_imm8:
	cmp al, 0
	jne invalid_operand
	call operand_size_prefix_16
	call find_source_operand
	mov al, 0xE5
	stosb
	call get_number
	cmp eax, 0xFF
	ja unvalid_size_operand
	stosb
	ret
	
	in_eax_imm8:
	cmp al, 0
	jne invalid_operand
	call operand_size_prefix_32
	call find_source_operand
	mov al, 0xE5
	stosb
	call get_number
	cmp eax, 0xFF
	ja unvalid_size_operand
	stosb
	ret
	
inc_:
	call skip_symbol
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 2
	je inc_r16
	cmp ah, 3
	je inc_r32
	jmp invalid_operand
	
	inc_r16:
	call operand_size_prefix_16
	add al, 0x40
	stosb
	ret
	
	inc_r32:
	call operand_size_prefix_32
	add al, 0x40
	stosb
	ret
	
insb_:
	mov al, 0x6C
	stosb
	ret
	
insw_:
	call operand_size_prefix_16
	mov al, 0x6D
	stosb
	ret
	
insd_:
	call operand_size_prefix_32
	mov al, 0x6D
	stosb
	ret
	
int_:
	call skip_symbol
	call get_number
	cmp eax, 0xFF
	ja unvalid_size_operand
	shl eax, 8
	mov al, 0xCD
	stosw
	ret
	
int3_:
	mov al, 0xCC
	stosb
	ret
	
into_:
	mov al, 0xCE
	stosb
	ret

iretd_:
	call operand_size_prefix_32
iret_:
	mov al, 0xCF
	stosb
	ret
	
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
	mov edx, operand_size
	call find_symbol
	jc operand_size_ns
	cmp eax, 1
	jg unvalid_size_operand
	call skip_symbol
	mov edx, [label_start]
	call find_symbol
	jnc je_rel8
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov eax, 0
	mov al, byte [opcode]
	stosw
	ret
	
	je_rel8:
	mov ebx, edi
	add ebx, 2 ; 2=size of instruction
	sub ebx, [binary_start]
	sub eax, ebx
	cmp eax, -128 ; 128 bytes before the end of the instruction
	jl relative_out_of_range
	cmp eax, +127   ; 127 bytes after the end of the instruction
	jg relative_out_of_range
	shl eax, 8
	mov al, byte [opcode]
	stosw
	ret
	
jmp_:
	call skip_symbol
	cmp word [esi], '0x'
	je jmp_ptr16
	mov edx, operand_size
	call find_symbol
	jc operand_size_ns
	cmp eax, 1
	je jmp_rel8
	cmp eax, 2
	je jmp_r16
	cmp eax, 4
	je jmp_r32
	jmp unvalid_size_operand
	
	jmp_rel8:
	call skip_symbol
	mov edx, [label_start]
	call find_symbol
	jnc jmp_rel8_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov eax, 0
	mov al, 0xEB
	stosw
	ret
	
	jmp_rel8_ok: ; jmp short rel8
	mov ebx, edi
	add ebx, 2 ; 2=size of instruction
	sub ebx, [binary_start]
	sub eax, ebx
	cmp eax, -128
	jl relative_out_of_range
	cmp eax, 127
	jg relative_out_of_range
	shl eax, 8
	mov al, 0xEB
	stosw
	ret
	
	jmp_r16:
	call skip_symbol
	call operand_size_prefix_16
	mov edx, all_registers
	call find_symbol
	jc jmp_rel16
	cmp ah, 2
	jne invalid_operand
	mov ah, 4
	shl ah, 3
	or ah, 11000000b
	or ah, al
	mov al, 0xFF
	stosw
	ret
	
	jmp_rel16: ; jmp near rel16
	mov edx, [label_start]
	call find_symbol
	jnc jmp_rel16_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov al, 0xE9
	stosb
	mov eax, 0
	stosw
	ret
	
	jmp_rel16_ok:
	mov ebx, edi
	add ebx, 3 ; 3=size of instruction
	sub ebx, [binary_start]
	sub eax, ebx
	cmp eax, -32768
	jl relative_out_of_range
	cmp eax, 32767
	jg relative_out_of_range
	push eax
	mov al, 0xE9
	stosb
	pop eax
	stosw
	ret
	
	jmp_r32:
	call skip_symbol
	call operand_size_prefix_32
	mov edx, all_registers
	call find_symbol
	jc jmp_rel32
	cmp ah, 3
	jne invalid_operand
	mov ah, 4
	shl ah, 3
	or ah, 11000000b
	or ah, al
	mov al, 0xFF
	stosw
	ret
	
	jmp_rel32: ; jmp near rel32
	mov edx, [label_start]
	call find_symbol
	jnc jmp_rel32_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov al, 0xE9
	stosb
	mov eax, 0
	stosd
	ret
	
	jmp_rel32_ok:
	mov ebx, edi
	add ebx, 5 ; 5=size of instruction
	sub ebx, [binary_start]
	sub eax, ebx
	cmp eax, -2147483648
	jl relative_out_of_range
	cmp eax, 2147483647
	jg relative_out_of_range
	push eax
	mov al, 0xE9
	stosb
	pop eax
	stosd
	ret
	
	jmp_ptr16:
	call get_number
	cmp eax, 0xFFFF
	ja unvalid_size_operand
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
	cmp eax, 0xFFFF
	ja unvalid_size_operand
	call operand_size_prefix_16
	push eax
	mov al, 0xEA
	stosb
	pop eax
	stosw
	pop eax
	stosw
	ret
	
	jmp_ptr16_32: ; jmp far pword
	call skip_symbol
	call get_number
	cmp eax, 0xFFFFFFFF
	ja unvalid_size_operand
	call operand_size_prefix_32
	push eax
	mov al, 0xEA
	stosb
	pop eax
	stosd
	pop eax
	stosw
	ret
	
lahf_:
	mov al, 0x9F
	stosb
	ret
	
leave_:
	mov al, 0xC9
	stosb
	ret
	
lgdt_:
	mov byte [opcode+1], 2
	jmp ldt_
	
lidt_:
	mov byte [opcode+1], 3
	jmp ldt_
	
	
ldt_:
	call skip_symbol
	mov edx, operand_size
	call find_symbol
	jc invalid_operand
	cmp eax, 6
	jne unvalid_size_operand
	call get_address
	call operand_size_prefix_32
	push eax
	mov ax, 0x010F
	stosw
	movzx ebx, byte [opcode+1] ; 2
	shl ebx, 3
	pop eax
	or al, bl
	stosb
	ret
	
lock_:
	mov al, 0xF0
	stosb
	ret
	
lodsb_:
	mov al, 0xAC
	stosb
	ret
	
lodsw_:
	call operand_size_prefix_16
	mov al, 0xAD
	stosb
	ret
	
lodsd_:
	call operand_size_prefix_32
	mov al, 0xAD
	stosb
	ret
	
loop_:
	call skip_symbol
	mov edx, operand_size
	call find_symbol
	jc operand_size_ns
	cmp eax, 1
	jne unvalid_size_operand
	call skip_symbol
	mov edx, [label_start]
	call find_symbol
	jnc loop_rel8 ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	mov eax, 0
	mov al, 0xE2
	stosw
	ret
	
	loop_rel8:
	mov ebx, edi
	add ebx, 2 ; 2=size of instruction
	sub ebx, [binary_start]
	sub eax, ebx
	cmp eax, -128 ; 128 bytes before the end of the instruction
	jl relative_out_of_range
	cmp eax, 127   ; 127 bytes after the end of the instruction
	jg relative_out_of_range
	shl eax, 8
	mov al, 0xE2 ; loop relative
	stosw
	ret
	
	
;=================================
; save address size prefix and
; ret: eax = index register code
;=================================
get_address:
	add esi, ecx
	call skip_space
	cmp byte [esi], '['
	jne invalid_operand
	inc esi
	call skip_space
	call get_symbol_size
	
	mov edx, all_registers
	call find_symbol
	jc no_segment_reg
	cmp ah, 4
	jne no_segment_reg
	shr eax, 16
	stosb
	call skip_symbol
	cmp al, ':'
	jne invalid_operand
	inc esi
	call skip_space
	call get_symbol_size
	no_segment_reg:
	
	mov edx, register_index
	call find_symbol
	jc invalid_operand
	push eax
	cmp ah, 3
	je reg_index_32
	call address_size_prefix_16
	jmp reg_index_16
	reg_index_32:
	call address_size_prefix_32
	reg_index_16:
	add esi, ecx
	call skip_space
	cmp byte [esi], ']'
	jne invalid_operand
	mov ecx, 1 ; to skipe  ']'
	pop eax
	ret
	
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
	
	mov_r8_r8:
	mov edx, all_registers
	call find_symbol
	jc mov_r8_m8
	cmp ah, 1
	jne mov_r8_m8
	mov ah, al ; eax=source register code
	shl ah, 3
	or ah, 11000000b ; Mod.R/M.mod = 11: Register
	pop ebx ; now ebx=distination register code
	or ah, bl
	mov al, 0x88
	stosw
	ret
	
	mov_r8_m8:
	mov edx, operand_size
	call find_symbol
	jc mov_r8_imm8
	cmp eax, 1
	jne unvalid_size_operand
	call get_address
	push eax
	mov al, 0x8A
	stosb
	pop eax
	pop ebx ; ebx=distination register code
	shl ebx, 3
	and bl, 00111000b ; Mod.R/M.mod = 00: [Memory]
	or al, bl
	stosb
	ret
	
	mov_r8_imm8:
	cmp word [esi], '0x'
	jne mov_r8_label
	call get_number
	jmp mov_r8_label_ok
	
	mov_r8_label:
	mov edx, [label_start]
	call find_symbol
	jnc mov_r8_label_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	pop ebx
	add bl, 0xB0
	mov al, bl
	mov ah, 0
	stosw
	ret
	
	mov_r8_label_ok:
	cmp eax, 0xFF
	ja unvalid_size_operand
	pop ebx
	add bl, 0xB0
	shl eax, 8
	mov al, bl
	stosw
	ret
	
	mov_m8:
	call get_address
	push eax
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc mov_m8_imm8
	cmp ah, 1
	jne mov_m8_imm8
	
	mov_m8_r8:
	push eax
	mov al, 0x88
	stosb
	pop eax
	shl eax, 3
	pop ebx ; ebx=distination register code
	or al, bl
	and al, 00111111b ; Mod.R/M.mod = 00: [Memory]
	stosb
	ret
	
	mov_m8_imm8:
	cmp word [esi], '0x'
	jne invalid_operand
	pop ebx ; ebx=distination register code
	and bl, 00000111b
	mov ah, bl
	mov al, 0xC6
	stosw
	call get_number
	cmp eax, 0xFF
	ja unvalid_size_operand
	stosb
	ret
	
	mov_r16:
	push eax ; eax=distination register code
	call operand_size_prefix_16
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	
	mov_r16_r16:
	mov edx, all_registers
	call find_symbol
	jc mov_r16_m16
	cmp ah, 4
	je mov_r16_seg
	cmp ah, 2
	jne mov_r16_m16
	mov ah, al ; eax=source register code
	shl ah, 3
	or ah, 11000000b
	pop ebx
	or ah, bl
	mov al, 0x89
	stosw
	ret
	
	mov_r16_m16:
	mov edx, operand_size
	call find_symbol
	jc mov_r16_imm16
	cmp eax, 2
	jne unvalid_size_operand
	call get_address
	push eax
	mov al, 0x8B
	stosb
	pop eax
	pop ebx ; ebx=distination register code
	shl ebx, 3
	and bl, 00111000b ; Mod.R/M.mod = 00: [Memory]
	or al, bl
	stosb
	ret
	
	mov_r16_seg:
	mov ah, al ; eax=source register code
	shl ah, 3
	or ah, 11000000b
	pop ebx
	or ah, bl
	mov al, 0x8C
	stosw
	ret
	
	mov_r16_imm16:
	cmp word [esi], '0x'
	jne mov_r16_label
	call get_number
	jmp mov_r16_label_ok
	
	mov_r16_label:
	mov edx, [label_start]
	call find_symbol
	jnc mov_r16_label_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	pop ebx
	add bl, 0xB8
	mov al, bl
	stosb
	mov eax, 0
	stosw
	ret
	
	mov_r16_label_ok:
	cmp eax, 0xFFFF
	ja unvalid_size_operand
	pop ebx
	add bl, 0xB8
	push eax
	mov al, bl
	stosb
	pop eax
	stosw
	ret
	
	mov_m16:
	call get_address
	push eax
	call operand_size_prefix_16
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc mov_m16_imm16
	cmp ah, 2
	jne mov_m16_imm16
	
	mov_m16_r16:
	push eax
	mov al, 0x89
	stosb
	pop eax
	shl eax, 3
	pop ebx ; ebx=distination register code
	or al, bl
	and al, 00111111b ; Mod.R/M.mod = 00: [Memory]
	stosb
	ret
	
	mov_m16_imm16:
	cmp word [esi], '0x'
	jne invalid_operand
	pop ebx ; ebx=distination register code
	and bl, 00000111b
	mov ah, bl
	mov al, 0xC7
	stosw
	call get_number
	cmp eax, 0xFFFF
	ja unvalid_size_operand
	stosw
	ret
	
	mov_r32:
	push eax ; eax=distination register code
	call find_source_operand
	cmp byte [esi], '['
	je operand_size_ns
	
	mov_r32_r32:
	mov edx, all_registers
	call find_symbol
	jc mov_r32_cr
	cmp ah, 3
	jne mov_r32_cr
	call operand_size_prefix_32
	mov ah, al ; eax=source register code
	shl ah, 3
	or ah, 11000000b
	pop ebx
	or ah, bl
	mov al, 0x89
	stosw
	ret
	
	mov_r32_cr:
	mov edx, all_registers
	call find_symbol
	jc mov_r32_m32
	cmp ah, 5
	jne mov_r32_m32
	push eax
	mov ax, 0x200F
	stosw
	pop eax
	shl al, 3 ; eax=source register code
	or al, 11000000b
	pop ebx
	or al, bl
	stosb
	ret
	
	mov_r32_m32:
	mov edx, operand_size
	call find_symbol
	jc mov_r32_imm32
	cmp eax, 4
	jne unvalid_size_operand
	call get_address
	push eax
	call operand_size_prefix_32
	mov al, 0x8B
	stosb
	pop eax
	pop ebx ; ebx=distination register code
	shl bl, 3
	and bl, 00111000b ; Mod.R/M.mod = 00: [Memory]
	or al, bl
	stosb
	ret
	
	mov_r32_imm32:
	cmp word [esi], '0x'
	jne mov_r32_label
	call get_number
	jmp mov_r32_label_ok
	
	mov_r32_label:
	mov edx, [label_start]
	call find_symbol
	jnc mov_r32_label_ok ; jnc = yes label found
	cmp [count_pass], 2
	jge invalid_operand
	mov [need_pass], 1
	call operand_size_prefix_32
	pop ebx
	add bl, 0xB8
	mov al, bl
	stosb
	mov eax, 0
	stosd
	ret
	
	mov_r32_label_ok:
	cmp eax, 0xFFFFFFFF
	ja unvalid_size_operand
	call operand_size_prefix_32
	pop ebx
	add bl, 0xB8
	push eax
	mov al, bl
	stosb
	pop eax
	stosd
	ret
	
	mov_m32:
	call get_address
	push eax
	call operand_size_prefix_32
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc mov_m32_imm32
	cmp ah, 3
	jne mov_m32_imm32
	
	mov_m32_r32:
	push eax
	mov al, 0x89
	stosb
	pop eax
	shl eax, 3
	pop ebx ; ebx=distination register code
	or al, bl
	and al, 00111111b ; Mod.R/M.mod = 00: [Memory]
	stosb
	ret
	
	mov_m32_imm32:
	cmp word [esi], '0x'
	jne invalid_operand
	pop ebx ; ebx=distination register code
	and bl, 00000111b
	mov ah, bl
	mov al, 0xC7
	stosw
	call get_number
	cmp eax, 0xFFFFFFFF
	ja unvalid_size_operand
	stosd
	ret
	
	mov_seg:
	cmp al, 1
	je invalid_operand
	push eax ; eax=distination register code
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
	or bl, al ; eax=source register code
	mov ah, bl
	mov al, 0x8E
	stosw
	ret
	
	mov_cr_r32:
	push eax ; eax=distination register code
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 3
	jne invalid_operand
	push eax
	mov ax, 0x220F
	stosw
	pop eax
	pop ebx   ; ebx=distination register code
	shl bl, 3 ; eax=source register code
	or bl, 11000000b
	or al, bl
	stosb
	ret
	
	
movsb_:
	mov al, 0xA4
	stosb
	ret
	
movsw_:
	call operand_size_prefix_16
	mov al, 0xA5
	stosb
	ret
	
movsd_:
	call operand_size_prefix_32
	mov al, 0xA5
	stosb
	ret
	
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
	je mov_x_r16_r8
	cmp ah, 3
	je mov_x_r32_r8
	jmp invalid_operand
	
	mov_x_r16_r8:
	push eax
	call operand_size_prefix_16
	call find_source_operand
	mov edx, all_registers
	call find_symbol
	jc invalid_operand
	cmp ah, 1
	jne invalid_operand
	push eax
	mov al, byte [opcode]
	mov ah, byte [opcode+1]
	stosw
	pop eax
	pop ebx ; now ebx=distination register code
	shl bl, 3
	or bl, 11000000b ; Mod.R/M.mod = 11: Register
	or al, bl
	stosb
	ret
	
	mov_x_r32_r8:
	push eax
	call operand_size_prefix_32
	call find_source_operand
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
	stosw
	pop eax
	pop ebx ; now ebx=distination register code
	shl bl, 3
	or bl, 11000000b ; Mod.R/M.mod = 11: Register
	or al, bl
	stosb
	ret
	
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
	stosw
	pop eax
	pop ebx ; now ebx=distination register code
	shl bl, 3
	or bl, 11000000b ; Mod.R/M.mod = 11: Register
	or al, bl
	stosb
	ret
	
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
	stosb
	ret
	
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
	cmp eax, 0xFF
	ja unvalid_size_operand
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
	stosb
	pop eax
	stosb
	ret
	
	out_imm8_ax:
	cmp al, 0
	jne invalid_operand
	call operand_size_prefix_16
	mov al, 0xE7
	stosb
	pop eax
	stosb
	ret
	
	out_imm8_eax:
	cmp al, 0
	jne invalid_operand
	call operand_size_prefix_32
	mov al, 0xE7
	stosb
	pop eax
	stosb
	ret
	
outsb_:
	mov al, 0x6E
	stosb
	ret
	
outsw_:
	call operand_size_prefix_16
	mov al, 0x6F
	stosb
	ret
	
outsd_:
	call operand_size_prefix_32
	mov al, 0x6F
	stosb
	ret
	
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
	stosb
	ret
	
	pop_r32:
	call operand_size_prefix_32
	add al, 0x58
	stosb
	ret
	
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
	stosb
	ret
	pop_ss:
	mov al, 0x17
	stosb
	ret
	pop_ds:
	mov al, 0x1F
	stosb
	ret
	pop_fs:
	mov ax, 0xA10F
	stosw
	ret
	pop_gs:
	mov ax, 0xA90F
	stosw
	ret
	
popad_:
	call operand_size_prefix_32
popa_:
	mov al, 0x61
	stosb
	ret
	
popf_:
	mov al, 0x9D
	stosb
	ret
	
push_:
	call skip_symbol
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
	stosb
	ret
	
	push_r32:
	call operand_size_prefix_32
	add al, 0x50
	stosb
	ret
	
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
	stosb
	ret
	push_cs:
	mov al, 0x0E
	stosb
	ret
	push_ss:
	mov al, 0x16
	stosb
	ret
	push_ds:
	mov al, 0x1E
	stosb
	ret
	push_fs:
	mov ax, 0xA00F
	stosw
	ret
	push_gs:
	mov ax, 0xA80F
	stosw
	ret
	
pushad_:
	call operand_size_prefix_32
pusha_:
	mov al, 0x60
	stosb
	ret
	
pushf_:
	mov al, 0x9C
	stosb
	ret
	
rep_:
	mov al, 0xF3
	stosb
	ret
		
repne_:
	mov al, 0xF2
	stosb
	ret
	
ret_:
	mov al, 0xC3
	stosb
	ret
	
sahf_:
	mov al, 0x9E
	stosb
	ret
	
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
	call find_source_operand
	jmp shlr
	
	shlr_r16:
	push eax
	call operand_size_prefix_16
	call find_source_operand
	jmp shlr
	
	shlr_r32:
	push eax
	call operand_size_prefix_32
	call find_source_operand
	jmp shlr
	
	shlr:
	call get_number
	cmp eax, 0xFF
	ja unvalid_size_operand
	pop edx
	push eax
	cmp eax, 1 ; Shift 1
	jne shlr_reg_imm8
	
	shlr_r_1:
	mov al, byte [opcode]
	add al, 0x10
	stosb
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or bl, dl
	mov al, bl
	stosb
	pop eax
	ret
	
	shlr_reg_imm8:
	mov al, byte [opcode]
	stosb
	movzx ebx, byte [opcode+1]
	shl ebx, 3
	or bl, 11000000b
	or bl, dl
	mov al, bl
	stosb
	pop eax
	stosb
	ret
	
sbb_:
	mov byte [opcode], 0x18
	mov byte [opcode+1], 0x03
	jmp same_code_01
	
scasb_:
	mov al, 0xAE
	stosb
	ret
	
scasw_:
	call operand_size_prefix_16
	mov al, 0xAF
	stosb
	ret
	
scasd_:
	call operand_size_prefix_32
	mov al, 0xAF
	stosb
	ret
	
stc_:
	mov al, 0xF9
	stosb
	ret
	
std_:
	mov al, 0xFD
	stosb
	ret
	
sti_:
	mov al, 0xFB
	stosb
	ret
	
stosb_:
	mov al, 0xAA
	stosb
	ret
	
stosw_:
	call operand_size_prefix_16
	mov al, 0xAB
	stosb
	ret
	
stosd_:
	call operand_size_prefix_32
	mov al, 0xAB
	stosb
	ret
	
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
	stosb
	pop eax
	shl eax, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stosb
	ret

	test_al_imm8:
	pop eax
	cmp al, 0
	jne test_r8_imm8
	call get_number
	cmp eax, 0xFF
	ja unvalid_size_operand
	shl eax, 8
	mov al, 0xA8
	stosw
	ret
	
	test_r8_imm8:
	mov ah, 0
	shl ah, 3
	or ah, al
	or ah, 11000000b
	mov al, 0xF6
	stosw
	call get_number
	cmp eax, 0xFF
	ja unvalid_size_operand
	stosb
	ret
	
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
	stosb
	pop eax
	shl eax, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stosb
	ret

	test_ax_imm16:
	pop eax
	cmp al, 0
	jne test_r16_imm16
	call get_number
	cmp eax, 0xFFFF
	ja unvalid_size_operand
	push eax
	mov al, 0xA9
	stosb
	pop eax
	stosw
	ret
	
	test_r16_imm16:
	mov ah, 0
	shl ah, 3
	or ah, al
	or ah, 11000000b
	mov al, 0xF7
	stosw
	call get_number
	cmp eax, 0xFFFF
	ja unvalid_size_operand
	stosw
	ret
	
	
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
	stosb
	pop eax
	shl eax, 3
	or al, 11000000b
	pop ebx
	or al, bl
	stosb
	ret

	test_eax_imm32:
	pop eax
	cmp al, 0
	jne test_r32_imm32
	call get_number
	cmp eax, 0xFFFFFFFF
	ja unvalid_size_operand
	push eax
	mov al, 0xA9
	stosb
	pop eax
	stosd
	ret
	
	test_r32_imm32:
	mov ah, 0
	shl ah, 3
	or ah, al
	or ah, 11000000b
	mov al, 0xF7
	stosw
	call get_number
	cmp eax, 0xFFFFFFFF
	ja unvalid_size_operand
	stosd
	ret
	
wait_:
	mov al, 0x9B
	stosb
	ret
	
xlatb_:
	mov al, 0xD7
	stosb
	ret
	
xor_:
	mov byte [opcode], 0x30
	mov byte [opcode+1], 0x06
	jmp same_code_01
	

	

asm_   db 'minis assembler version 0.09',13,10,0
usage_ db 'usage: as source binary',13,10,0
nem_   db 'error: not enough memory.',13,10,0
nosf_  db 'error: source file not found.',13,10,0
ecf_   db 'error: create file failed.',13,10,0
uns_   db 'error: unknown instruction.',13,10,0
ecol_  db 'error: extra characters on line.',13,10,0
eivo_  db 'error: invalid operand.',13,10,0
eios_  db 'error: invalid size of operand.',13,10,0
emeq_  db 'error: missing end quote.',13,10,0
einl_  db 'error: invalid label.',13,10,0
elad_  db 'error: label already defined.',13,10,0
erjr_  db 'error: relative address outside range.',13,10,0
eons_  db 'error: operand size not specified.',13,10,0
erwl_  db 'error: reserved word used as label.',13,10,0
bfnf_  db 'error: binary file not found.',13,10,0
line_  db 'line : [       ]',13,10,0
succ_  db 'success:            bytes.',13,10,0


line_number dd 0
code_type db 0

memory_start dd 0
memory_end dd 0
source_start dd 0
source_end dd 0
binary_start dd 0
binary_end dd 0
label_start dd 0
label_end   dd 0

count_pass  dd 0
need_pass   dd 0

input_file dd 0
output_file dd 0
input_bin dd 0

opcode db 0,0

bcount dd 0
binary_size dd 0

bin_name rb 128
save_cmd rb 255

stack 0x1000

section '.idata' import data readable writeable

	dd 0,0,0,rva kernel_name,rva kernel_table
	dd 0,0,0,0,0

kernel_table:
	ExitProcess dd rva _ExitProcess
	CreateFile dd rva _CreateFileA
	ReadFile dd rva _ReadFile
	WriteFile dd rva _WriteFile
	CloseHandle dd rva _CloseHandle
	SetFilePointer dd rva _SetFilePointer
	GetCommandLine dd rva _GetCommandLineA
	GetStdHandle dd rva _GetStdHandle
	VirtualAlloc dd rva _VirtualAlloc
	dd 0

kernel_name db 'KERNEL32.DLL',0

_ExitProcess dw 0
	db 'ExitProcess',0
_CreateFileA dw 0
	db 'CreateFileA',0
_ReadFile dw 0
	db 'ReadFile',0
_WriteFile dw 0
	db 'WriteFile',0
_CloseHandle dw 0
	db 'CloseHandle',0
_SetFilePointer dw 0
	db 'SetFilePointer',0
_GetCommandLineA dw 0
	db 'GetCommandLineA',0
_GetStdHandle dw 0
	db 'GetStdHandle',0
_VirtualAlloc dw 0
	db 'VirtualAlloc',0

