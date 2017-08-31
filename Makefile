CC       := /opt/cross-x86_64/bin/x86_64-elf-gcc
AR       := /opt/cross-x86_64/bin/x86_64-elf-ar
LD       := /opt/cross-x86_64/bin/x86_64-elf-ld

SYSROOT    := $(PWD)/sysroot
INCLUDEDIR := $(SYSROOT)/usr/include
LIBDIR     := $(SYSROOT)/usr/lib
BOOTDIR    := $(SYSROOT)/boot

WARNINGS := -Wall -Wextra -Wpedantic -Werror -Wshadow -Wno-error=unused-function
CFLAGS   := -c -pipe -ggdb3 -std=gnu11 -O0 $(WARNINGS) -fdiagnostics-color=always \
            -ffreestanding -Ikernel/include -Iklibc/include \
            --sysroot=$(SYSROOT) -DTREEOS_CMDLINE_DEFINES \
			-DTREEOS_I386 -DTREEOS_DEBUG
ASFLAGS  := $(CFLAGS) -DTREEOS_EXPORT_ASM
LDFLAGS  := -ffreestanding -fno-common -nostdlib \
            -T kernel/arch/i386/linker.ld --sysroot=$(SYSROOT) -lklibc

KERNEL_CSOURCES := $(shell find kernel -type f -name "*.c" -print)
KERNEL_ASOURCES := $(shell find kernel -iname "crt?.S" -prune -o -type f -name "*.S" -print)
KLIBC_CSOURCES  := $(shell find klibc -type f -name "*.c" -print)
KLIBC_ASOURCES  := $(shell find klibc -type f -name "*.S" -print)
ALL_CSOURCES    := $(KERNEL_CSOURCES) $(KLIBC_CSOURCES)
ALL_ASOURCES    := $(KERNEL_ASOURCES) $(KLIBC_ASOURCES)

CRTI_OBJ     := kernel/arch/i386/crti.o
CRTBEGIN_OBJ := $(shell $(CC) $(CFLAGS) $(LDFLAGS) -print-file-name=crtbegin.o)
CRTEND_OBJ   := $(shell $(CC) $(CFLAGS) $(LDFLAGS) -print-file-name=crtend.o)
CRTN_OBJ     := kernel/arch/i386/crtn.o

KERNEL_OBJECTS := $(patsubst %.c, %.o, $(KERNEL_CSOURCES)) \
                  $(patsubst %.S, %.o, $(KERNEL_ASOURCES))
KLIBC_OBJECTS  := $(patsubst %.c, %.o, $(KLIBC_CSOURCES)) \
                  $(patsubst %.S, %.o, $(KLIBC_ASOURCES))
DEPFILES       := $(patsubst %.c, %.d, $(ALL_CSOURCES)) \
				  $(patsubst %.S, %.d, $(ALL_ASOURCES)) \
				  $(patsubst %.o, %.d, $(CRTI_OBJ)) \
				  $(patsubst %.o, %.d, $(CRTN_OBJ))

KLIBC_TARGET   := $(LIBDIR)/libklibc.a
KERNEL_TARGET  := $(BOOTDIR)/kernel
ISO_TARGET     := $(PWD)/treeos.iso
GRUB_CFG_FILE  := $(BOOTDIR)/grub/grub.cfg

.PHONY: dumpvars all kernel libs klibc distclean clean clean-kernel \
        clean-libs clean-iso install install-headers install-libs \
		install-kernel install-grub iso

all: libs kernel

libs: klibc

klibc: $(KLIBC_TARGET)


kernel: libs $(KERNEL_TARGET)

$(KLIBC_TARGET): $(KLIBC_OBJECTS)
	@mkdir -p $(LIBDIR)
	@echo ">> Linking library $@"
	@$(AR) rcs $@ $(KLIBC_OBJECTS)

$(KERNEL_TARGET): $(KERNEL_OBJECTS) $(CRTI_OBJ) $(CRTN_OBJ)
	@mkdir -p $(BOOTDIR)
	@echo ">> Linking kernel image $(KERNEL_TARGET)"
	@$(CC) -o $(KERNEL_TARGET) $(CRTI_OBJ) $(CRTBEGIN_OBJ) $(KERNEL_OBJECTS) $(CRTEND_OBJ) $(CRTN_OBJ) $(LDFLAGS)

distclean: clean clean-iso

clean: clean-kernel clean-libs clean-deps

clean-kernel:
	rm -f $(KERNEL_TARGET) $(KERNEL_OBJECTS) $(CRTI_OBJ) $(CRTN_OBJ)
	@find kernel -type f -iname "*~" -exec rm -f {} \;

clean-libs:
	rm -f $(KLIBC_TARGET) $(KLIBC_OBJECTS)
	@find klibc -type f -iname "*~" -exec rm -f {} \;

clean-deps:
	rm -f $(DEPFILES)

clean-iso:
	rm -f $(ISO_TARGET)

-include $(DEPFILES)

%.o: %.c
	@echo "(CC) $<"
	@$(CC) -o $@ $(CFLAGS) -MMD -MP $<

%.o: %.S
	@echo "(AS) $<"
	@$(CC) -o $@ $(ASFLAGS) -MMD -MP $<

install-grub:
	@echo ">> Installing GRUB"
	@mkdir -p $(BOOTDIR)/grub
	@echo "set default=0" > $(GRUB_CFG_FILE)
	@echo "set timeout=1" >> $(GRUB_CFG_FILE)
	@echo "menuentry \"treeos\" {" >> $(GRUB_CFG_FILE)
	@echo "    multiboot /boot/kernel" >> $(GRUB_CFG_FILE)
	@echo "    module    /boot/init --init" >> $(GRUB_CFG_FILE)
	@echo "}" >> $(GRUB_CFG_FILE)

$(ISO_TARGET): kernel install-grub
	@echo ">> Creating ISO"
	@grub-mkrescue -d /usr/lib/grub/i386-pc -o $(ISO_TARGET) $(SYSROOT)

iso: $(ISO_TARGET)

