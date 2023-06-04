/* Register usage:
   tp points to the next instruction.
   gp points to the current instruction -- Instruction Pointer.
   fp is the Return Stack pointer.
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

	.text
	.globl _start
_start:
	la fp, return_stack_top

	.section .rodata
cold_start:
	.int QUIT

