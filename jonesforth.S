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

/*
	As you will have seen in the background documentation, FORTH has two stacks, an ordinary
	stack for parameters, and a return stack which is a bit more mysterious.  But our return
	stack is just the stack I talked about in the previous paragraph, used to save tp/%esi when
	calling from a FORTH word into another FORTH word.

	In this FORTH, we are using the normal stack pointer (sp/%esp) for the parameter stack.
	We will use the risc-v/i386's "other" stack pointer (fp/%ebp, usually called the "frame pointer")
	for our return stack.

	I've got two macros which just wrap up the details of using fp/%ebp for the return stack.
	You use them as for example "PUSHRSP gp"/"PUSHRSP %eax" (push gp/%eax on the return stack) or "POPRSP t1"/"POPRSP %ebx"
	(pop top of return stack into t1/%ebx).
*/

/* Macros to deal with the return stack pointed to by fp. */
	.macro PUSHRSP reg
	sw \reg,-4(fp)
	addi fp,fp,-4
	.endm
	
	.macro POPRSP reg
	mv \reg,fp
	addi fp,fp,4
	.endm
/*
	In FORTH the interpreter function is often called DOCOL (I think it means "DO COLON" because
	all FORTH definitions start with a colon, as in : DOUBLE DUP + ;

	The "interpreter" (it's not really "interpreting") just needs to push the old tp/%esi on the
	stack and set tp/%esi to the first word in the definition.  Remember that we jumped to the
	function using jalr zero,gp,0 / JMP *(%eax)?  Well a consequence of that is that conveniently gp/%eax contains
	the address of this codeword, so just by adding 4 to it we get the address of the first
	data word.  Finally after setting up tp/%esi, it just does NEXT which causes that first word
	to run.
*/
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

/*
	BUILT-IN WORDS ----------------------------------------------------------------------

	Remember our dictionary entries (headers)?  Let's bring those together with the codeword
	and data words to see how : DOUBLE DUP + ; really looks in memory.

	  pointer to previous word
	   ^
	   |
	+--|------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
	+---------+---+---+---+---+---+---+---+---+------------+--|---------+------------+------------+
           ^       len                         pad  codeword      |
	   |							  V
	  LINK in next word				points to codeword of DUP
	
	Initially we can't just write ": DOUBLE DUP + ;" (ie. that literal string) here because we
	don't yet have anything to read the string, break it up at spaces, parse each word, etc. etc.
	So instead we will have to define built-in words using the GNU assembler data constructors
	(like .int, .byte, .string, .ascii and so on -- look them up in the gas info page if you are
	unsure of them).

	The long way would be:

	.int <link to previous word>
	.byte 6			// len
	.ascii "DOUBLE"		// string
	.byte 0			// padding
DOUBLE: .int DOCOL		// codeword
	.int DUP		// pointer to codeword of DUP
	.int PLUS		// pointer to codeword of +
	.int EXIT		// pointer to codeword of EXIT

	That's going to get quite tedious rather quickly, so here I define an assembler macro
	so that I can just write:

	defword "DOUBLE",6,,DOUBLE
	.int DUP,PLUS,EXIT

	and I'll get exactly the same effect.

	Don't worry too much about the exact implementation details of this macro - it's complicated!
*/

	.set F_IMMED,0x80
	.set F_HIDDEN,0x20
	.set F_LENMASK,0x1f

	# Store the chain of links.
1:
	.set link,0

/* defword macro */
	.macro defword name, namelen, flags=0, label
	.section .rodata
	.align 4
	.globl name_\label
name_\label :
	.int link		// link
	.set link,name_\label
	.byte \flags+\namelen	// flags + length byte
	.ascii "\name"		// the name
	.align 4		// padding to next 4 byte boundary
	.globl \label
\label :
	.int DOCOL		// codeword - the interpreter
	// list of word pointers follow
	.endm

/*
	Similarly I want a way to write words written in assembly language.  There will be quite a few
	of these to start with because, well, everything has to start in assembly before there's
	enough "infrastructure" to be able to start writing FORTH words, but also I want to define
	some common FORTH words in assembly language for speed, even though I could write them in FORTH.

	This is what DUP looks like in memory:

	  pointer to previous word
	   ^
	   |
	+--|------+---+---+---+---+------------+
	| LINK    | 3 | D | U | P | code_DUP ---------------------> points to the assembly
	+---------+---+---+---+---+------------+		    code used to write DUP,
           ^       len              codeword			    which ends with NEXT.
	   |
	  LINK in next word

	Again, for brevity in writing the header I'm going to write an assembler macro called defcode.
	As with defword above, don't worry about the complicated details of the macro.
*/

/* defcode macro */
	.macro defcode name, namelen, flags=0, label
	.section .rodata
	.align 4
	.globl name_\label
#name_\label :
#	.int link
#	.set link,name_\label
	.int 1b
1:
	.byte \flags+\namelen	// flags + length byte
	.ascii "\name"		// the name
	.align 4		// padding to next 4 byte boundary
	.globl \label
\label :
	.int code_\label	// codeword
	.text
	.globl code_\label
code_\label :			// assembler code follows
	.endm

/*
	Now some easy FORTH primitives.  These are written in assembly for speed.  If you understand
	risc-v assembly language then it is worth reading these.  However if you don't understand assembly
	you can skip the details.
*/

	# DROP drops the top of stack
	defcode "DROP",4,,DROP
	mv gp,sp
	addi sp,sp,-4
	NEXT

	defcode "SWAP",4,,SWAP
	lw t0,-4(sp)
	lw t1,0(sp)
	sw t0,0(sp)
	sw t1,-4(sp)
	NEXT
