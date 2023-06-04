PREFIX?=riscv64-unknown-elf
MINICHLINK?=/home/siuyin/ch32v003fun/minichlink

CFLAGS+= \
	-g -Os -flto -ffunction-sections \
	-static-libgcc \
	-march=rv32ec \
	-mabi=ilp32e \
	-nostdlib \
	-I. -Wall $(EXTRA_CFLAGS)

LINKER_SCRIPT?=simple.ld
LDFLAGS+=-T $(LINKER_SCRIPT) -Wl,--gc-sections -Lmisc -lgcc

TARGET=jonesforth
TARGET_EXT?=S

WRITE_SECTION?=flash

all:
	make flash

$(TARGET).elf : $(TARGET).$(TARGET_EXT)
	$(PREFIX)-gcc -o $@ $^ $(CFLAGS) $(LDFLAGS)

$(TARGET).bin : $(TARGET).elf
	$(PREFIX)-size $^
	$(PREFIX)-objdump -S $^ > $(TARGET).lst
	$(PREFIX)-objdump -t $^ > $(TARGET).map
	$(PREFIX)-objcopy -O binary $< $(TARGET).bin
	$(PREFIX)-objcopy -O ihex $< $(TARGET).hex

FLASH_COMMAND?=$(MINICHLINK)/minichlink -w $< $(WRITE_SECTION) -b

flash : $(TARGET).bin
	make -C $(MINICHLINK) all
	$(FLASH_COMMAND)

clean :
	rm -rf $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).lst $(TARGET).map $(TARGET).hex || true

build : $(TARGET).bin

