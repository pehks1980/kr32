some new ideas about nsfs /vps

┌─────────────────────────────────────────────────────────────┐
│                    kr32 Kernel Space                        │
├─────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐    │
│  │  VFS System Call Interface (Assembly)              │    │
│  │  - sys_read, sys_write, sys_open, sys_unlink      │    │
│  │  - sys_mount, sys_umount                         │    │
│  └────────────────┬───────────────────────────────────┘    │
│                   │                                         │
│  ┌────────────────▼───────────────────────────────────┐    │
│  │  NSFS Driver (Ring 0)                             │    │
│  │  - namespace management                           │    │
│  │  - transaction log append                         │    │
│  │  - VFS materialization                           │    │
│  │  - compaction & GC                               │    │
│  └────────────────┬───────────────────────────────────┘    │
│                   │                                         │
│  ┌────────────────▼───────────────────────────────────┐    │
│  │  NSFS Storage Layer                               │    │
│  │  - Key-value B-tree in kernel memory              │    │
│  │  - Page cache for namespaces                     │    │
│  │  - Persistent storage interface                   │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘

## BMI opcodes

The VM-side BMI device now backs NSFS with a JSON key/value store at
`nsfs_store.json` by default. `NS_CREATE` with namespace `0` and an empty
payload creates:

```text
ns:0:meta
ns:0:checkpoint
ns:0:log:<txid>
```

Current host driver operations:

```text
NS_CREATE   0x01  namespace = R4, payload empty
NS_DELETE   0x02  namespace = R4, payload empty
FILE_CREATE 0x10  namespace = R4, payload = UTF-8 path
FILE_DELETE 0x11  namespace = R4, payload = UTF-8 path
DIR_CREATE  0x20  namespace = R4, payload = UTF-8 path
DIR_DELETE  0x21  namespace = R4, payload = UTF-8 path
```

Proposed kernel driver functions:

```text
nsfs_create_namespace(ns)
nsfs_delete_namespace(ns)
nsfs_create_file(ns, path_ptr, path_len)
nsfs_delete_file(ns, path_ptr, path_len)
nsfs_create_dir(ns, path_ptr, path_len)
nsfs_delete_dir(ns, path_ptr, path_len)
```

Proposed VFS ops mapping:

```text
nsfs_lookup(path)       -> materialize inode from ns:<ns>:path:<path>
nsfs_open(inode, flags) -> normal file object setup after lookup/create
nsfs_read(file, buf, n) -> later FILE_READ opcode or cached file data
nsfs_write(file, buf,n) -> later FILE_WRITE opcode plus log append
nsfs_close(file)        -> no-op until dirty flush exists
nsfs_create(path, mode) -> FILE_CREATE or DIR_CREATE based on mode
nsfs_unlink(path)       -> FILE_DELETE
nsfs_mkdir(path, mode)  -> DIR_CREATE
nsfs_rmdir(path)        -> DIR_DELETE
```


┌─────────────────────────────────────────────────────────────┐
│                       NSFS (Key-Value DB)                   │
├─────────────────────────────────────────────────────────────┤
│ ns:0:meta       → {env, admissions, version, checkpoint}  │
│ ns:0:log:1      → {op: write, path:/a, data:...}         │
│ ns:0:log:2      → {op: delete, path:/b}                  │
│ ns:0:log:3      → {op: write, path:/c, data:...}         │
│ ns:0:checkpoint → {vfs_state}                             │
│                                                             │
│ ns:1:meta       → {env, admissions, version, checkpoint}  │
│ ns:1:log:100    → {op: write, path:/x, data:...}         │
│ ns:1:log:101    → {op: delete, path:/y}                  │
│ ns:1:checkpoint → {vfs_state}                             │
│                                                             │
│ ns:2:meta       → {env, admissions, version, checkpoint}  │
│ ns:2:log:200    → {op: write, path:/z, data:...}         │
└─────────────────────────────────────────────────────────────┘
