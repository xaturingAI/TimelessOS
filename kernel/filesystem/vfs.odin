// Virtual Filesystem (VFS) Layer
// Unified filesystem interface for TimelessOS

package filesystem.vfs

import (
    "core:log"
    "core:mem"
    "core:string"
)

// ============================================================================
// VFS Core Structures
// ============================================================================

// File Types
FILE_TYPE :: enum {
    Unknown,
    Regular,
    Directory,
    Character_Device,
    Block_Device,
    FIFO,
    Socket,
    Symlink,
}

// File Permissions
FILE_PERMS :: struct {
    user_read: bool,
    user_write: bool,
    user_exec: bool,
    group_read: bool,
    group_write: bool,
    group_exec: bool,
    other_read: bool,
    other_write: bool,
    other_exec: bool,
    setuid: bool,
    setgid: bool,
    sticky: bool,
}

// File Metadata
FILE_STAT :: struct {
    inode:      u64,
    size:       u64,
    blocks:     u64,
    type:       FILE_TYPE,
    perms:      FILE_PERMS,
    uid:        u32,
    gid:        u32,
    atime:      u64,  // Last access time
    mtime:      u64,  // Last modification time
    ctime:      u64,  // Last change time
    link_count: u32,
}

// File Operations
FILE_OPS :: struct {
    open:     proc(path: string, flags: u32) -> *VFS_FILE,
    close:    proc(file: *VFS_FILE) -> bool,
    read:     proc(file: *VFS_FILE, buffer: []u8, offset: u64) -> int,
    write:    proc(file: *VFS_FILE, buffer: []u8, offset: u64) -> int,
    seek:     proc(file: *VFS_FILE, offset: i64, whence: u32) -> u64,
    readdir:  proc(file: *VFS_FILE) -> *VFS_DIRENT,
    mkdir:    proc(path: string, perms: FILE_PERMS) -> bool,
    unlink:   proc(path: string) -> bool,
    rmdir:    proc(path: string) -> bool,
    stat:     proc(path: string) -> *FILE_STAT,
    chmod:    proc(path: string, perms: FILE_PERMS) -> bool,
    chown:    proc(path: string, uid: u32, gid: u32) -> bool,
    rename:   proc(old_path: string, new_path: string) -> bool,
    symlink:  proc(target: string, link_path: string) -> bool,
    readlink: proc(path: string) -> string,
}

// Filesystem Operations
FS_OPS :: struct {
    mount:     proc(device: string, mountpoint: string, flags: u32) -> *VFS_MOUNT,
    unmount:   proc(mount: *VFS_MOUNT) -> bool,
    statfs:    proc(mount: *VFS_MOUNT) -> *FS_STAT,
    sync:      proc(mount: *VFS_MOUNT) -> bool,
}

// Filesystem Statistics
FS_STAT :: struct {
    total_blocks:  u64,
    free_blocks:   u64,
    total_inodes:  u64,
    free_inodes:   u64,
    block_size:    u32,
    max_name_len:  u32,
    fs_type:       string,
}

// VFS File Handle
VFS_FILE :: struct {
    path:       string,
    inode:      u64,
    offset:     u64,
    flags:      u32,
    mode:       u32,
    ref_count:  u32,
    fs_data:    rawptr,  // Filesystem-specific data
    mount:      *VFS_MOUNT,
}

// VFS Directory Entry
VFS_DIRENT :: struct {
    name:   string,
    inode:  u64,
    type:   FILE_TYPE,
}

// VFS Mount Point
VFS_MOUNT :: struct {
    device:     string,
    mountpoint: string,
    fs_type:    string,
    flags:      u32,
    root_inode: u64,
    fs_data:    rawptr,  // Filesystem-specific data
    ops:        *FS_OPS,
    file_ops:   *FILE_OPS,
    ref_count:  u32,
    next:       *VFS_MOUNT,
}

// VFS Path Resolution
VFS_PATH :: struct {
    mount:      *VFS_MOUNT,
    inode:      u64,
    remainder:  string,
}

// ============================================================================
// VFS Global State
// ============================================================================

// Mount Flags
MOUNT_RDONLY ::  1
MOUNT_NOEXEC ::   2
MOUNT_NOSUID ::   4
MOUNT_NODEV ::    8

// Open Flags
O_RDONLY ::  0
O_WRONLY ::  1
O_RDWR ::    2
O_CREAT ::   4
O_EXCL ::    8
O_TRUNC ::   16
O_APPEND ::  32
O_DIRECTORY :: 64
O_SYMLINK ::  128

// Seek Whence
SEEK_SET :: 0
SEEK_CUR :: 1
SEEK_END :: 2

// Global VFS State
vfs_initialized: bool = false
root_mount: *VFS_MOUNT = nil
mount_count: u32 = 0
file_count: u32 = 0

// Mount Point List
mount_list: *VFS_MOUNT = nil


// Initialize VFS
vfs_init :: proc() -> bool {
    log.info("VFS: Initializing virtual filesystem...")
    
    if vfs_initialized {
        log.warn("VFS: Already initialized")
        return true
    }
    
    vfs_initialized = true
    mount_count = 0
    file_count = 0
    
    log.info("VFS: Initialized")
    return true
}


// Register Filesystem Driver
vfs_register_fs :: proc(name: string, ops: *FS_OPS, file_ops: *FILE_OPS) -> bool {
    log.info("VFS: Registering filesystem '%s'", name)
    
    // Store filesystem driver in registry
    // This would add to a global filesystem driver table
    
    return true
}


// ============================================================================
// Path Resolution
// ============================================================================

// Resolve Path to Inode
vfs_resolve_path :: proc(path: string) -> *VFS_PATH {
    if path == "" || path[0] != '/' {
        return nil  // Must be absolute path
    }
    
    // Find mount point
    mount := find_mount_for_path(path)
    if mount == nil {
        return nil
    }
    
    // Start from root inode
    current_inode := mount.root_inode
    
    // Parse path components
    components := string.split(path, "/")
    
    for comp in components {
        if comp == "" || comp == "." {
            continue
        }
        
        if comp == ".." {
            // Go to parent (simplified)
            continue
        }
        
        // Lookup component in current directory
        // This would call the filesystem's lookup operation
        // For now, just continue
        _ = current_inode
    }
    
    return &VFS_PATH{
        mount = mount,
        inode = current_inode,
        remainder = "",
    }
}


// Find Mount Point for Path
find_mount_for_path :: proc(path: string) -> *VFS_MOUNT {
    // Walk mount list to find best match
    // Start from root, find longest prefix match
    
    current := mount_list
    
    best_match := root_mount
    
    for current != nil {
        if string.has_prefix(path, current.mountpoint) {
            if best_match == nil || 
               len(current.mountpoint) > len(best_match.mountpoint) {
                best_match = current
            }
        }
        current = current.next
    }
    
    return best_match
}


// ============================================================================
// Mount Operations
// ============================================================================

// Mount Filesystem
vfs_mount :: proc(device: string, mountpoint: string, 
                  fs_type: string, flags: u32) -> bool {
    log.info("VFS: Mounting %s on %s (type: %s)", 
             device, mountpoint, fs_type)
    
    // Find filesystem driver
    fs_ops, file_ops := get_fs_ops(fs_type)
    if fs_ops == nil {
        log.error("VFS: Unknown filesystem type '%s'", fs_type)
        return false
    }
    
    // Call filesystem mount
    mount := fs_ops.mount(device, mountpoint, flags)
    if mount == nil {
        log.error("VFS: Mount failed")
        return false
    }
    
    // Add to mount list
    if mount_list == nil {
        mount_list = mount
    } else {
        // Add to end of list
        current := mount_list
        for current.next != nil {
            current = current.next
        }
        current.next = mount
    }
    
    mount_count++
    
    log.info("VFS: Mounted %s on %s", device, mountpoint)
    return true
}


// Unmount Filesystem
vfs_unmount :: proc(mountpoint: string) -> bool {
    log.info("VFS: Unmounting %s", mountpoint)
    
    // Find mount
    mount := find_mount(mountpoint)
    if mount == nil {
        log.error("VFS: Mount point not found: %s", mountpoint)
        return false
    }
    
    // Check if busy
    if mount.ref_count > 0 {
        log.error("VFS: Mount point busy")
        return false
    }
    
    // Call filesystem unmount
    if !mount.ops.unmount(mount) {
        log.error("VFS: Unmount failed")
        return false
    }
    
    // Remove from mount list
    remove_mount(mount)
    
    mount_count--
    
    log.info("VFS: Unmounted %s", mountpoint)
    return true
}


// Find Mount by Mountpoint
find_mount :: proc(mountpoint: string) -> *VFS_MOUNT {
    current := mount_list
    for current != nil {
        if current.mountpoint == mountpoint {
            return current
        }
        current = current.next
    }
    return nil
}


// Remove Mount from List
remove_mount :: proc(mount: *VFS_MOUNT) {
    if mount == mount_list {
        mount_list = mount.next
        return
    }
    
    current := mount_list
    for current != nil && current.next != mount {
        current = current.next
    }
    
    if current != nil {
        current.next = mount.next
    }
}


// Get Filesystem Operations
get_fs_ops :: proc(fs_type: string) -> (*FS_OPS, *FILE_OPS) {
    // Lookup filesystem driver by name
    // This would search a global registry
    
    switch fs_type {
    case "ext4":
        // return &ext4_fs_ops, &ext4_file_ops
    case "fat32":
        // return &fat32_fs_ops, &fat32_file_ops
    case "zfs":
        // return &zfs_fs_ops, &zfs_file_ops
    case "xfs":
        // return &xfs_fs_ops, &xfs_file_ops
    }
    
    return nil, nil
}


// ============================================================================
// File Operations
// ============================================================================

// Open File
vfs_open :: proc(path: string, flags: u32, mode: u32) -> *VFS_FILE {
    log.debug("VFS: Opening %s (flags: 0x%X)", path, flags)
    
    // Resolve path
    resolved := vfs_resolve_path(path)
    if resolved == nil {
        return nil
    }
    
    // Get file operations
    file_ops := resolved.mount.file_ops
    if file_ops == nil || file_ops.open == nil {
        return nil
    }
    
    // Open file
    file := file_ops.open(path, flags)
    if file != nil {
        file.mount = resolved.mount
        file.flags = flags
        file.mode = mode
        file.ref_count = 1
        file_count++
    }
    
    return file
}


// Close File
vfs_close :: proc(file: *VFS_FILE) -> bool {
    if file == nil {
        return false
    }
    
    file.ref_count--
    
    if file.ref_count == 0 {
        // Call filesystem close
        if file.mount.file_ops.close != nil {
            file.mount.file_ops.close(file)
        }
        
        file_count--
    }
    
    return true
}


// Read File
vfs_read :: proc(file: *VFS_FILE, buffer: []u8) -> int {
    if file == nil || file.mount.file_ops.read == nil {
        return -1
    }
    
    n := file.mount.file_ops.read(file, buffer, file.offset)
    
    if n > 0 {
        file.offset += cast(u64)(n)
    }
    
    return n
}


// Write File
vfs_write :: proc(file: *VFS_FILE, buffer: []u8) -> int {
    if file == nil || file.mount.file_ops.write == nil {
        return -1
    }
    
    n := file.mount.file_ops.write(file, buffer, file.offset)
    
    if n > 0 {
        file.offset += cast(u64)(n)
    }
    
    return n
}


// Seek File
vfs_seek :: proc(file: *VFS_FILE, offset: i64, whence: u32) -> u64 {
    if file == nil || file.mount.file_ops.seek == nil {
        return file.offset
    }
    
    file.offset = file.mount.file_ops.seek(file, offset, whence)
    return file.offset
}


// Get File Status
vfs_stat :: proc(path: string) -> *FILE_STAT {
    resolved := vfs_resolve_path(path)
    if resolved == nil {
        return nil
    }
    
    if resolved.mount.file_ops.stat == nil {
        return nil
    }
    
    return resolved.mount.file_ops.stat(path)
}


// ============================================================================
// Directory Operations
// ============================================================================

// Read Directory
vfs_readdir :: proc(file: *VFS_FILE) -> *VFS_DIRENT {
    if file == nil || file.mount.file_ops.readdir == nil {
        return nil
    }
    
    return file.mount.file_ops.readdir(file)
}


// Create Directory
vfs_mkdir :: proc(path: string, perms: FILE_PERMS) -> bool {
    resolved := vfs_resolve_path(path)
    if resolved == nil {
        return false
    }
    
    if resolved.mount.file_ops.mkdir == nil {
        return false
    }
    
    return resolved.mount.file_ops.mkdir(path, perms)
}


// Remove Directory
vfs_rmdir :: proc(path: string) -> bool {
    resolved := vfs_resolve_path(path)
    if resolved == nil {
        return false
    }
    
    if resolved.mount.file_ops.rmdir == nil {
        return false
    }
    
    return resolved.mount.file_ops.rmdir(path)
}


// ============================================================================
// File Operations (continued)
// ============================================================================

// Unlink File
vfs_unlink :: proc(path: string) -> bool {
    resolved := vfs_resolve_path(path)
    if resolved == nil {
        return false
    }
    
    if resolved.mount.file_ops.unlink == nil {
        return false
    }
    
    return resolved.mount.file_ops.unlink(path)
}


// Rename File/Directory
vfs_rename :: proc(old_path: string, new_path: string) -> bool {
    // Both paths should be on same mount
    old_resolved := vfs_resolve_path(old_path)
    new_resolved := vfs_resolve_path(new_path)
    
    if old_resolved == nil || new_resolved == nil {
        return false
    }
    
    if old_resolved.mount != new_resolved.mount {
        log.error("VFS: Cross-device rename not supported")
        return false
    }
    
    if old_resolved.mount.file_ops.rename == nil {
        return false
    }
    
    return old_resolved.mount.file_ops.rename(old_path, new_path)
}


// Create Symlink
vfs_symlink :: proc(target: string, link_path: string) -> bool {
    resolved := vfs_resolve_path(link_path)
    if resolved == nil {
        return false
    }
    
    if resolved.mount.file_ops.symlink == nil {
        return false
    }
    
    return resolved.mount.file_ops.symlink(target, link_path)
}


// Read Symlink
vfs_readlink :: proc(path: string) -> string {
    resolved := vfs_resolve_path(path)
    if resolved == nil {
        return ""
    }
    
    if resolved.mount.file_ops.readlink == nil {
        return ""
    }
    
    return resolved.mount.file_ops.readlink(path)
}


// Change Permissions
vfs_chmod :: proc(path: string, perms: FILE_PERMS) -> bool {
    resolved := vfs_resolve_path(path)
    if resolved == nil {
        return false
    }
    
    if resolved.mount.file_ops.chmod == nil {
        return false
    }
    
    return resolved.mount.file_ops.chmod(path, perms)
}


// Change Ownership
vfs_chown :: proc(path: string, uid: u32, gid: u32) -> bool {
    resolved := vfs_resolve_path(path)
    if resolved == nil {
        return false
    }
    
    if resolved.mount.file_ops.chown == nil {
        return false
    }
    
    return resolved.mount.file_ops.chown(path, uid, gid)
}


// ============================================================================
// Filesystem Statistics
// ============================================================================

// Get Filesystem Statistics
vfs_statfs :: proc(mountpoint: string) -> *FS_STAT {
    mount := find_mount(mountpoint)
    if mount == nil {
        return nil
    }
    
    if mount.ops.statfs == nil {
        return nil
    }
    
    return mount.ops.statfs(mount)
}


// Sync Filesystem
vfs_sync :: proc(mountpoint: string) -> bool {
    mount := find_mount(mountpoint)
    if mount == nil {
        return false
    }
    
    if mount.ops.sync == nil {
        return true  // No sync needed
    }
    
    return mount.ops.sync(mount)
}


// Sync All Filesystems
vfs_sync_all :: proc() {
    log.info("VFS: Syncing all filesystems...")
    
    current := mount_list
    for current != nil {
        if current.ops.sync != nil {
            current.ops.sync(current)
        }
        current = current.next
    }
}


// ============================================================================
// Utility Functions
// ============================================================================

// Check if Path is Directory
vfs_is_dir :: proc(path: string) -> bool {
    stat := vfs_stat(path)
    if stat == nil {
        return false
    }
    return stat.type == .Directory
}


// Check if Path is Regular File
vfs_is_file :: proc(path: string) -> bool {
    stat := vfs_stat(path)
    if stat == nil {
        return false
    }
    return stat.type == .Regular
}


// Check if Path Exists
vfs_exists :: proc(path: string) -> bool {
    return vfs_stat(path) != nil
}


// Get File Size
vfs_size :: proc(path: string) -> u64 {
    stat := vfs_stat(path)
    if stat == nil {
        return 0
    }
    return stat.size
}


// List Mount Points
vfs_list_mounts :: proc() {
    log.info("VFS: Mount points:")
    
    current := mount_list
    for current != nil {
        log.info("  %s on %s (type: %s)", 
                 current.device, current.mountpoint, current.fs_type)
        current = current.next
    }
}
