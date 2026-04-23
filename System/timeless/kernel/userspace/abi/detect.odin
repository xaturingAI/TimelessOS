package abi

import "core:mem"

Binary_Type :: enum {
	UNKNOWN,
	ELF_32,
	ELF_64,
	PE_32,
	PE_64,
	MACHO_32,
	MACHO_64,
	FREEBSD_ELF,
}

OS_Type :: enum {
	UNKNOWN,
	LINUX,
	WINDOWS,
	MACOS,
	FREEBSD,
}

Architecture :: enum {
	UNKNOWN,
	X86,
	X86_64,
	ARM,
	ARM64,
}

Binary_Info :: struct {
	binary_type:   Binary_Type,
	os_type:       OS_Type,
	arch:         Architecture,
	entry_point:   u64,
	base_address:  u64,
	program_header_offset: u64,
	section_offset:      u64,
	section_count:      u32,
	program_header_count: u32,
	is_dynamically_linked: bool,
	 interpreter:        string,
	 library_paths:      []string,
}

MAGIC_ELF :: 0x7F454C46
MAGIC_PE   :: 'M' << 24 | 'Z' << 16 | 0x90 << 8 | 0x00
MAGIC_MACHO :: 0xFEEDFACE
MAGIC_MACHO64 :: 0xFEEDFACF

detect :: proc(data: []byte) -> Binary_Info {
	if len(data) < 64 {
		return Binary_Info{}
	}

	elf_magic := mem.u32_from_le(data[0:4])
	pe_magic := mem.u32_from_le(data[0:4])

	if elf_magic == MAGIC_ELF {
		return detect_elf(data)
	}

	if data[0] == 'M' && data[1] == 'Z' {
		return detect_pe(data)
	}

	if mem.u32_from_be(data[0:4]) == MAGIC_MACHO || mem.u32_from_be(data[0:4]) == MAGIC_MACHO64 {
		return detect_macho(data)
	}

	return Binary_Info{}
}

detect_elf :: proc(data: []byte) -> Binary_Info {
	if len(data) < 64 {
		return Binary_Info{}
	}

	elf_class := data[4]
	 endian := data[5]
	 version := data[6]

	if elf_class == 0 {
		return Binary_Info{binary_type: .ELF_32}
	}
	if elf_class == 2 {
		return Binary_Info{binary_type: .ELF_64}
	}

	return Binary_Info{}
}

detect_pe :: proc(data: []byte) -> Binary_Info {
	if len(data) < 0x80 {
		return Binary_Info{}
	}

	nt_headers_offset := mem.u32_from_le(data[0x3C:0x40])
	if uint(nt_headers_offset) + 24 > uint(len(data)) {
		return Binary_Info{}
	}

	machine := mem.u16_from_le(data[nt_headers_offset:nt_headers_offset+2])
	optional_header_size := mem.u16_from_le(data[nt_headers_offset+16:nt_headers_offset+18])

	if machine == 0x014C {
		return Binary_Info{
			binary_type: .PE_32,
			os_type:     .WINDOWS,
			arch:       .X86,
		}
	}
	if machine == 0x8664 {
		return Binary_Info{
			binary_type: .PE_64,
			os_type:     .WINDOWS,
			arch:       .X86_64,
		}
	}

	return Binary_Info{}
}

detect_macho :: proc(data: []byte) -> Binary_Info {
	if len(data) < 32 {
		return Binary_Info{}
	}

	magic := mem.u32_from_be(data[0:4])
	cpu_type := mem.u32_from_le(data[12:16])

	result := Binary_Info{os_type: .MACOS}

	if magic == MAGIC_MACHO {
		result.binary_type = .MACHO_32
	} else if magic == MAGIC_MACHO64 {
		result.binary_type = .MACHO_64
	}

	switch cpu_type {
	case 7:
		result.arch = .X86
	case 0x01000007:
		result.arch = .X86_64
	case 12:
		result.arch = .ARM
	case 0x0100000C:
		result.arch = .ARM64
	}

	return result
}