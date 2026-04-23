# ZFS Porting Plan for TimelessOS

## Overview
ZFS (Zettabyte Filesystem) is an advanced copy-on-write filesystem with integrated volume management. This document outlines the strategy for porting ZFS to TimelessOS.

## Status: PLANNED

---

## Phase 1: Core Infrastructure (Weeks 1-4)

### 1.1 SPL (Solaris Portability Layer)
ZFS depends on SPL, which provides Solaris kernel APIs. We need to implement compatibility layer:

**Required SPL Components:**
- [ ] Task queues (work queues)
- [ ] Kernel threads (kthread)
- [ ] Mutexes and condition variables
- [ ] Read-write locks (rwl)
- [ ] Reference counting (refcount)
- [ ] List management (list_t)
- [ ] AVL trees (avl_t)
- [ ] Hash tables (hash_table)
- [ ] Bitmap operations
- [ ] Memory allocation (kmem_alloc, kmem_free)
- [ ] VFS compatibility layer

**Implementation Location:**
```
System/timeless-os/kernel/libs/spl/
├── spl.odin              # Main SPL module
├── sync.odin             # Synchronization primitives
├── taskq.odin            # Task queues
├── list.odin             # List implementation
├── avl.odin              # AVL trees
├── refcount.odin         # Reference counting
└── kmem.odin             # Memory allocation
```

### 1.2 ZFS Core Data Structures
**Required Structures:**
- [ ] SPA (Storage Pool Allocator) - top-level pool management
- [ ] DMU (Data Management Unit) - data access layer
- [ ] ZAP (ZFS Attribute Processor) - extensible attributes
- [ ] ARC (Adaptive Replacement Cache) - primary cache
- [ ] L2ARC - secondary cache (SSD)
- [ ] ZIL (ZFS Intent Log) - write logging

---

## Phase 2: Core ZFS Components (Weeks 5-8)

### 2.1 Storage Pool Allocator (SPA)
```odin
spa :: struct {
    name: string,
    guid: u64,
    version: u32,
    state: spa_state,
    root_vdev: *vdev,
    mos_config: *zap_object,
    // ... more fields
}
```

**Tasks:**
- [ ] Pool import/export
- [ ] vdev tree management
- [ ] Pool I/O pipeline
- [ ] Space map management
- [ ] Pool checkpoint

### 2.2 Virtual Devices (vdev)
**vdev Types to Implement:**
- [ ] vdev_disk - raw disk device
- [ ] vdev_mirror - mirror vdev
- [ ] vdev_raidz - RAID-Z (single, double, triple parity)
- [ ] vdev_spare - hot spare
- [ ] vdev_cache - read cache
- [ ] vdev_log - intent log device

**RAID-Z Implementation:**
```odin
raidz_state :: struct {
    data_disks: u32,
    parity_disks: u32,  // 1, 2, or 3
    cols: u32,
    // ... RAID-Z specific state
}
```

### 2.3 Data Management Unit (DMU)
**Tasks:**
- [ ] Object set management
- [ ] Block allocation
- [ ] Block pointer management
- [ ] Compression support
- [ ] Encryption support (optional)
- [ ] Deduplication (optional - very memory intensive)

---

## Phase 3: Filesystem Layer (Weeks 9-12)

### 3.1 ZAP (ZFS Attribute Processor)
**Tasks:**
- [ ] Microzap (small directories)
- [ ] Fatzap (large directories)
- [ ] Attribute management
- [ ] Name lookups

### 3.2 DNLC (Directory Name Lookup Cache)
**Tasks:**
- [ ] Directory entry caching
- [ ] Name hash tables
- [ ] Cache invalidation

### 3.3 ZFS Inodes (znode)
```odin
znode :: struct {
    z_pflags: u64,        // Persistent flags
    z_atime: zfs_time,
    z_mtime: zfs_time,
    z_ctime: zfs_time,
    z_crtime: zfs_time,
    z_uid: u64,
    z_gid: u64,
    z_size: u64,
    z_parent: u64,
    z_links: u64,
    // ... more fields
}
```

### 3.4 VFS Integration
**Tasks:**
- [ ] zfs_vnops - vnode operations
- [ ] zfs_dir - directory operations
- [ ] zfs_znode - inode management
- [ ] Integration with TimelessOS VFS layer

---

## Phase 4: Advanced Features (Weeks 13-16)

### 4.1 ARC (Adaptive Replacement Cache)
```odin
arc_hdr :: struct {
    b_type: arc_buf_type,
    b_state: *arc_state,
    b_dbuf: *dmu_buf,
    b_size: u64,
    // ... more fields
}
```

**Tasks:**
- [ ] ARC header management
- [ ] LRU/MFU lists
- [ ] Ghost lists
- [ ] Adaptive sizing
- [ ] Eviction policies

### 4.2 ZIL (ZFS Intent Log)
**Tasks:**
- [ ] Intent log records
- [ ] Log device management
- [ ] Synchronous write handling
- [ ] Log replay on import

### 4.3 L2ARC (Secondary Cache)
**Tasks:**
- [ ] L2ARC header structures
- [ ] SSD device management
- [ ] Cache population
- [ ] Cache eviction

---

## Phase 5: Testing and Optimization (Weeks 17-20)

### 5.1 Testing
- [ ] Unit tests for SPL
- [ ] Integration tests for ZFS components
- [ ] Pool creation/destruction tests
- [ ] RAID-Z parity tests
- [ ] Snapshot/clone tests
- [ ] Compression tests
- [ ] Recovery tests (power failure simulation)

### 5.2 Performance Optimization
- [ ] I/O scheduler tuning
- [ ] ARC size tuning
- [ ] Compression algorithm selection
- [ ] Prefetch optimization
- [ ] Lock contention reduction

---

## File Structure

```
System/timeless-os/kernel/filesystem/zfs/
├── zfs.odin                    # Main ZFS module
├── spl/                        # Solaris Portability Layer
│   ├── spl.odin
│   ├── sync.odin
│   ├── taskq.odin
│   ├── list.odin
│   ├── avl.odin
│   └── kmem.odin
├── spa/                        # Storage Pool Allocator
│   ├── spa.odin
│   ├── spa_config.odin
│   ├── spa_misc.odin
│   └── space_map.odin
├── vdev/                       # Virtual Devices
│   ├── vdev.odin
│   ├── vdev_disk.odin
│   ├── vdev_mirror.odin
│   ├── vdev_raidz.odin
│   └── vdev_label.odin
├── dmu/                        # Data Management Unit
│   ├── dmu.odin
│   ├── dmu_object.odin
│   ├── dmu_send.odin
│   └── dmu_tx.odin
├── zap/                        # ZFS Attribute Processor
│   ├── zap.odin
│   ├── zap_micro.odin
│   └── zap_leaf.odin
├── arc/                        # Adaptive Replacement Cache
│   ├── arc.odin
│   ├── arc_buf.odin
│   └── l2arc.odin
├── zil/                        # ZFS Intent Log
│   ├── zil.odin
│   └── zilog.odin
├── znode/                      # ZFS Inodes
│   ├── znode.odin
│   ├── zfs_dir.odin
│   └── zfs_znode.odin
├── dsl/                        # Dataset and Snapshot Layer
│   ├── dsl.odin
│   ├── dsl_dataset.odin
│   ├── dsl_dir.odin
│   └── dsl_snap.odin
└── utils/
    ├── zfs_checksum.odin       # Checksums (SHA256, Fletcher4, etc.)
    ├── zfs_compress.odin       # Compression (LZ4, ZSTD, etc.)
    └── zfs_crypto.odin         # Encryption (optional)
```

---

## Key Algorithms

### Checksums
ZFS supports multiple checksum algorithms:
- Fletcher-2 (legacy)
- Fletcher-4 (default)
- SHA-256 (strong)
- xxHash (fast)
- SHA-512 (strongest)
- xxHash64 (fast 64-bit)

### Compression
- LZ4 (default, fast)
- ZSTD (better compression)
- GZIP (levels 1-9)
- LZJB (legacy)

### RAID-Z Parity Calculation
```odin
// RAID-Z parity uses Reed-Solomon-like coding
// For RAID-Z1 (single parity): simple XOR
// For RAID-Z2 (double parity): XOR + multiplication in GF(2^8)
// For RAID-Z3 (triple parity): XOR + two multiplications

raidz_calculate_parity :: proc(data: [][]u8, parity: *[]u8) {
    // Single parity (RAID-Z1)
    for col in 0..<num_data_disks {
        for byte in 0..<block_size {
            parity[0][byte] ^= data[col][byte]
        }
    }
    
    // Double parity (RAID-Z2) - uses Galois Field multiplication
    // Triple parity (RAID-Z3) - additional GF operations
}
```

---

## Integration with TimelessOS VFS

### Mount Point Registration
```odin
// In filesystem/vfs.odin, add:
case "zfs":
    return &zfs_fs_ops, &zfs_file_ops
```

### Kernel Initialization
```odin
// In kernel/main.odin:
import "filesystem:zfs"

// During boot:
zfs.spa_init()
vfs.register_fs("zfs", &zfs_fs_ops, &zfs_file_ops)
```

---

## Known Challenges

### 1. Memory Requirements
- ARC can consume significant RAM
- Minimum recommended: 4GB for basic operation
- Deduplication requires ~5GB RAM per TB of storage

### 2. Licensing
- OpenZFS uses CDDL license
- TimelessOS kernel should verify compatibility
- Consider keeping ZFS as loadable module

### 3. Complexity
- ZFS is ~800K lines of C code
- Full port will take significant time
- Consider starting with read-only support

### 4. Performance
- Copy-on-write can cause fragmentation
- Requires SSD for best performance
- Tuning needed for TimelessOS memory model

---

## Milestones

### Milestone 1: SPL Complete
- All SPL primitives working
- Basic kmem, sync, taskq functional
- **Target:** End of Week 4

### Milestone 2: SPA/vdev Complete
- Pool import/export working
- Single disk vdev functional
- Mirror vdev functional
- **Target:** End of Week 8

### Milestone 3: DMU/ZAP Complete
- Object allocation working
- Directory operations functional
- Basic file I/O working
- **Target:** End of Week 12

### Milestone 4: Full Feature Set
- ARC/L2ARC functional
- ZIL working
- Snapshots/clones working
- Compression working
- **Target:** End of Week 16

### Milestone 5: Production Ready
- All tests passing
- Performance optimized
- Documentation complete
- **Target:** End of Week 20

---

## References

- OpenZFS Source: https://github.com/openzfs/zfs
- ZFS on Linux: https://openzfs.org/wiki/Linux
- Illumos ZFS: https://illumos.org/books/zfs/
- CDDL License: https://opensource.org/licenses/CDDL-1.0

---

## Notes

- Start with read-only implementation for safety
- Test extensively before enabling writes
- Consider porting ZFS tools (zpool, zfs) for management
- Integration with dinit for pool import on boot
