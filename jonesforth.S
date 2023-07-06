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
#name_\label :
#	.int link		// link
#	.set link,name_\label
name_\label :
	.int 1b
1:
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
name_\label :
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

	# DROP drops the top of stack.
	defcode "DROP",4,,DROP
	addi sp,sp,4
	NEXT

	# SWAP swaps the top two values on the stack.
	defcode "SWAP",4,,SWAP
	lw t0,4(sp)
	lw t1,0(sp)
	sw t1,4(sp)
	sw t0,0(sp)
	NEXT

	# DUP duplicatesi (t0 -- t0 t0) the top value on the stack and pushes it on the stack.
	defcode "DUP",3,,DUP
	lw t0,0(sp)
	addi sp,sp,-4
	sw t0,0(sp)
	NEXT

	# OVER (x t0 -- t0 x t0) gets the second element of the stack and pushes it on top.
	defcode "OVER",4,,OVER
	lw t0,4(sp)
	addi sp,sp,-4
	sw t0,0(sp)
	NEXT

	# ROT rotates thus ( t0 t1 t2 -- t2 t0 t1 ), where a was at top of stack.
	# Think positive angle anti-clockwise rotation.
	defcode "ROT",3,,ROT
	lw t2,8(sp)
	lw t1,4(sp)
	lw t0,0(sp)
	sw t1,8(sp)
	sw t0,4(sp)
	sw t2,0(sp)
	NEXT

	# -ROT rotates ( t0 t1 t2 -- t1 t2 t0).
	defcode "-ROT",4,,NROT
	lw t2,8(sp)
	lw t1,4(sp)
	lw t0,0(sp)
	sw t0,8(sp)
	sw t2,4(sp)
	sw t1,0(sp)
	NEXT

	# 2DROP drops top two elements of the stack
	defcode "2DROP",5,,TWODROP
	addi sp,sp,8
	NEXT

	# 2DUP duplicates (t0 t1 -- t0 t1 t0 t1) top two elements of the stack
	defcode "2DUP",4,,TWODUP
	lw t1,4(sp)
	lw t0,0(sp)
	sw t1,-4(sp)
	sw t0,-8(sp)
	addi sp,sp,-8
	NEXT

	# 2SWAP swaps the top two pairs of elements of stack ( t0 t1 a0 a1 -- a0 a1 t0 t1 ).
	lw a1,12(sp)
	lw a0,8(sp)
	lw t1,4(sp)
	lw t0,0(sp)
	sw t1,12(sp)
	sw t0,8(sp)
	sw a1,4(sp)
	sw a0,0(sp)
	NEXT

	# ?DUP duplicates top of stack if non-zero ( Z -- Z ), ( NZ -- NZ NZ).
	defcode "?DUP",4,,QDUP
	lw t0,0(sp)
	beqz t0, .qdup_end
	addi sp,sp,-4
	sw t0,0(sp)
.qdup_end:
	NEXT

	# 1+ increments top of stack (t0 -- t0+1)
	defcode "1+",2,,INCR
	lw t0,0(sp)
	addi t0,t0,1
	sw t0,0(sp)
	NEXT

	# 1- decrements top of stack ( t0 -- t0-1 ).
	defcode "1-",2,,DECR
	lw t0,0(sp)
	addi t0,t0,-1
	sw t0,0(sp)
	NEXT

	# 4+ adds 4 to top of stack ( t0 -- t0+4 ).
	defcode "4+",2,,INCR4
	lw t0,0(sp)
	addi t0,t0,4
	sw t0,0(sp)
	NEXT

	# 4- subtracts 4 from top of stack ( t0 -- t0-4 ).
	defcode "4-",2,,DECR4
	lw t0,0(sp)
	addi t0,t0,-4
	sw t0,0(sp)
	NEXT

	# + gets top of stack and adds it to the next word on stack ( t0 t1 -- t0+t1 ).
	defword "+",1,,ADD
	lw t1,4(sp)
	lw t0,0(sp)
	addi sp,sp,4
	add t0,t0,t1
	sw t0,0(sp)
	NEXT

	# - gets top of stack and subtracts it from the next word on stack ( t0 t1 -- t1-t0 ).
	defword "-",1,,SUB
	lw t1,4(sp)
	lw t0,0(sp)
	addi sp,sp,4
	sub t0,t1,t0
	sw t0,0(sp)
	NEXT

	# * ( a0 a1 -- a1*a0 )
	defword "*",1,,MUL
	lw a1,4(sp)
	lw a0,0(sp)
	add a2,zero,a0
	addi a0,zero,0
1:
	andi a3,a1,1
	beq a3,zero, 2f
	add a0,a0,a2
2:
	srli a1,a1,1
	slli a2,a2,1
	bne a1,zero, 1b

	addi sp,sp,4
	sw a0,0(sp)
	NEXT

	# /MOD unsigned divide and mod ( a0 a1 -- a0/a1 a0%a1 )
	defword "/MOD",4,,DIVMOD
	lw a1,4(sp)
	lw a0,0(sp)

	add a2,zero,a1
	add a1,zero,a0
	addi a0,zero,-1
	beq a2,zero,5f
	addi a3,zero,1
	bgeu a2,a1,2f
1:
	bge zero,a2,2f
	slli a2,a2,1
	slli a3,a3,1
	bltu a2,a1,1b
2:
	addi a0,zero,0
3:
	bltu a1,a2,4f
	sub a1,a1,a2
	or a0,a0,a3
4:
	srli a3,a3,1
	srli a2,a2,1
	bne a3,zero,3b
5:
	sw a1,4(sp)
	sw a0,0(sp)
	NEXT

/*
	Lots of comparison operations like =, <, >, etc..

	ANS FORTH says that the comparison words should return all (binary) 1's for
	TRUE and all 0's for FALSE.  However this is a bit of a strange convention
	so this FORTH breaks it and returns the more normal (for C programmers ...)
	1 meaning TRUE and 0 meaning FALSE.
*/

	# = ( a a -- 1 ) , ( a b  -- 0 )
	defcode "=",1,,EQU
	lw a1,4(sp)
	lw a0,0(sp)
	addi sp,sp,4
	beq a0,a1, 1f
	li a0,0
	j 2f
1:
	li a0,1
2:	
	sw a0,0(sp)
	NEXT

	# <> ( a a -- 0 ), ( a b -- 1 )
	defcode "<>",2,,NEQU
	lw a1,4(sp)
	lw a0,0(sp)
	addi sp,sp,4
	bne a0,a1,1f
	li a0,0
	j 2f
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# < ( 2 3 -- 1 ), ( 2 2  -- 0 )
	defcode "<",1,,LT
	lw a1,4(sp)
	lw a0,0(sp)
	addi sp,sp,4
	blt a0,a1,1f
	li a0,0
	j 2f
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# > (3 2 -- 1 ), ( 2 2 -- 0 )
	defcode ">",1,,GT
	lw a1,4(sp)
	lw a0,0(sp)
	addi sp,sp,4
	bgt a0,a1,1f
	li a0,0
	j 2f
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# >= ( 3 3 -- 1 ), ( 2 3 -- 0 )
	defcode ">=",2,,GE
	lw a1,4(sp)
	lw a0,0(sp)
	addi sp,sp,4
	bge a0,a1,1f
	li a0,0
	j 2f
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# 0= ( z -- 1 ), ( nz -- 0 )
	defcode "0=",2,,ZEQU
	lw a0,0(sp)
	beqz a0,1f
	li a0,0
	j 2f
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# 0<> ( nz -- 1 ), ( z -- 0 )
	defcode "0<>",3,,ZNEQU
	lw a0,0(sp)
	bnez a0,1f
	li a0,0
	j 2f
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# 0< ( neg -- 1 ), ( z -- 0 )
	defcode "0<",2,,ZLT
	lw a0,0(sp)
	blt a0,zero,1f
	li a0,0
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# 0> ( pos -- 1 ), ( z -- 0 )
	defcode "0>",2,,ZGT
	lw a0,0(sp)
	bgt a0,zero,1f
	li a0,0
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# 0<= ( neg|z -- 1 ), ( >0 -- 0 )
	defcode "0<=",3,,ZLE
	lw a0,0(sp)
	ble a0,zero,1f
	li a0,0
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# 0>= ( pos|z -- 1 ), ( neg -- 0 )
	defcode "0>=",3,,ZGE
	lw a0,0(sp)
	bge a0,zero,1f
	li a0,0
1:
	li a0,1
2:
	sw a0,0(sp)
	NEXT

	# AND ( a0 a1 -- a0 & a1 )
	defcode "AND",3,,AND
	lw a1,4(sp)
	lw a0,0(sp)
	addi sp,sp,4
	and a0,a0,a1
	sw a0,0(sp)
	NEXT

	# OR ( a0 a1 -- a0 | a1 )
	defcode "OR",2,,OR
	lw a1,4(sp)
	lw a0,0(sp)
	addi sp,sp,4
	or a0,a0,a1
	sw a0,0(sp)
	NEXT

	# XOR ( a0 a1 -- a0 ^ a1 )
	defcode "XOR",3,,XOR
	lw a1,4(sp)
	lw a0,0(sp)
	addi sp,sp,4
	xor a0,a0,a1
	sw a0,0(sp)
	NEXT

	# INVERT ( a0 -- ~a0 )
	defcode "INVERT",6,,INVERT
	lw a0,0(sp)
	not a0,a0
	sw a0,0(sp)
	NEXT

/*
	RETURNING FROM FORTH WORDS ----------------------------------------------------------------------

	Time to talk about what happens when we EXIT a function.  In this diagram QUADRUPLE has called
	DOUBLE, and DOUBLE is about to exit (look at where %esi is pointing):

		QUADRUPLE
		+------------------+
		| codeword         |
		+------------------+		   DOUBLE
		| addr of DOUBLE  ---------------> +------------------+
		+------------------+               | codeword         |
		| addr of DOUBLE   |		   +------------------+
		+------------------+	   	   | addr of DUP      |
		| addr of EXIT	   |		   +------------------+
		+------------------+	   	   | addr of +        |
						   +------------------+
					   %esi -> | addr of EXIT     |
						   +------------------+

	What happens when the + function does NEXT?  Well, the following code is executed.
*/

	defcode "EXIT",4,,EXIT
	POPRSP tp  // %esi in jonesforth x86 is tp in my RISC-V implementation
	NEXT
