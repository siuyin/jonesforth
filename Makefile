all:
	riscv64-unknown-elf-gcc -march=rv32ec -mabi=ilp32e -static -nostdlib -g -T simple.ld -o jonesforth.elf jonesforth.S

.PHONY: all
