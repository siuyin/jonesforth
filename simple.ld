ENTRY( _start )

MEMORY
{
	FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 16K
	RAM (xrw)  : ORIGIN = 0x20000000, LENGTH = 2K
}

SECTIONS
{

    .text :
    {
      . = ALIGN(4);
      *(.text)
      *(.rodata)
      . = ALIGN(4);
    } >FLASH AT>FLASH 

    .data :
    {
      . = ALIGN(4);
      *(.data .data.*)
      . = ALIGN(4);
      PROVIDE( _edata = .);
    } >RAM AT>FLASH

	PROVIDE( end = . );

	PROVIDE( _eusrstack = ORIGIN(RAM) + LENGTH(RAM) - 128);	
	PROVIDE( return_stack_top = ORIGIN(RAM) + LENGTH(RAM));	
}



