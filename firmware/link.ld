ENTRY(_start)
MEMORY { OCR (rwx) : ORIGIN = 0xF9000000, LENGTH = 32K }
SECTIONS {
 .text : { *(.text.start) *(.text .text.*) *(.rodata .rodata.*) } > OCR
 .data : { *(.data .data.* .sdata .sdata.*) } > OCR
 .bss (NOLOAD) : { . = ALIGN(4); _bss_start = .; *(.bss .bss.* .sbss .sbss.*) *(COMMON) . = ALIGN(4); _bss_end = .; } > OCR
 _sp = ORIGIN(OCR) + LENGTH(OCR) - 16;
 ASSERT(_bss_end < _sp - 2048,"OCRAM leaves insufficient stack")
 /DISCARD/ : { *(.comment .note* .eh_frame*) }
}
