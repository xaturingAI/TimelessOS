package filesystem.vfs

import (
	"core:log"
	"core:mem"
	"core:strings"
)

// ============================================================
// Constants
// ============================================================

STRATA_MOUNT_ROOT :: "/Mount/strata"

// ============================================================
// Stratum type enum  (was a bare u32 — now meaningful)
// ============================================================

Stratum_Type :: enum u32 {
	Native        = 0,  // TimelessOS native kernel space
	Linux         = 1,  // Linux ELF / syscall-compat stratum
	NT_Windows    = 2,  // Windows NT / Wine / ReactOS stratum
	QEMU_Guest    = 3,  // Full QEMU VM guest (any OS)
	FreeBSD       = 4,  // FreeBSD syscall-compat stratum
	XNU_MacOS     = 5,  // macOS XNU syscall-compat stratum
}

// ============================================================
// QEMU disk image descriptor
// Used when stratum_type == .QEMU_Guest
// ============================================================

QEMU_Image_Format :: enum u8 {
	Raw    = 0,
	QCow2  = 1,
	VDI    = 2,
	VMDK   = 3,
}

QEMU_Image :: struct {
	image_path:   string,           // path to the .qcow2 / .img file on host
	format:       QEMU_Image_Format,
	guest_os:     Stratum_Type,     // what OS is inside the image
	mount_offset: u64,              // byte offset to partition (0 = auto)
	fs_type:      string,           // "ntfs", "ext4", "apfs", etc.
	mounted:      bool,
	loop_device:  string,           // assigned loop device e.g. "/dev/loop0"
}

// ============================================================
// OS VFS Layout Map
// Maps TimelessOS canonical paths  <->  guest OS native paths
// This is what lets the kernel translate syscall paths correctly
// e.g.  Windows NtOpenFile("C:\Users\keres\...")
//        -> TimelessOS  "/User/live-users/keres/..."
// ============================================================

Path_Map_Entry :: struct {
	timeless_path: string,   // canonical TimelessOS path
	guest_path:    string,   // what the guest OS calls this
	bidirectional: bool,     // translate in both directions?
}

OS_Layout :: struct {
	stratum_type: Stratum_Type,
	name:         string,
	path_map:     []Path_Map_Entry,
}

// Linux layout  (guest uses POSIX paths)
LINUX_LAYOUT :: OS_Layout{
	stratum_type = .Linux,
	name         = "linux",
	path_map     = []Path_Map_Entry{
		{ timeless_path = "/User/live-users",   guest_path = "/home",         bidirectional = true  },
		{ timeless_path = "/User/root",          guest_path = "/root",         bidirectional = true  },
		{ timeless_path = "/Library/tmp",        guest_path = "/tmp",          bidirectional = true  },
		{ timeless_path = "/Library/cache",      guest_path = "/var/cache",    bidirectional = true  },
		{ timeless_path = "/Software/system-pkgs/linux", guest_path = "/usr", bidirectional = false },
		{ timeless_path = "/Library/shared-libs",guest_path = "/usr/lib",     bidirectional = true  },
		{ timeless_path = "/Library/lang",       guest_path = "/usr/local",   bidirectional = false },
		{ timeless_path = "/Settings/System",    guest_path = "/etc",         bidirectional = true  },
		{ timeless_path = "/Mount",              guest_path = "/mnt",         bidirectional = true  },
		{ timeless_path = "/System/Boot",        guest_path = "/boot",        bidirectional = false },
	},
}

// Windows NT layout  (guest uses drive-letter paths)
// NOTE: We represent Windows paths internally as unix-style
// "/C/" instead of "C:\" to avoid backslash hell in the kernel.
// The NT syscall layer translates "C:\..." <-> "/C/..." on entry/exit.
NT_LAYOUT :: OS_Layout{
	stratum_type = .NT_Windows,
	name         = "nt-windows",
	path_map     = []Path_Map_Entry{
		{ timeless_path = "/User/live-users",    guest_path = "/C/Users",                 bidirectional = true  },
		{ timeless_path = "/User/root",          guest_path = "/C/Users/Administrator",   bidirectional = true  },
		{ timeless_path = "/Library/tmp",        guest_path = "/C/Windows/Temp",          bidirectional = true  },
		{ timeless_path = "/Library/cache",      guest_path = "/C/Windows/SoftwareDistribution", bidirectional = false },
		{ timeless_path = "/Software/system-pkgs/nt",     guest_path = "/C/Windows",     bidirectional = false },
		{ timeless_path = "/Library/shared-libs",guest_path = "/C/Windows/System32",     bidirectional = true  },
		{ timeless_path = "/Settings/User",      guest_path = "/C/Users/%USER%/AppData/Roaming", bidirectional = true },
		{ timeless_path = "/Settings/System",    guest_path = "/C/Windows/System32/config", bidirectional = false },
		{ timeless_path = "/Software/user-pkgs", guest_path = "/C/Program Files",        bidirectional = true  },
		{ timeless_path = "/Mount",              guest_path = "/",                        bidirectional = false },
	},
}

// FreeBSD layout  (very close to Linux but subtle differences)
FREEBSD_LAYOUT :: OS_Layout{
	stratum_type = .FreeBSD,
	name         = "freebsd",
	path_map     = []Path_Map_Entry{
		{ timeless_path = "/User/live-users",    guest_path = "/home",         bidirectional = true  },
		{ timeless_path = "/User/root",          guest_path = "/root",         bidirectional = true  },
		{ timeless_path = "/Library/tmp",        guest_path = "/tmp",          bidirectional = true  },
		{ timeless_path = "/Library/shared-libs",guest_path = "/usr/lib",     bidirectional = true  },
		{ timeless_path = "/Software/system-pkgs/freebsd", guest_path = "/usr/local", bidirectional = false },
		{ timeless_path = "/Settings/System",    guest_path = "/etc",         bidirectional = true  },
		{ timeless_path = "/Mount",              guest_path = "/mnt",         bidirectional = true  },
	},
}

// macOS XNU layout
XNU_LAYOUT :: OS_Layout{
	stratum_type = .XNU_MacOS,
	name         = "xnu-macos",
	path_map     = []Path_Map_Entry{
		{ timeless_path = "/User/live-users",    guest_path = "/Users",        bidirectional = true  },
		{ timeless_path = "/User/root",          guest_path = "/var/root",     bidirectional = true  },
		{ timeless_path = "/Library/tmp",        guest_path = "/private/tmp",  bidirectional = true  },
		{ timeless_path = "/Library/shared-libs",guest_path = "/usr/lib",     bidirectional = true  },
		{ timeless_path = "/Software/system-pkgs/xnu", guest_path = "/System/Library", bidirectional = false },
		{ timeless_path = "/Software/user-pkgs", guest_path = "/Applications", bidirectional = true  },
		{ timeless_path = "/Settings/User",      guest_path = "/Users/%USER%/Library/Preferences", bidirectional = true },
		{ timeless_path = "/Settings/System",    guest_path = "/Library/Preferences", bidirectional = true  },
		{ timeless_path = "/Mount",              guest_path = "/Volumes",      bidirectional = true  },
	},
}

// Global layout registry  (indexed by Stratum_Type)
OS_LAYOUTS := [Stratum_Type]^OS_Layout{
	.Linux      = &LINUX_LAYOUT,
	.NT_Windows = &NT_LAYOUT,
	.FreeBSD    = &FREEBSD_LAYOUT,
	.XNU_MacOS  = &XNU_LAYOUT,
}

// ============================================================
// Strata_Mount  (expanded from original)
// ============================================================

Strata_Mount_Flags :: distinct u32

ST_MOUNT_STRATUM  :: Strata_Mount_Flags(0x01)
ST_MOUNT_SHARED   :: Strata_Mount_Flags(0x02)
ST_MOUNT_VIRT     :: Strata_Mount_Flags(0x04)
ST_MOUNT_PERSIST  :: Strata_Mount_Flags(0x08)
ST_MOUNT_READONLY :: Strata_Mount_Flags(0x10)  // new: useful for system dirs

Strata_Mount :: struct {
	stratum_name: string,
	stratum_type: Stratum_Type,   // was u32, now typed enum
	host_path:    string,         // TimelessOS-side canonical path
	guest_path:   string,         // what the guest OS sees
	flags:        Strata_Mount_Flags,
	mount_point:  ^VFS_MOUNT,
	qemu_image:   ^QEMU_Image,    // non-nil when stratum_type == .QEMU_Guest
	layout:       ^OS_Layout,     // path translation table for this stratum
}

// ============================================================
// Global state
// ============================================================

strata_mounts: [dynamic]Strata_Mount
qemu_images:   [dynamic]QEMU_Image

// ============================================================
// Init
// ============================================================

init_strata_vfs :: proc() -> bool {
	log.info("VFS Strata: Initializing strata VFS integration...")

	// Fixed: was init_dynamic() which does not exist in Odin
	strata_mounts = make([dynamic]Strata_Mount, 0, 8)
	qemu_images   = make([dynamic]QEMU_Image,   0, 4)

	vfs_register_fs("strata", &strata_fs_ops, &strata_file_ops)

	setup_default_strata_mounts()

	log.infof("VFS Strata: Initialized with %v strata mounts", len(strata_mounts))
	return true
}

// ============================================================
// FS + File ops tables
// ============================================================

strata_fs_ops := FS_OPS{
	mount   = strata_mount,
	unmount = strata_unmount,
	sync    = strata_sync,
	statfs  = strata_statfs,
}

strata_file_ops := FILE_OPS{
	open   = strata_open,
	close  = strata_close,
	read   = strata_read,
	write  = strata_write,
	seek   = strata_seek,
	stat   = strata_stat,
	mkdir  = strata_mkdir,
	unlink = strata_unlink,
	rmdir  = strata_rmdir,
}

// ============================================================
// Default mounts  (fixed: was broken nested struct literal)
// ============================================================

setup_default_strata_mounts :: proc() {
	// --- Native TimelessOS root ---
	append(&strata_mounts, Strata_Mount{
		stratum_name = "native",
		stratum_type = .Native,
		host_path    = "/",
		guest_path   = "/",
		flags        = ST_MOUNT_STRATUM,
		layout       = nil,
	})

	// --- Linux stratum shared mounts ---
	append(&strata_mounts, Strata_Mount{
		stratum_name = "linux",
		stratum_type = .Linux,
		host_path    = "/User/live-users",
		guest_path   = "/home",
		flags        = ST_MOUNT_SHARED,
		layout       = &LINUX_LAYOUT,
	})
	append(&strata_mounts, Strata_Mount{
		stratum_name = "linux",
		stratum_type = .Linux,
		host_path    = "/Library/tmp",
		guest_path   = "/tmp",
		flags        = ST_MOUNT_SHARED,
		layout       = &LINUX_LAYOUT,
	})

	// --- NT / Windows stratum ---
	// NOTE: We store Windows paths as "/C/..." internally.
	// The NT syscall handler converts "C:\..." -> "/C/..." on entry.
	append(&strata_mounts, Strata_Mount{
		stratum_name = "nt-windows",
		stratum_type = .NT_Windows,
		host_path    = "/User/live-users",
		guest_path   = "/C/Users",          // internal unix form of C:\Users
		flags        = ST_MOUNT_SHARED,
		layout       = &NT_LAYOUT,
	})
	append(&strata_mounts, Strata_Mount{
		stratum_name = "nt-windows",
		stratum_type = .NT_Windows,
		host_path    = "/Software/system-pkgs/nt",
		guest_path   = "/C/Windows",
		flags        = ST_MOUNT_STRATUM | ST_MOUNT_READONLY,
		layout       = &NT_LAYOUT,
	})
	append(&strata_mounts, Strata_Mount{
		stratum_name = "nt-windows",
		stratum_type = .NT_Windows,
		host_path    = "/Library/tmp",
		guest_path   = "/C/Windows/Temp",
		flags        = ST_MOUNT_SHARED,
		layout       = &NT_LAYOUT,
	})
}

// ============================================================
// QEMU image mounting
// Call this to plug a .qcow2 / .img file in as a stratum
//
// Example:
//   mount_qemu_image("/Mount/strata/reactos.qcow2",
//                    .QCow2, .NT_Windows, "ntfs")
// ============================================================

mount_qemu_image :: proc(
	image_path: string,
	format:     QEMU_Image_Format,
	guest_os:   Stratum_Type,
	fs_type:    string,
) -> bool {
	log.infof("VFS Strata: Mounting QEMU image '%v' (os=%v fs=%v)", image_path, guest_os, fs_type)

	img := QEMU_Image{
		image_path = image_path,
		format     = format,
		guest_os   = guest_os,
		fs_type    = fs_type,
		mounted    = false,
	}

	// Assign a loop device slot (real impl would call into driver layer)
	loop_idx := len(qemu_images)
	img.loop_device = strings.concatenate({"/dev/loop", _int_to_str(loop_idx)})

	append(&qemu_images, img)
	last := &qemu_images[len(qemu_images)-1]

	// Find the layout for this guest OS type
	layout := OS_LAYOUTS[guest_os]

	// Register a QEMU_Guest stratum mount for each mapped path in the layout
	if layout != nil {
		for &entry in layout.path_map {
			append(&strata_mounts, Strata_Mount{
				stratum_name = layout.name,
				stratum_type = .QEMU_Guest,
				host_path    = entry.timeless_path,
				guest_path   = entry.guest_path,
				flags        = ST_MOUNT_STRATUM,
				qemu_image   = last,
				layout       = layout,
			})
		}
	}

	last.mounted = true
	log.infof("VFS Strata: QEMU image mounted at %v -> %v", img.loop_device, image_path)
	return true
}

unmount_qemu_image :: proc(image_path: string) -> bool {
	for i in 0..<len(qemu_images) {
		if qemu_images[i].image_path == image_path {
			qemu_images[i].mounted = false
			// Remove all strata mounts that reference this image
			i_mount := 0
			for i_mount < len(strata_mounts) {
				if strata_mounts[i_mount].qemu_image == &qemu_images[i] {
					ordered_remove(&strata_mounts, i_mount)
				} else {
					i_mount += 1
				}
			}
			ordered_remove(&qemu_images, i)
			return true
		}
	}
	return false
}

// ============================================================
// Path translation  (the core of syscall path mapping)
//
// translate_to_guest:   "/User/live-users/keres/doc.txt"
//                    -> "/home/keres/doc.txt"  (for Linux stratum)
//                    -> "/C/Users/keres/doc.txt" (for NT stratum)
//
// translate_to_host:    reverse of the above
// ============================================================

translate_to_guest :: proc(timeless_path: string, stype: Stratum_Type) -> string {
	layout := OS_LAYOUTS[stype]
	if layout == nil do return timeless_path

	for &entry in layout.path_map {
		if strings.has_prefix(timeless_path, entry.timeless_path) {
			rest := timeless_path[len(entry.timeless_path):]
			return strings.concatenate({entry.guest_path, rest})
		}
	}
	return timeless_path
}

translate_to_host :: proc(guest_path: string, stype: Stratum_Type) -> string {
	layout := OS_LAYOUTS[stype]
	if layout == nil do return guest_path

	for &entry in layout.path_map {
		if !entry.bidirectional do continue
		if strings.has_prefix(guest_path, entry.guest_path) {
			rest := guest_path[len(entry.guest_path):]
			return strings.concatenate({entry.timeless_path, rest})
		}
	}
	return guest_path
}

// NT-specific helper: convert "C:\Users\keres" -> "/C/Users/keres"
// Called by the NT syscall layer before any VFS operation
nt_path_to_internal :: proc(nt_path: string) -> string {
	// "C:\..." -> "/C/..."
	if len(nt_path) >= 3 && nt_path[1] == ':' {
		drive  := nt_path[0:1]
		rest   := nt_path[2:]
		// Replace backslashes with forward slashes
		rest_fwd := strings.replace_all(rest, "\\", "/")
		return strings.concatenate({"/", drive, rest_fwd})
	}
	return nt_path
}

// Reverse: "/C/Users/keres" -> "C:\Users\keres"
internal_path_to_nt :: proc(internal: string) -> string {
	if len(internal) >= 3 && internal[0] == '/' {
		drive := internal[1:2]
		rest  := internal[2:]
		rest_bs := strings.replace_all(rest, "/", "\\")
		return strings.concatenate({drive, ":", rest_bs})
	}
	return internal
}

// ============================================================
// Mount / Unmount
// ============================================================

strata_mount :: proc(device: string, mountpoint: string, flags: u32) -> ^VFS_MOUNT {
	log.infof("VFS Strata: Mounting strata '%v' at %v", device, mountpoint)

	parts := strings.split(device, ":")
	if len(parts) < 2 {
		log.errorf("VFS Strata: bad device string '%v' (expected name:host_path)", device)
		return nil
	}

	stratum_name := parts[0]
	host_path    := parts[1]
	guest_path   := mountpoint
	if len(parts) >= 3 {
		guest_path = parts[2]
	}

	sm := Strata_Mount{
		stratum_name = stratum_name,
		host_path    = host_path,
		guest_path   = guest_path,
		flags        = Strata_Mount_Flags(flags),
	}
	append(&strata_mounts, sm)

	mount := &VFS_MOUNT{
		device     = device,
		mountpoint = mountpoint,
		fs_type    = "strata",
		flags      = flags,
		root_inode = 1,
		ops        = &strata_fs_ops,
		file_ops   = &strata_file_ops,
	}

	log.infof("VFS Strata: Mounted '%v' at %v", host_path, mountpoint)
	return mount
}

// Fixed: was *VFS_MOUNT (C pointer syntax) — Odin uses ^
strata_unmount :: proc(mount: ^VFS_MOUNT) -> bool {
	log.infof("VFS Strata: Unmounting at %v", mount.mountpoint)

	for i in 0..<len(strata_mounts) {
		if strata_mounts[i].mount_point == mount {
			ordered_remove(&strata_mounts, i)
			return true
		}
	}
	return false
}

strata_sync :: proc(mount: ^VFS_MOUNT) -> bool {
	log.debug("VFS Strata: Syncing strata mount")
	return true
}

strata_statfs :: proc(mount: ^VFS_MOUNT) -> ^FS_STAT {
	return &FS_STAT{
		total_blocks  = 0,
		free_blocks   = 0,
		total_inodes  = 0,
		free_inodes   = 0,
		block_size    = 4096,
		max_name_len  = 255,
		fs_type       = "strata",
	}
}

// ============================================================
// File ops  (fixed ^  pointer syntax throughout)
// ============================================================

strata_open :: proc(path: string, flags: u32) -> ^VFS_FILE {
	resolved := resolve_strata_path(path)
	if resolved == "" do return nil
	return vfs_open_path(resolved)
}

strata_close :: proc(file: ^VFS_FILE) -> bool {
	if file.mount != nil do return true
	return vfs_close_file(file)
}

strata_read :: proc(file: ^VFS_FILE, buffer: []u8, offset: u64) -> int {
	// Delegate to the underlying real FS once a QEMU image is loopback-mounted
	if file.mount != nil && file.mount.fs_type != "strata" {
		return vfs_read_file(file, buffer, offset)
	}
	return -1
}

strata_write :: proc(file: ^VFS_FILE, buffer: []u8, offset: u64) -> int {
	if file.mount != nil && file.mount.fs_type != "strata" {
		return vfs_write_file(file, buffer, offset)
	}
	return -1
}

strata_seek :: proc(file: ^VFS_FILE, offset: i64, whence: u32) -> u64 {
	return file.offset
}

strata_stat :: proc(path: string) -> ^FILE_STAT {
	resolved := resolve_strata_path(path)
	if resolved == "" do return nil
	return vfs_stat_path(resolved)
}

strata_mkdir :: proc(path: string, perms: FILE_PERMS) -> bool {
	log.debugf("VFS Strata: mkdir %v", path)
	resolved := resolve_strata_path(path)
	if resolved == "" do return false
	return vfs_mkdir(resolved, perms)
}

strata_unlink :: proc(path: string) -> bool {
	log.debugf("VFS Strata: unlink %v", path)
	resolved := resolve_strata_path(path)
	if resolved == "" do return false
	return vfs_unlink(resolved)
}

strata_rmdir :: proc(path: string) -> bool {
	log.debugf("VFS Strata: rmdir %v", path)
	resolved := resolve_strata_path(path)
	if resolved == "" do return false
	return vfs_rmdir(resolved)
}

// ============================================================
// Path resolution helpers
// ============================================================

// Resolve a guest-side path to a TimelessOS host path.
// Checks all registered strata mounts for a prefix match.
resolve_strata_path :: proc(path: string) -> string {
	for &m in strata_mounts {
		if strings.has_prefix(path, m.guest_path) {
			rest := path[len(m.guest_path):]
			return strings.concatenate({m.host_path, rest})
		}
	}
	return path   // no translation needed — already a host path
}

get_strata_mount :: proc(guest_path: string) -> ^Strata_Mount {
	for i in 0..<len(strata_mounts) {
		if strata_mounts[i].guest_path == guest_path {
			return &strata_mounts[i]
		}
	}
	return nil
}

get_strata_mounts_for_type :: proc(stype: Stratum_Type) -> [dynamic]^Strata_Mount {
	result := make([dynamic]^Strata_Mount, 0, 4)
	for i in 0..<len(strata_mounts) {
		if strata_mounts[i].stratum_type == stype {
			append(&result, &strata_mounts[i])
		}
	}
	return result
}

list_strata_mounts :: proc() {
	log.info("VFS Strata: Active mounts:")
	for &m in strata_mounts {
		log.infof("  [%v] %v -> %v  (host: %v)",
			m.stratum_type, m.guest_path, m.host_path, m.stratum_name)
	}
}

get_stratum_root :: proc(name: string) -> string {
	return strings.concatenate({STRATA_MOUNT_ROOT, "/", name})
}

is_strata_path :: proc(path: string) -> bool {
	return strings.has_prefix(path, STRATA_MOUNT_ROOT)
}

// ============================================================
// Internal utility  (avoids importing fmt in kernel context)
// ============================================================

_int_to_str :: proc(n: int) -> string {
	if n == 0 do return "0"
	buf: [20]u8
	i := len(buf)
	v := n
	for v > 0 {
		i -= 1
		buf[i] = u8('0') + u8(v % 10)
		v /= 10
	}
	return string(buf[i:])
}
