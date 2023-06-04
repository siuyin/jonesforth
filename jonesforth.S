/* jonesforth.S adapted to target RISC-V ch32v003 by Loh Siu Yin.
   Register usage:
   tp (%esi in jonesforth) points to the next instruction.
   gp (%eax) points to the current instruction -- Instruction Pointer.
   fp (%ebp) is the Return Stack pointer.
*/

/* riscv64-unknown-elf-gcc -march=rv32ec -mabi=ilp32e -static -nostdlib -g -T simple.ld -o jonesforth.elf jonesforth.S */
	.set JONES_VERSION,47

/* Firstly it reads the memory at tp/%esi into the accumulator gp/%eax.
   Secondly it increments tp/%esi by 4 bytes.
   Now we just need to jump to the address in gp/%eax.
 */
/* NEXT macro */
	.macro NEXT
	mv gp,tp
	addi tp,tp,4
	jalr zero,gp,0
	.endm

/* Macros to deal with the return stack pointed to by fp. */
	.macro PUSHRSP reg
	sw \reg,-4(fp)
	addi fp,fp,-4
	.endm
	
	.macro POPRSP reg
	mv \reg,fp
	addi fp,fp,4
	.endm

/* DOCOL - the interpreter */
	.text
	.align 4

DOCOL:
	PUSHRSP tp
	add tp,gp,4
	NEXT


/* Assembler entry point. */
	.text
	.globl _start
_start:
	la fp,return_stack_top
	# FIXME
	# j set_up_data_segment
	la tp,cold_start

	.section .rodata
cold_start:
	# FIXME
	#.int QUIT

	.set F_IMMED,0x80
	.set F_HIDDEN,0x20
	.set F_LENMASK,0x1f

	.set link,0


