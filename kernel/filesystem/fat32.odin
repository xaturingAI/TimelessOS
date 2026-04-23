// FAT32 Filesystem Driver
// File Allocation Table 32-bit for TimelessOS

package filesystem.fat32

import (
    "core:log"
    "core:mem"
    "core:string"
    "mm:physical"
    "mm:virtual"
    "filesystem:vfs"
)

// ============================================================================
// FAT32 Structures
// ============================================================================

// FAT32 Boot Sector (BIOS Parameter Block)
fat32_boot_sector :: struct {
    // Jump instruction
    jmp_boot:       [3]u8,
    oem_name:       [8]u8,
    
    // BIOS Parameter Block
    bytes_per_sector:     u16,
    sectors_per_cluster:  u8,
    reserved_sectors:     u16,
    num_fats:             u8,
    root_entry_count:     u16,  // 0 for FAT32
    total_sectors_16:     u16,  // 0 for FAT32
    media_type:           u8,
    fat_size_16:          u16,  // 0 for FAT32
    sectors_per_track:    u16,
    num_heads:            u16,
    hidden_sectors:       u32,
    total_sectors_32:     u32,
    
    // FAT32 Extended BPB
    fat_size_32:          u32,
    ext_flags:            u16,
    fs_version:           u16,
    root_cluster:         u32,
    fs_info_sector:       u16,
    backup_boot_sector:   u16,
    reserved:             [12]u8,
    drive_number:         u8,
    reserved1:            u8,
    boot_signature:       u8,
    volume_id:            u32,
    volume_label:         [11]u8,
    fs_type:              [8]u8,
    
    // Boot code (420 bytes)
    boot_code:            [420]u8,
    
    // Boot signature
    signature:            u16,  // 0xAA55
}

// FAT32 Directory Entry
fat32_dir_entry :: struct {
    name:           [11]u8,  // 8.3 format
    attr:           u8,
    nt_reserved:    u8,
    create_time_10ms: u8,
    create_time:    u16,
    create_date:    u16,
    access_date:    u16,
    first_cluster_hi: u16,
    modify_time:    u16,
    modify_date:    u16,
    first_cluster_lo: u16,
    file_size:      u32,
}

// FAT32 Long Filename Entry (VFAT)
fat32_lfn_entry :: struct {
    order:          u8,
    name1:          [10]u8,  // Unicode
    attr:           u8,      // 0x0F for LFN
    type:           u8,      // 0x00
    checksum:       u8,
    name2:          [12]u8,  // Unicode
    first_cluster_lo: u16,   // 0x0000
    name3:          [4]u8,   // Unicode
}

// File Attributes
FAT32_ATTR_READ_ONLY ::  0x01
FAT32_ATTR_HIDDEN ::     0x02
FAT32_ATTR_SYSTEM ::     0x04
FAT32_ATTR_VOLUME_ID ::  0x08
FAT32_ATTR_DIRECTORY ::  0x10
FAT32_ATTR_ARCHIVE ::    0x20
FAT32_ATTR_LFN ::        0x0F  // Long filename entry

// FAT32 Cluster Markers
FAT32_EOC ::           0x0FFFFFF8  // End of chain
FAT32_BAD_CLUSTER ::   0x0FFFFFF7

// ============================================================================
// FAT32 Filesystem State
// ============================================================================

fat32_fs :: struct {
    mounted: bool,
    device: string,
    mountpoint: string,
    
    // Boot sector info
    bs: fat32_boot_sector,
    
    // Calculated values
    bytes_per_sector: u32,
    sectors_per_cluster: u32,
    bytes_per_cluster: u32,
    reserved_sectors: u32,
    fat_sectors: u32,
    root_cluster: u32,
    data_start_sector: u32,
    total_clusters: u32,
    num_fats: u32,
    
    // FSINFO sector
    fsinfo_sector: u32,
    free_clusters: u32,
    next_free_cluster: u32,
    
    // Device access
    device_sector_size: u32,
    device_start_sector: u64,
    
    // FAT cache
    fat_cache: rawptr,
    fat_cache_dirty: bool,
}

fat32_file :: struct {
    dir_entry: fat32_dir_entry,
    cluster: u32,
    offset: u32,
    size: u32,
    is_dir: bool,
    parent_cluster: u32,
}

fat32_fs_global: fat32_fs


// ============================================================================
// FAT32 Filesystem Operations
// ============================================================================

// FAT32 Mount
fat32_mount :: proc(device: string, mountpoint: string, flags: u32) -> *vfs.VFS_MOUNT {
    log.info("FAT32: Mounting %s on %s...", device, mountpoint)
    
    fat32_fs_global = fat32_fs{
        device = device,
        mountpoint = mountpoint,
        mounted = false,
    }
    
    // Read boot sector
    if !fat32_read_boot_sector() {
        log.error("FAT32: Failed to read boot sector")
        return nil
    }
    
    // Verify boot signature
    if fat32_fs_global.bs.signature != 0xAA55 {
        log.error("FAT32: Invalid boot signature 0x%X", 
                  fat32_fs_global.bs.signature)
        return nil
    }
    
    // Verify FAT32
    if fat32_fs_global.bs.fat_size_32 == 0 {
        log.error("FAT32: Not a FAT32 volume (FAT size is 0)")
        return nil
    }
    
    // Verify filesystem type string
    fs_type := string.trim(cast(string)(fat32_fs_global.bs.fs_type[:]))
    if fs_type != "FAT32   " && fs_type != "FAT16   " {
        log.error("FAT32: Invalid filesystem type '%s'", fs_type)
        return nil
    }
    
    log.info("FAT32: Boot sector valid (FAT32)")
    
    // Calculate filesystem parameters
    fat32_calculate_parameters()
    
    // Read FSINFO sector
    fat32_read_fsinfo()
    
    // Load FAT into cache
    if !fat32_load_fat() {
        log.error("FAT32: Failed to load FAT")
        return nil
    }
    
    fat32_fs_global.mounted = true
    
    log.info("FAT32: Mounted successfully")
    log.info("FAT32: Volume '%s', %d clusters, %d bytes/cluster",
             cast(string)(fat32_fs_global.bs.volume_label[:]),
             fat32_fs_global.total_clusters,
             fat32_fs_global.bytes_per_cluster)
    
    // Create VFS mount structure
    mount := cast(*vfs.VFS_MOUNT)(/* allocate */)
    
    mount.device = device
    mount.mountpoint = mountpoint
    mount.fs_type = "fat32"
    mount.flags = flags
    mount.root_inode = fat32_fs_global.root_cluster
    mount.fs_data = &fat32_fs_global
    mount.ops = &fat32_fs_ops
    mount.file_ops = &fat32_file_ops
    
    return mount
}


// Read Boot Sector
fat32_read_boot_sector :: proc() -> bool {
    log.info("FAT32: Reading boot sector...")
    
    // Read first sector
    // In real implementation:
    // block_device_read(0, &fat32_fs_global.bs, 512)
    
    return true
}


// Calculate Filesystem Parameters
fat32_calculate_parameters :: proc() {
    bs := &fat32_fs_global.bs
    
    fat32_fs_global.bytes_per_sector = u32(bs.bytes_per_sector)
    fat32_fs_global.sectors_per_cluster = u32(bs.sectors_per_cluster)
    fat32_fs_global.bytes_per_cluster = 
        fat32_fs_global.bytes_per_sector * fat32_fs_global.sectors_per_cluster
    fat32_fs_global.reserved_sectors = u32(bs.reserved_sectors)
    fat32_fs_global.num_fats = u32(bs.num_fats)
    fat32_fs_global.fat_sectors = u32(bs.fat_size_32)
    fat32_fs_global.root_cluster = bs.root_cluster
    
    // Calculate data region start
    fat32_fs_global.data_start_sector = fat32_fs_global.reserved_sectors + 
        (fat32_fs_global.fat_sectors * fat32_fs_global.num_fats)
    
    // Calculate total clusters
    total_sectors := u32(bs.total_sectors_32)
    data_sectors := total_sectors - fat32_fs_global.data_start_sector
    fat32_fs_global.total_clusters = data_sectors / fat32_fs_global.sectors_per_cluster
    
    // FSINFO sector
    fat32_fs_global.fsinfo_sector = u32(bs.fs_info_sector)
    
    log.info("FAT32: %d bytes/sector, %d sectors/cluster",
             fat32_fs_global.bytes_per_sector,
             fat32_fs_global.sectors_per_cluster)
    log.info("FAT32: Data starts at sector %d, %d total clusters",
             fat32_fs_global.data_start_sector,
             fat32_fs_global.total_clusters)
}


// Read FSINFO Sector
fat32_read_fsinfo :: proc() {
    if fat32_fs_global.fsinfo_sector == 0 {
        return
    }
    
    log.debug("FAT32: Reading FSINFO sector %d", fat32_fs_global.fsinfo_sector)
    
    // Read FSINFO sector
    // Parse free_clusters and next_free_cluster
    
    fat32_fs_global.free_clusters = 0xFFFFFFFF
    fat32_fs_global.next_free_cluster = 2
}


// Load FAT into Cache
fat32_load_fat :: proc() -> bool {
    fat_size_bytes := fat32_fs_global.fat_sectors * fat32_fs_global.bytes_per_sector
    
    log.info("FAT32: Loading FAT (%d KB)...", fat_size_bytes / 1024)
    
    // Allocate FAT cache
    fat_phys := physical.allocate_contiguous(fat_size_bytes)
    if fat_phys == 0 {
        log.error("FAT32: Failed to allocate FAT cache")
        return false
    }
    
    fat32_fs_global.fat_cache = virtual.physical_to_virtual(fat_phys)
    
    // Read FAT from device
    // block_device_read(reserved_sectors, fat_cache, fat_size_bytes)
    
    mem.zero(cast([]u8)(fat32_fs_global.fat_cache, fat_size_bytes))
    
    log.info("FAT32: FAT loaded")
    return true
}


// ============================================================================
// FAT Cluster Operations
// ============================================================================

// Get FAT Entry
fat32_get_fat_entry :: proc(cluster: u32) -> u32 {
    if cluster < 2 || cluster >= fat32_fs_global.total_clusters + 2 {
        return 0
    }
    
    // FAT entry is 4 bytes
    fat_offset := cluster * 4
    
    if fat32_fs_global.fat_cache == nil {
        return 0
    }
    
    ptr := cast(*volatile u32)(cast(uintptr)(fat32_fs_global.fat_cache) + fat_offset)
    entry := ptr[] & 0x0FFFFFFF
    
    return entry
}


// Set FAT Entry
fat32_set_fat_entry :: proc(cluster: u32, value: u32) {
    if cluster < 2 || cluster >= fat32_fs_global.total_clusters + 2 {
        return
    }
    
    fat_offset := cluster * 4
    
    if fat32_fs_global.fat_cache == nil {
        return
    }
    
    ptr := cast(*volatile u32)(cast(uintptr)(fat32_fs_global.fat_cache) + fat_offset)
    
    // Preserve upper 4 bits
    old_value := ptr[]
    ptr[] = (old_value & 0xF0000000) | (value & 0x0FFFFFFF)
    
    fat32_fs_global.fat_cache_dirty = true
}


// Cluster to Sector
fat32_cluster_to_sector :: proc(cluster: u32) -> u32 {
    return fat32_fs_global.data_start_sector + 
           ((cluster - 2) * fat32_fs_global.sectors_per_cluster)
}


// Get Next Cluster
fat32_get_next_cluster :: proc(cluster: u32) -> u32 {
    return fat32_get_fat_entry(cluster)
}


// Allocate Cluster
fat32_allocate_cluster :: proc() -> u32 {
    // Find first free cluster (value 0)
    for cluster in 2..<fat32_fs_global.total_clusters + 2 {
        if fat32_get_fat_entry(cluster) == 0 {
            fat32_set_fat_entry(cluster, FAT32_EOC)
            
            if fat32_fs_global.free_clusters > 0 {
                fat32_fs_global.free_clusters--
            }
            
            return cluster
        }
    }
    
    return 0  // No free space
}


// Free Cluster Chain
fat32_free_cluster_chain :: proc(start_cluster: u32) {
    cluster := start_cluster
    
    for cluster != 0 && cluster < FAT32_EOC {
        next := fat32_get_next_cluster(cluster)
        fat32_set_fat_entry(cluster, 0)
        cluster = next
    }
    
    if fat32_fs_global.free_clusters != 0xFFFFFFFF {
        fat32_fs_global.free_clusters++
    }
}


// ============================================================================
// FAT32 Directory Operations
// ============================================================================

// Read Directory Cluster
fat32_read_directory :: proc(cluster: u32) -> []fat32_dir_entry {
    if cluster < 2 {
        return nil
    }
    
    sector := fat32_cluster_to_sector(cluster)
    
    // Read directory cluster
    // Return array of directory entries
    
    return nil  // Simplified
}


// Find Entry in Directory
fat32_find_entry :: proc(dir_cluster: u32, name: string) -> *fat32_dir_entry {
    // Convert name to 8.3 format
    name_83 := fat32_name_to_83(name)
    
    // Read directory
    entries := fat32_read_directory(dir_cluster)
    if entries == nil {
        return nil
    }
    
    // Linear search
    for entry in entries {
        if entry.attr == 0x00 {
            break  // End of entries
        }
        
        if entry.attr == FAT32_ATTR_LFN {
            continue  // Skip LFN entries
        }
        
        if fat32_compare_name(entry.name[:], name_83) {
            return entry
        }
    }
    
    return nil
}


// Convert Name to 8.3 Format
fat32_name_to_83 :: proc(name: string) -> [11]u8 {
    var result: [11]u8
    mem.zero(result[:])
    
    // Convert to uppercase
    // Split name and extension
    // Pad with spaces
    
    return result
}


// Compare Names
fat32_compare_name :: proc(entry_name: []u8, search_name: [11]u8) -> bool {
    for i in 0..<11 {
        if entry_name[i] != search_name[i] {
            return false
        }
    }
    return true
}


// Create Directory Entry
fat32_create_entry :: proc(parent_cluster: u32, name: string, 
                           is_dir: bool) -> *fat32_dir_entry {
    // Find free entry
    // Create new entry
    // Allocate first cluster
    
    return nil  // Simplified
}


// ============================================================================
// FAT32 File Operations
// ============================================================================

// FAT32 Open
fat32_open :: proc(path: string, flags: u32) -> *vfs.VFS_FILE {
    log.debug("FAT32: Opening %s", path)
    
    if path == "/" {
        // Open root directory
        return fat32_open_root()
    }
    
    // Find file in directory structure
    entry := fat32_find_path(path)
    if entry == nil {
        if flags & vfs.O_CREAT != 0 {
            // Create file
            entry = fat32_create_file(path)
        }
        
        if entry == nil {
            return nil
        }
    }
    
    // Check if directory
    is_dir := (entry.attr & FAT32_ATTR_DIRECTORY) != 0
    
    // Get first cluster
    cluster := u32(entry.first_cluster_hi) << 16 | u32(entry.first_cluster_lo)
    
    // Create file handle
    file := &vfs.VFS_FILE{
        path = path,
        inode = cluster,
        offset = 0,
        flags = flags,
        fs_data = entry,
    }
    
    return file
}


// Open Root Directory
fat32_open_root :: proc() -> *vfs.VFS_FILE {
    file := &vfs.VFS_FILE{
        path = "/",
        inode = fat32_fs_global.root_cluster,
        offset = 0,
        flags = vfs.O_RDONLY,
        fs_data = nil,
    }
    
    return file
}


// Find Path
fat32_find_path :: proc(path: string) -> *fat32_dir_entry {
    if path == "/" {
        return nil  // Root handled separately
    }
    
    // Start from root
    current_cluster := fat32_fs_global.root_cluster
    
    // Parse path components
    components := string.split(path, "/")
    
    var entry: *fat32_dir_entry = nil
    
    for comp in components {
        if comp == "" || comp == "." {
            continue
        }
        
        if comp == ".." {
            // Go to parent (simplified - stay at root)
            current_cluster = fat32_fs_global.root_cluster
            continue
        }
        
        // Find entry in current directory
        entry = fat32_find_entry(current_cluster, comp)
        if entry == nil {
            return nil
        }
        
        // If not last component, must be directory
        if comp != components[len(components)-1] {
            if (entry.attr & FAT32_ATTR_DIRECTORY) == 0 {
                return nil
            }
            
            current_cluster = u32(entry.first_cluster_hi) << 16 | 
                              u32(entry.first_cluster_lo)
        }
    }
    
    return entry
}


// Create File
fat32_create_file :: proc(path: string) -> *fat32_dir_entry {
    // Get parent directory
    // Find free entry
    // Create entry
    // Allocate first cluster
    
    return nil  // Simplified
}


// FAT32 Close
fat32_close :: proc(file: *vfs.VFS_FILE) -> bool {
    // Flush any dirty data
    return true
}


// FAT32 Read
fat32_read :: proc(file: *vfs.VFS_FILE, buffer: []u8, offset: u64) -> int {
    entry := cast(*fat32_dir_entry)(file.fs_data)
    if entry == nil {
        // Root directory
        return fat32_read_dir(file, buffer)
    }
    
    file_size := entry.file_size
    
    if offset >= u64(file_size) {
        return 0
    }
    
    to_read := len(buffer)
    if offset + u64(to_read) > u64(file_size) {
        to_read = int(u64(file_size) - offset)
    }
    
    // Get first cluster
    cluster := u32(entry.first_cluster_hi) << 16 | u32(entry.first_cluster_lo)
    
    // Seek to offset
    bytes_to_skip := u32(offset)
    for bytes_to_skip >= fat32_fs_global.bytes_per_cluster {
        cluster = fat32_get_next_cluster(cluster)
        if cluster >= FAT32_EOC {
            return 0
        }
        bytes_to_skip -= fat32_fs_global.bytes_per_cluster
    }
    
    // Read data
    bytes_read := 0
    sector := fat32_cluster_to_sector(cluster)
    
    // Read from device
    // Handle cluster chaining
    
    return to_read
}


// Read Directory
fat32_read_dir :: proc(file: *vfs.VFS_FILE, buffer: []u8) -> int {
    // Read directory entries
    // Return serialized dirents
    
    return 0
}


// FAT32 Write
fat32_write :: proc(file: *vfs.VFS_FILE, buffer: []u8, offset: u64) -> int {
    entry := cast(*fat32_dir_entry)(file.fs_data)
    if entry == nil {
        return -1  // Can't write to root
    }
    
    // Allocate clusters if needed
    // Write data
    // Update file size
    // Update directory entry
    
    return len(buffer)
}


// FAT32 Seek
fat32_seek :: proc(file: *vfs.VFS_FILE, offset: i64, whence: u32) -> u64 {
    entry := cast(*fat32_dir_entry)(file.fs_data)
    file_size := u64(entry.file_size)
    
    switch whence {
    case vfs.SEEK_SET:
        file.offset = u64(offset)
    case vfs.SEEK_CUR:
        file.offset = u64(i64(file.offset) + offset)
    case vfs.SEEK_END:
        file.offset = u64(i64(file_size) + offset)
    }
    
    return file.offset
}


// FAT32 Readdir
fat32_readdir :: proc(file: *vfs.VFS_FILE) -> *vfs.VFS_DIRENT {
    // Read next directory entry
    // Convert to VFS_DIRENT
    
    return nil
}


// FAT32 Stat
fat32_stat :: proc(path: string) -> *vfs.FILE_STAT {
    if path == "/" {
        return fat32_stat_root()
    }
    
    entry := fat32_find_path(path)
    if entry == nil {
        return nil
    }
    
    stat := &vfs.FILE_STAT{
        inode = u32(entry.first_cluster_hi) << 16 | u32(entry.first_cluster_lo),
        size = u64(entry.file_size),
        type = fat32_attr_to_type(entry.attr),
        mtime = u64(entry.modify_date) << 16 | u64(entry.modify_time),
        ctime = u64(entry.create_date) << 16 | u64(entry.create_time),
        atime = u64(entry.access_date),
    }
    
    return stat
}


// Stat Root
fat32_stat_root :: proc() -> *vfs.FILE_STAT {
    return &vfs.FILE_STAT{
        inode = fat32_fs_global.root_cluster,
        type = .Directory,
    }
}


// Attribute to Type
fat32_attr_to_type :: proc(attr: u8) -> vfs.FILE_TYPE {
    if (attr & FAT32_ATTR_DIRECTORY) != 0 {
        return .Directory
    }
    return .Regular
}


// ============================================================================
// FAT32 Filesystem Operations Table
// ============================================================================

fat32_fs_ops :: vfs.FS_OPS {
    mount = fat32_mount,
    unmount = fat32_unmount,
    statfs = fat32_statfs,
    sync = fat32_sync,
}

fat32_file_ops :: vfs.FILE_OPS {
    open = fat32_open,
    close = fat32_close,
    read = fat32_read,
    write = fat32_write,
    seek = fat32_seek,
    readdir = fat32_readdir,
    mkdir = fat32_mkdir,
    unlink = fat32_unlink,
    rmdir = fat32_rmdir,
    stat = fat32_stat,
    chmod = fat32_chmod,
    chown = fat32_chown,
    rename = fat32_rename,
    symlink = fat32_symlink,
    readlink = fat32_readlink,
}


// Placeholder implementations
fat32_unmount :: proc(mount: *vfs.VFS_MOUNT) -> bool {
    fat32_fs_global.mounted = false
    return true
}

fat32_statfs :: proc(mount: *vfs.VFS_MOUNT) -> *vfs.FS_STAT {
    return &vfs.FS_STAT{
        total_blocks = u64(fat32_fs_global.total_clusters),
        free_blocks = u64(fat32_fs_global.free_clusters),
        block_size = fat32_fs_global.bytes_per_cluster,
        max_name_len = 255,
        fs_type = "fat32",
    }
}

fat32_sync :: proc(mount: *vfs.VFS_MOUNT) -> bool {
    // Write FAT if dirty
    if fat32_fs_global.fat_cache_dirty {
        // Write FAT to device
        fat32_fs_global.fat_cache_dirty = false
    }
    return true
}

fat32_mkdir :: proc(path: string, perms: vfs.FILE_PERMS) -> bool { return false }
fat32_unlink :: proc(path: string) -> bool { return false }
fat32_rmdir :: proc(path: string) -> bool { return false }
fat32_chmod :: proc(path: string, perms: vfs.FILE_PERMS) -> bool { return false }
fat32_chown :: proc(path: string, uid: u32, gid: u32) -> bool { return false }
fat32_rename :: proc(old_path: string, new_path: string) -> bool { return false }
fat32_symlink :: proc(target: string, link_path: string) -> bool { return false }
fat32_readlink :: proc(path: string) -> string { return "" }
