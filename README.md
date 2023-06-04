# JonesForth port to RISC-V ch32v003
This is my port of the public domain jonesforth (https://github.com/nornagon/jonesforth)
to target the RISC-V ch32v003.

Jonesforth initially targetted i386.

## Building
On WSL or Debian based OSes apt-get install build-essential libnewlib-dev gcc-riscv64-unknown-elf libusb-1.0-0-dev libudev-dev

```
make		// builds and flashes the part. Requires minichlink. See https://github.com/cnlohr/ch32v003fun
make build	// builds jonesforth.elf, .lst, bin and other file useful for debugging.
```
