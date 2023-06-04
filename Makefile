all:
	riscv64-unknown-elf-gcc jonesforth.S -o jonesforth.elf -nostdlib -march=rv32ec -mabi=ilp32e -g -T simple.ld

.PHONY: all
