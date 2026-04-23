package nt

import "core:log"
import "core:mem"
import "core:strings"
import "core:slice"
import "core:unicode/utf16"

import vfs "filesystem/vfs"

// ============================================================
// NT Status codes  (fixed: had two entries sharing 0xC000000F,
// and STATUS_UNSUCCESSFUL had the wrong value 0xC000000C)
// ============================================================

NT_Status :: distinct u32

STATUS_SUCCESS                  :: NT_Status(0x00000000)
STATUS_PENDING                  :: NT_Status(0x00000103)
STATUS_NO_MORE_FILES            :: NT_Status(0x80000006)
STATUS_END_OF_FILE              :: NT_Status(0xC0000011)  // fixed capitalisation from STATUS_end_OF_FILE
STATUS_NO_SUCH_FILE             :: NT_Status(0xC000000F)
STATUS_OBJECT_NAME_NOT_FOUND    :: NT_Status(0xC0000034)
STATUS_OBJECT_PATH_NOT_FOUND    :: NT_Status(0xC000003A)
STATUS_ACCESS_DENIED            :: NT_Status(0xC0000022)
STATUS_INVALID_HANDLE           :: NT_Status(0xC0000008)
STATUS_INVALID_PARAMETER        :: NT_Status(0xC000000D)  // fixed: was 0xC000000F (collision with NO_SUCH_FILE)
STATUS_NOT_IMPLEMENTED          :: NT_Status(0xC0000002)
STATUS_UNSUCCESSFUL             :: NT_Status(0xC0000001)  // fixed: was 0xC000000C
STATUS_NO_MEMORY                :: NT_Status(0xC0000017)
STATUS_SHARING_VIOLATION        :: NT_Status(0xC0000043)
STATUS_DELETE_PENDING           :: NT_Status(0xC0000056)
STATUS_FILE_IS_A_DIRECTORY      :: NT_Status(0xC00000BA)
STATUS_NOT_A_DIRECTORY          :: NT_Status(0xC0000103)
STATUS_BUFFER_TOO_SMALL         :: NT_Status(0xC0000023)
STATUS_INFO_LENGTH_MISMATCH     :: NT_Status(0xC0000004)

// ============================================================
// Access mask flags
// ============================================================

FILE_READ_DATA          :: u32(0x00000001)
FILE_WRITE_DATA         :: u32(0x00000002)
FILE_APPEND_DATA        :: u32(0x00000004)
FILE_READ_EA            :: u32(0x00000008)
FILE_WRITE_EA           :: u32(0x00000010)
FILE_READ_ATTRIBUTES    :: u32(0x00000080)
FILE_WRITE_ATTRIBUTES   :: u32(0x00000100)
FILE_DELETE             :: u32(0x00010000)  // fixed: was same value as FILE_READ_CONTROL
FILE_READ_CONTROL       :: u32(0x00020000)
GENERIC_READ            :: u32(0x80000000)
GENERIC_WRITE           :: u32(0x40000000)
GENERIC_EXECUTE         :: u32(0x20000000)
GENERIC_ALL             :: u32(0x10000000)

// Share mode
FILE_SHARE_READ         :: u32(0x00000001)
FILE_SHARE_WRITE        :: u32(0x00000002)
FILE_SHARE_DELETE       :: u32(0x00000004)

// Create disposition
FILE_SUPERSEDE          :: u32(0x00000000)
FILE_OPEN               :: u32(0x00000001)
FILE_CREATE             :: u32(0x00000002)
FILE_OPEN_IF            :: u32(0x00000003)
FILE_OVERWRITE          :: u32(0x00000004)
FILE_OVERWRITE_IF       :: u32(0x00000005)

// Create/open options  (removed duplicate FILE_NON_DIRECTORY_FILE and FILE_NO_COMPRESSION)
FILE_DIRECTORY_FILE             :: u32(0x00000001)
FILE_NON_DIRECTORY_FILE         :: u32(0x00000040)  // fixed: removed duplicate definition
FILE_SYNCHRONOUS_IO_NONALERT    :: u32(0x00000020)
FILE_SYNCHRONOUS_IO_ALERT       :: u32(0x00000010)
FILE_NO_INTERMEDIATE_BUFFERING  :: u32(0x00000008)
FILE_DELETE_ON_CLOSE            :: u32(0x00001000)
FILE_OPEN_BY_FILE_ID            :: u32(0x00002000)
FILE_OPEN_FOR_BACKUP_INTENT     :: u32(0x00004000)
FILE_NO_COMPRESSION             :: u32(0x00008000)  // fixed: removed duplicate definition

// ============================================================
// NT Object types  (handle table covers all kernel objects)
// ============================================================

Object_Type :: enum u8 {
	File,
	Directory,
	Section,
	Event,
	Mutant,       // NT mutex
	Semaphore,
	Key,          // registry key
	SymbolicLink,
	Process,
	Thread,
	Token,
	Port,         // ALPC port
}

// ============================================================
// NT Handle table entry
// One entry covers all object types — object_type tells you
// which union field is meaningful.
// ============================================================

NT_Handle :: struct {
	object_type:   Object_Type,
	access_mask:   u32,
	share_mode:    u32,
	// File-specific
	vfs_file:      ^vfs.VFS_FILE,
	// Generic name (for events, mutants, etc.)
	object_name:   string,
	// Reference count for shared handles
	ref_count:     int,
}

// ============================================================
// NT Wire structures  (UNICODE_STRING, OBJECT_ATTRIBUTES, etc.)
// These must be #packed and match the exact Windows ABI layout.
// ============================================================

// UNICODE_STRING
NT_Unicode_String :: struct #packed {
	length:          u16,   // byte length of Buffer (not char count)
	maximum_length:  u16,
	_pad:            u32,   // 8-byte alignment on x64
	buffer:          ^u16,  // UTF-16LE characters
}

// OBJECT_ATTRIBUTES
NT_Object_Attributes :: struct #packed {
	length:                       u32,
	root_directory:               u64,   // optional root handle
	object_name:                  ^NT_Unicode_String,
	attributes:                   u32,
	security_descriptor:          ^rawptr,
	security_quality_of_service:  ^rawptr,
}

// IO_STATUS_BLOCK
NT_IO_Status_Block :: struct #packed {
	status:       NT_Status,
	_pad:         u32,
	information:  u64,
}

// FILE_BASIC_INFORMATION  (used by NtQueryInformationFile)
NT_File_Basic_Info :: struct #packed {
	creation_time:    i64,
	last_access_time: i64,
	last_write_time:  i64,
	change_time:      i64,
	file_attributes:  u32,
	_pad:             u32,
}

// FILE_STANDARD_INFORMATION
NT_File_Standard_Info :: struct #packed {
	allocation_size: i64,
	end_of_file:     i64,
	number_of_links: u32,
	delete_pending:  bool,
	directory:       bool,
	_pad:            u16,
}

// FILE_INFORMATION_CLASS values we handle
File_Info_Class :: enum u32 {
	FileBasicInformation     = 4,
	FileStandardInformation  = 5,
	FileNameInformation      = 9,
	FilePositionInformation  = 14,
	FileEndOfFileInformation = 20,
}

// ============================================================
// Windows NT full filesystem hierarchy -> TimelessOS path map
//
// This is the table that was MISSING — the old nt_translate_path
// was routing everything to /strata/linux which is completely wrong.
//
// NT Object Manager namespace prefixes are handled first,
// then drive-letter paths, then well-known directory paths.
//
// Internal representation: we store Windows drive paths as
// /C/, /D/ etc. (forward slashes) to avoid backslash escaping
// in the kernel. The wire-level conversion (C:\ <-> /C/) happens
// in nt_unicode_to_internal before this table is consulted.
// ============================================================

NT_Path_Entry :: struct {
	nt_prefix:       string,   // NT/Win32 path prefix (internal /X/ form)
	timeless_path:   string,   // TimelessOS canonical target
	strip_prefix:    bool,     // if true, append the remainder after prefix
}

// Order matters — more specific prefixes must come before shorter ones.
NT_PATH_TABLE :: []NT_Path_Entry {
	// ---- NT Object Manager namespace ----
	// \??\  and  \DosDevices\  both map to drive roots
	{ nt_prefix = "/??/C/",         timeless_path = "/",                       strip_prefix = false },
	{ nt_prefix = "/DosDevices/C/", timeless_path = "/",                       strip_prefix = false },

	// \Device\HarddiskVolume paths -> Mount points
	{ nt_prefix = "/Device/HarddiskVolume1", timeless_path = "/Mount/main-drive",  strip_prefix = true },
	{ nt_prefix = "/Device/HarddiskVolume2", timeless_path = "/Mount/boot-drive",  strip_prefix = true },
	{ nt_prefix = "/Device/CdRom0",          timeless_path = "/Mount/cdrom0",       strip_prefix = true },

	// \SystemRoot  -> Windows directory
	{ nt_prefix = "/SystemRoot",    timeless_path = "/Software/system-pkgs/nt/Windows", strip_prefix = true },

	// ---- C: drive well-known directories (most specific first) ----

	// User profile directories
	{ nt_prefix = "/C/Users",       timeless_path = "/User/live-users",        strip_prefix = true },

	// Windows OS directory and subdirs
	{ nt_prefix = "/C/Windows/System32",     timeless_path = "/Library/shared-libs/nt/System32",   strip_prefix = true },
	{ nt_prefix = "/C/Windows/SysWOW64",     timeless_path = "/Library/shared-libs/nt/SysWOW64",   strip_prefix = true },
	{ nt_prefix = "/C/Windows/Temp",         timeless_path = "/Library/tmp",                        strip_prefix = true },
	{ nt_prefix = "/C/Windows/Fonts",        timeless_path = "/Library/shared-libs/nt/Fonts",       strip_prefix = true },
	{ nt_prefix = "/C/Windows/inf",          timeless_path = "/Library/shared-libs/nt/inf",         strip_prefix = true },
	{ nt_prefix = "/C/Windows",              timeless_path = "/Software/system-pkgs/nt/Windows",    strip_prefix = true },

	// Program directories
	{ nt_prefix = "/C/Program Files (x86)", timeless_path = "/Software/user-pkgs/x86",   strip_prefix = true },
	{ nt_prefix = "/C/Program Files",       timeless_path = "/Software/user-pkgs",        strip_prefix = true },
	{ nt_prefix = "/C/ProgramData",         timeless_path = "/Settings/System/nt",        strip_prefix = true },

	// Temp and misc
	{ nt_prefix = "/C/Temp",  timeless_path = "/Library/tmp",  strip_prefix = true },
	{ nt_prefix = "/C/tmp",   timeless_path = "/Library/tmp",  strip_prefix = true },

	// C: root -> TimelessOS Software/system-pkgs/nt
	// (anything not matched above that's on C: goes here)
	{ nt_prefix = "/C/",  timeless_path = "/Software/system-pkgs/nt/",  strip_prefix = true },
	{ nt_prefix = "/C",   timeless_path = "/Software/system-pkgs/nt",   strip_prefix = false },

	// ---- Other drive letters -> Mount subdirectories ----
	{ nt_prefix = "/D/",  timeless_path = "/Mount/drive-d/",  strip_prefix = true },
	{ nt_prefix = "/E/",  timeless_path = "/Mount/drive-e/",  strip_prefix = true },
	{ nt_prefix = "/F/",  timeless_path = "/Mount/drive-f/",  strip_prefix = true },
}

// ============================================================
// Global state  (handle table + allocator)
// ============================================================

@(private) _nt_handle_table: map[u64]^NT_Handle
@(private) _next_handle:     u64 = 0x1000  // NT handles start above 0x1000

// ============================================================
// Init
// ============================================================

init_nt_syscalls :: proc() {
	log.info("NT VFS: Initializing NT syscall / VFS integration...")
	_nt_handle_table = make(map[u64]^NT_Handle)
	_next_handle = 0x1000
	log.info("NT VFS: Ready")
}

// ============================================================
// Syscall dispatch table
// NT syscall numbers are NOT stable across Windows versions —
// these match Windows 10 2004+ / ReactOS approximation.
// Wine's ntdll has the definitive table.
// ============================================================

nt_syscall_dispatch :: proc(num: u64, args: []u64) -> (u64, u64) {
	if len(args) < 8 {
		return 0, u64(STATUS_INVALID_PARAMETER)
	}

	switch num {
	case 0x00F: return sys_nt_close(args[0])
	case 0x055: return sys_nt_create_file(args[0], u32(args[1]), args[2], args[3], args[4], u32(args[5]), u32(args[6]), u32(args[7]))
	case 0x006: return sys_nt_read_file(args[0], args[1], u32(args[2]), args[3], args[4])
	case 0x008: return sys_nt_write_file(args[0], args[1], u32(args[2]), args[3], args[4])
	case 0x033: return sys_nt_open_file(args[0], u32(args[1]), args[2], args[3], u32(args[4]))
	case 0x013: return sys_nt_delete_file(args[0])
	case 0x04D: return sys_nt_create_process(args[0], u32(args[1]), args[2], args[3])
	case 0x019: return sys_nt_create_section(args[0], u32(args[1]), args[2], u32(args[3]), u32(args[4]), args[5])
	case 0x028: return sys_nt_map_view_of_section(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
	case 0x02A: return sys_nt_unmap_view_of_section(args[0], args[1])
	case 0x015: return sys_nt_allocate_virtual_memory(args[0], args[1], args[2], args[3], u32(args[4]), u32(args[5]))
	case 0x01E: return sys_nt_free_virtual_memory(args[0], args[1], args[2], u32(args[3]))
	case 0x050: return sys_nt_protect_virtual_memory(args[0], args[1], args[2], u32(args[3]), args[4])
	case 0x023: return sys_nt_query_virtual_memory(args[0], args[1], u32(args[2]), args[3], args[4])
	case 0x04E: return sys_nt_create_thread(args[0], u32(args[1]), args[2], args[3], args[4], args[5])
	case 0x004: return sys_nt_wait_for_single_object(args[0], bool(args[1] != 0), args[2])
	case 0x048: return sys_nt_create_event(args[0], u32(args[1]), args[2], bool(args[3] != 0), bool(args[4] != 0))
	case 0x026: return sys_nt_set_event(args[0])
	case 0x035: return sys_nt_reset_event(args[0])
	case 0x011: return sys_nt_query_information_file(args[0], args[1], args[2], u32(args[3]), u32(args[4]))
	case 0x024: return sys_nt_query_directory_file(args[0], args[1], args[2], u32(args[3]), bool(args[4] != 0), args[5], bool(args[6] != 0))
	}

	log.warnf("NT VFS: unhandled syscall 0x%X", num)
	return 0, u64(STATUS_NOT_IMPLEMENTED)
}

// ============================================================
// NtClose
// ============================================================

sys_nt_close :: proc(handle: u64) -> (u64, u64) {
	h := _handle_get(handle)
	if h == nil {
		return 0, u64(STATUS_INVALID_HANDLE)
	}

	h.ref_count -= 1
	if h.ref_count <= 0 {
		if h.object_type == .File && h.vfs_file != nil {
			vfs.vfs_close(h.vfs_file)
		}
		free(h)
		delete_key(&_nt_handle_table, handle)
	}

	return 0, u64(STATUS_SUCCESS)
}

// ============================================================
// NtCreateFile
// ============================================================

sys_nt_create_file :: proc(
	out_handle:         u64,    // pointer to receive the handle
	desired_access:     u32,
	object_attributes:  u64,   // pointer to OBJECT_ATTRIBUTES
	io_status_block:    u64,   // pointer to IO_STATUS_BLOCK
	allocation_size:    u64,
	file_attributes:    u32,
	share_access:       u32,
	create_disposition: u32,
	create_options:     u32,
) -> (u64, u64) {

	obj_attr := cast(^NT_Object_Attributes)(uintptr(object_attributes))
	if obj_attr == nil {
		return 0, u64(STATUS_INVALID_PARAMETER)
	}

	// Convert NT UNICODE_STRING path to TimelessOS canonical path
	raw_path := nt_unicode_to_internal(obj_attr.object_name)
	if raw_path == "" {
		return 0, u64(STATUS_OBJECT_NAME_NOT_FOUND)
	}

	timeless_path := nt_translate_path(raw_path)
	log.debugf("NT NtCreateFile: '%v' -> '%v'", raw_path, timeless_path)

	vfs_flags := _disposition_to_vfs_flags(desired_access, create_disposition)

	vfs_file := vfs.vfs_open(timeless_path, vfs_flags, 0)
	if vfs_file == nil {
		return 0, u64(STATUS_NO_SUCH_FILE)
	}

	h := new(NT_Handle)      // fixed: was  mem Alloc(sizeof(NT_Handle))
	h^ = NT_Handle{
		object_type  = .File,
		access_mask  = desired_access,
		share_mode   = share_access,
		vfs_file     = vfs_file,
		ref_count    = 1,
	}

	handle := _alloc_handle(h)

	// Write handle back to caller's out_handle pointer
	if out_handle != 0 {
		out := cast(^u64)(uintptr(out_handle))
		out^ = handle
	}

	// Fill IO_STATUS_BLOCK
	_set_io_status(io_status_block, STATUS_SUCCESS, 0)

	log.debugf("NT NtCreateFile: handle=0x%X path='%v'", handle, timeless_path)
	return handle, u64(STATUS_SUCCESS)
}

// ============================================================
// NtOpenFile  (missing from original — used constantly by apps)
// ============================================================

sys_nt_open_file :: proc(
	out_handle:        u64,
	desired_access:    u32,
	object_attributes: u64,
	io_status_block:   u64,
	share_access:      u32,
) -> (u64, u64) {
	// NtOpenFile is NtCreateFile with FILE_OPEN disposition
	return sys_nt_create_file(
		out_handle, desired_access,
		object_attributes, io_status_block,
		0, 0, share_access, FILE_OPEN, 0,
	)
}

// ============================================================
// NtReadFile
// ============================================================

sys_nt_read_file :: proc(
	file_handle:     u64,
	user_buffer:     u64,
	length:          u32,
	byte_offset:     u64,   // optional file offset pointer
	io_status_block: u64,
) -> (u64, u64) {

	h := _handle_get(file_handle)
	if h == nil || h.vfs_file == nil {
		return 0, u64(STATUS_INVALID_HANDLE)
	}

	buf := make([]u8, length)     // allocate read buffer
	defer delete(buf)             // fixed: was mem.free(buf) — use delete() for slices

	n := vfs.vfs_read(h.vfs_file, buf)

	if n < 0 {
		return 0, u64(STATUS_UNSUCCESSFUL)
	}
	if n == 0 {
		_set_io_status(io_status_block, STATUS_END_OF_FILE, 0)
		return 0, u64(STATUS_END_OF_FILE)
	}

	if user_buffer != 0 {
		mem.copy(rawptr(uintptr(user_buffer)), raw_data(buf), n)
	}

	_set_io_status(io_status_block, STATUS_SUCCESS, u64(n))
	return u64(n), u64(STATUS_SUCCESS)
}

// ============================================================
// NtWriteFile
// ============================================================

sys_nt_write_file :: proc(
	file_handle:     u64,
	user_buffer:     u64,
	length:          u32,
	byte_offset:     u64,
	io_status_block: u64,
) -> (u64, u64) {

	h := _handle_get(file_handle)
	if h == nil || h.vfs_file == nil {
		return 0, u64(STATUS_INVALID_HANDLE)
	}

	// Build a slice over the user's buffer pointer
	// fixed: was mem.slice_buf() which doesn't exist
	buf := slice.from_ptr(cast(^u8)(uintptr(user_buffer)), int(length))

	n := vfs.vfs_write(h.vfs_file, buf)
	if n < 0 {
		return 0, u64(STATUS_UNSUCCESSFUL)
	}

	_set_io_status(io_status_block, STATUS_SUCCESS, u64(n))
	return u64(n), u64(STATUS_SUCCESS)
}

// ============================================================
// NtDeleteFile
// ============================================================

sys_nt_delete_file :: proc(object_attributes: u64) -> (u64, u64) {
	obj_attr := cast(^NT_Object_Attributes)(uintptr(object_attributes))
	if obj_attr == nil {
		return 0, u64(STATUS_INVALID_PARAMETER)
	}

	raw_path      := nt_unicode_to_internal(obj_attr.object_name)
	timeless_path := nt_translate_path(raw_path)

	ok := vfs.vfs_unlink(timeless_path)
	if !ok {
		return 0, u64(STATUS_NO_SUCH_FILE)
	}

	return 0, u64(STATUS_SUCCESS)
}

// ============================================================
// NtQueryInformationFile  (missing from original)
// Windows apps call this constantly for file size, attributes etc.
// ============================================================

sys_nt_query_information_file :: proc(
	file_handle:     u64,
	io_status_block: u64,
	file_info:       u64,   // output buffer pointer
	length:          u32,
	info_class:      u32,
) -> (u64, u64) {

	h := _handle_get(file_handle)
	if h == nil || h.vfs_file == nil {
		return 0, u64(STATUS_INVALID_HANDLE)
	}

	stat := vfs.vfs_stat_by_file(h.vfs_file)

	switch File_Info_Class(info_class) {
	case .FileBasicInformation:
		if length < size_of(NT_File_Basic_Info) {
			return 0, u64(STATUS_BUFFER_TOO_SMALL)
		}
		out := cast(^NT_File_Basic_Info)(uintptr(file_info))
		if stat != nil {
			out.file_attributes = _vfs_attr_to_nt(stat.mode)
		}
		_set_io_status(io_status_block, STATUS_SUCCESS, u64(size_of(NT_File_Basic_Info)))
		return 0, u64(STATUS_SUCCESS)

	case .FileStandardInformation:
		if length < size_of(NT_File_Standard_Info) {
			return 0, u64(STATUS_BUFFER_TOO_SMALL)
		}
		out := cast(^NT_File_Standard_Info)(uintptr(file_info))
		if stat != nil {
			out.end_of_file    = i64(stat.size)
			out.allocation_size = i64((stat.size + 4095) & ~u64(4095))
			out.directory      = stat.is_dir
		}
		_set_io_status(io_status_block, STATUS_SUCCESS, u64(size_of(NT_File_Standard_Info)))
		return 0, u64(STATUS_SUCCESS)

	case:
		return 0, u64(STATUS_NOT_IMPLEMENTED)
	}
}

// ============================================================
// NtQueryDirectoryFile  (missing from original)
// Used by every app that lists directory contents.
// ============================================================

sys_nt_query_directory_file :: proc(
	file_handle:       u64,
	event_handle:      u64,
	out_buffer:        u64,
	out_length:        u32,
	return_single:     bool,
	file_name_filter:  u64,   // optional UNICODE_STRING filter
	restart_scan:      bool,
) -> (u64, u64) {
	h := _handle_get(file_handle)
	if h == nil || h.vfs_file == nil {
		return 0, u64(STATUS_INVALID_HANDLE)
	}
	// Stub — real impl would call vfs.vfs_readdir and serialise
	// FILE_DIRECTORY_INFORMATION structs into out_buffer.
	return 0, u64(STATUS_NOT_IMPLEMENTED)
}

// ============================================================
// NtCreateProcess  (minimal stub)
// ============================================================

sys_nt_create_process :: proc(
	out_handle:         u64,
	desired_access:     u32,
	object_attributes:  u64,
	parent_handle:      u64,
) -> (u64, u64) {
	h := new(NT_Handle)    // fixed: was mem Alloc(sizeof(...))
	h^ = NT_Handle{ object_type = .Process, access_mask = desired_access, ref_count = 1 }
	handle := _alloc_handle(h)
	if out_handle != 0 {
		(cast(^u64)(uintptr(out_handle)))^ = handle
	}
	return handle, u64(STATUS_SUCCESS)
}

// ============================================================
// NtCreateSection / NtMapViewOfSection / NtUnmapViewOfSection
// ============================================================

sys_nt_create_section :: proc(
	out_handle:         u64,
	desired_access:     u32,
	object_attributes:  u64,
	page_protection:    u32,
	allocation_type:    u32,
	file_handle:        u64,
) -> (u64, u64) {
	h := new(NT_Handle)
	h^ = NT_Handle{ object_type = .Section, access_mask = desired_access, ref_count = 1 }
	handle := _alloc_handle(h)
	if out_handle != 0 {
		(cast(^u64)(uintptr(out_handle)))^ = handle
	}
	log.debugf("NT NtCreateSection: handle=0x%X", handle)
	return handle, u64(STATUS_SUCCESS)
}

sys_nt_map_view_of_section :: proc(
	section_handle: u64,
	process_handle: u64,
	base_address:   u64,
	zero_bits:      u64,
	commit_size:    u64,
	section_offset: u64,
	view_size:      u64,
) -> (u64, u64) {
	return base_address, u64(STATUS_SUCCESS)
}

sys_nt_unmap_view_of_section :: proc(process_handle: u64, base_address: u64) -> (u64, u64) {
	return 0, u64(STATUS_SUCCESS)
}

// ============================================================
// Virtual memory
// ============================================================

sys_nt_allocate_virtual_memory :: proc(
	process_handle:  u64,
	base_address:    u64,
	zero_bits:       u64,
	region_size:     u64,
	allocation_type: u32,
	protect:         u32,
) -> (u64, u64) {                       // fixed: was 5 params, now 6 to match dispatch
	size := region_size if region_size != 0 else 0x1000

	ptr, err := mem.alloc(int(size))
	if err != .None || ptr == nil {
		return 0, u64(STATUS_NO_MEMORY)
	}

	if base_address != 0 {
		(cast(^u64)(uintptr(base_address)))^ = u64(uintptr(ptr))
	}
	return u64(uintptr(ptr)), u64(STATUS_SUCCESS)
}

sys_nt_free_virtual_memory :: proc(
	process_handle: u64,
	base_address:   u64,
	region_size:    u64,
	free_type:      u32,
) -> (u64, u64) {
	if base_address != 0 {
		free(rawptr(uintptr(base_address)))
	}
	return 0, u64(STATUS_SUCCESS)
}

sys_nt_protect_virtual_memory :: proc(
	process_handle: u64,
	base_address:   u64,
	region_size:    u64,
	new_protect:    u32,
	old_protect:    u64,
) -> (u64, u64) {
	return 0, u64(STATUS_SUCCESS)
}

sys_nt_query_virtual_memory :: proc(
	process_handle: u64,
	base_address:   u64,
	info_class:     u32,
	memory_info:    u64,
	info_length:    u64,
) -> (u64, u64) {
	return 0, u64(STATUS_SUCCESS)
}

// ============================================================
// Thread + synchronisation
// ============================================================

sys_nt_create_thread :: proc(
	out_handle:        u64,
	desired_access:    u32,
	object_attributes: u64,
	process_handle:    u64,
	start_address:     u64,
	stack_size:        u64,
) -> (u64, u64) {
	h := new(NT_Handle)   // fixed: was mem Alloc(sizeof(...))
	h^ = NT_Handle{ object_type = .Thread, access_mask = desired_access, ref_count = 1 }
	handle := _alloc_handle(h)
	if out_handle != 0 {
		(cast(^u64)(uintptr(out_handle)))^ = handle
	}
	log.debugf("NT NtCreateThread: handle=0x%X start=0x%X", handle, start_address)
	return handle, u64(STATUS_SUCCESS)
}

sys_nt_wait_for_single_object :: proc(
	object_handle: u64,
	alertable:     bool,
	timeout:       u64,
) -> (u64, u64) {
	return 0, u64(STATUS_SUCCESS)
}

sys_nt_create_event :: proc(
	out_handle:        u64,
	desired_access:    u32,
	object_attributes: u64,
	manual_reset:      bool,
	initial_state:     bool,
) -> (u64, u64) {
	h := new(NT_Handle)   // fixed: was mem Alloc(sizeof(...))
	h^ = NT_Handle{ object_type = .Event, access_mask = desired_access, ref_count = 1 }
	handle := _alloc_handle(h)
	if out_handle != 0 {
		(cast(^u64)(uintptr(out_handle)))^ = handle
	}
	return handle, u64(STATUS_SUCCESS)
}

sys_nt_set_event :: proc(event_handle: u64) -> (u64, u64) {
	return 0, u64(STATUS_SUCCESS)
}

sys_nt_reset_event :: proc(event_handle: u64) -> (u64, u64) {
	return 0, u64(STATUS_SUCCESS)
}

// ============================================================
// PATH TRANSLATION  —  NT / Win32 -> TimelessOS
//
// Step 1: nt_unicode_to_internal
//   Converts UNICODE_STRING (UTF-16LE) to an internal ASCII-safe
//   path with forward slashes and drive-letter prefix:
//     "C:\Users\keres\doc.txt"  ->  "/C/Users/keres/doc.txt"
//     "\??\C:\Windows"          ->  "/??/C/Windows"
//
// Step 2: nt_translate_path
//   Walks NT_PATH_TABLE to map the internal path to a
//   TimelessOS canonical path:
//     "/C/Users/keres/doc.txt"  ->  "/User/live-users/keres/doc.txt"
//     "/C/Windows/System32"     ->  "/Library/shared-libs/nt/System32"
// ============================================================

// Convert a NT UNICODE_STRING pointer to our internal path form.
// Replaces backslashes with forward slashes and converts drive
// letter prefix:  "C:\" -> "/C/"
nt_unicode_to_internal :: proc(uni: ^NT_Unicode_String) -> string {
	if uni == nil || uni.buffer == nil || uni.length == 0 {
		return ""
	}

	// Length is in bytes; divide by 2 for UTF-16 code unit count
	char_count := int(uni.length) / 2
	utf16_slice := slice.from_ptr(uni.buffer, char_count)

	// Convert UTF-16LE -> UTF-8
	utf8_buf := make([]u8, char_count * 4)  // worst-case UTF-8 size
	utf8_len := utf16.decode_to_utf8(utf8_buf, utf16_slice)
	raw := string(utf8_buf[:utf8_len])

	// Replace all backslashes with forward slashes
	forward := strings.replace_all(raw, "\\", "/")

	// Convert drive-letter prefix:  "C:/..." -> "/C/..."
	if len(forward) >= 2 && forward[1] == ':' {
		drive := string([]u8{forward[0]})
		rest  := forward[2:]  // strip the ':'
		return strings.concatenate({"/", drive, rest})
	}

	return forward
}

// Walk NT_PATH_TABLE and return the TimelessOS canonical path.
// This replaces the old nt_translate_path that was sending
// everything to /strata/linux which was completely wrong.
nt_translate_path :: proc(internal_path: string) -> string {
	for entry in NT_PATH_TABLE {
		if strings.has_prefix(internal_path, entry.nt_prefix) {
			if entry.strip_prefix {
				rest := internal_path[len(entry.nt_prefix):]
				return strings.concatenate({entry.timeless_path, rest})
			}
			return entry.timeless_path
		}
	}
	// No match — return the internal path unchanged so the VFS
	// can attempt a direct lookup.  Better than silently routing
	// to the wrong stratum.
	log.warnf("NT VFS: no path mapping for '%v'", internal_path)
	return internal_path
}

// Reverse translation: TimelessOS path -> NT internal path
// Used when the kernel needs to present a path back to the NT process.
timeless_to_nt_internal :: proc(timeless_path: string) -> string {
	for entry in NT_PATH_TABLE {
		if !entry.strip_prefix do continue
		if strings.has_prefix(timeless_path, entry.timeless_path) {
			rest := timeless_path[len(entry.timeless_path):]
			return strings.concatenate({entry.nt_prefix, rest})
		}
	}
	return timeless_path
}

// ============================================================
// Handle table helpers
// ============================================================

_alloc_handle :: proc(h: ^NT_Handle) -> u64 {
	handle := _next_handle
	_next_handle += 1
	_nt_handle_table[handle] = h
	return handle
}

_handle_get :: proc(handle: u64) -> ^NT_Handle {
	h, ok := _nt_handle_table[handle]
	if !ok do return nil
	return h
}

// ============================================================
// Internal helpers
// ============================================================

_set_io_status :: proc(io_status_ptr: u64, status: NT_Status, info: u64) {
	if io_status_ptr == 0 do return
	ios := cast(^NT_IO_Status_Block)(uintptr(io_status_ptr))
	ios.status      = status
	ios.information = info
}

_disposition_to_vfs_flags :: proc(access: u32, disposition: u32) -> u32 {
	flags: u32 = 0
	if access & FILE_WRITE_DATA != 0 || access & GENERIC_WRITE != 0 {
		flags |= vfs.O_RDWR
	} else {
		flags |= vfs.O_RDONLY
	}
	switch disposition {
	case FILE_CREATE:
		flags |= vfs.O_CREAT | vfs.O_EXCL
	case FILE_OPEN_IF:
		flags |= vfs.O_CREAT
	case FILE_OVERWRITE_IF:
		flags |= vfs.O_CREAT | vfs.O_TRUNC
	case FILE_SUPERSEDE:
		flags |= vfs.O_CREAT | vfs.O_TRUNC
	case FILE_OVERWRITE:
		flags |= vfs.O_TRUNC
	}
	return flags
}

_vfs_attr_to_nt :: proc(mode: u32) -> u32 {
	nt_attr: u32 = 0x00000020  // FILE_ATTRIBUTE_ARCHIVE (default)
	if mode & 0o040000 != 0 {  // S_IFDIR
		nt_attr = 0x00000010   // FILE_ATTRIBUTE_DIRECTORY
	}
	if mode & 0o200 == 0 {     // not owner-writable = read only
		nt_attr |= 0x00000001  // FILE_ATTRIBUTE_READONLY
	}
	return nt_attr
}
