# NSFS over BMI

NSFS is the writable namespace filesystem backed by the VM-side BMI device.
The current implementation lives in `device/nsfs.py` and persists a JSON
key/value store to `nsfs_store.json` by default.

## Stack Shape

```text
KR32 kernel/VFS
  -> nsfs_* driver routines
  -> bmi_call(opcode, payload, payload_len, namespace)
  -> VM BMIDevice
  -> NSFSStore JSON KV
```

BMI requests are written by KR32 into `BMI_BUF_WRITE`, the doorbell is rung at
`BMI_REG_BASE`, and the VM writes the reply into `BMI_BUF_READ`.

## BMI Opcodes

```text
NS_CREATE    0x01  namespace = R4, payload empty
NS_DELETE    0x02  namespace = R4, payload empty
FILE_CREATE  0x10  namespace = R4, payload = UTF-8 path or file payload
FILE_DELETE  0x11  namespace = R4, payload = UTF-8 path
FILE_APPEND  0x12  namespace = R4, payload = file payload
DIR_CREATE   0x20  namespace = R4, payload = UTF-8 path
DIR_DELETE   0x21  namespace = R4, payload = UTF-8 path
NSFS_INDEX   0x30  namespace = R4, payload empty
```

Status codes follow errno values:

```text
0   OK
2   ENOENT
17  EEXIST
22  EINVAL
39  ENOTEMPTY
```

## File Payload

`FILE_APPEND` uses a binary envelope so file content can be arbitrary bytes:

```text
u32 path_len      little-endian byte length of the path
path bytes        UTF-8 path, no required NUL
file data bytes   bytes to append or initial create data
```

`FILE_CREATE` accepts both this envelope and the older path-only payload. That
keeps the existing kernel calls working while allowing initial file data later.

Example payload for appending `ABC\n` to `etc/crash.txt`:

```text
0D 00 00 00
65 74 63 2F 63 72 61 73 68 2E 74 78 74
41 42 43 0A
```

## Index Payload

`NSFS_INDEX` returns a packed binary table of the latest live namespace state.
The kernel does not receive JSON and does not see old versions or tombstones.

Request:

```text
namespace = R4
payload empty
```

Reply:

```text
u32 entry_count

repeated entry:
  u32 type        1 = file, 2 = dir
  u32 size        file size, 0 for dirs
  u32 version     latest live version
  u32 path_len    UTF-8 path byte length
  path bytes      no required NUL
  padding         zero bytes to align next entry to 4 bytes
```

If the full reply does not fit in the 4 KiB BMI payload area, the host returns
`E2BIG`. A paged index opcode can be added later when namespaces grow.

## KV Layout

Creating namespace `0` creates:

```text
ns:0:meta
ns:0:checkpoint
ns:0:log:<txid>
```

File data is not stored inline in the path record. A file is a latest manifest
that references immutable chunk records.

```text
ns:<ns>:path:<path> -> {
  "type": "file",
  "version": N,
  "size": total_bytes,
  "chunks": [chunk_id, ...],
  "tail": chunk_id | null,
  "previous": "ns:<ns>:filever:<path>:<old_version>" | null,
  "deleted": false,
  "created_txid": txid,
  "modified_txid": txid
}

ns:<ns>:chunk:<chunk_id> -> {
  "size": byte_count,
  "data": base64_bytes
}

ns:<ns>:filever:<path>:<version> -> old manifest snapshot
```

Chunks are currently fixed at `1024` bytes (`NSFS_CHUNK_SIZE`). A 2049-byte file
is represented as:

```text
chunk 1: 1024 bytes
chunk 2: 1024 bytes
chunk 3: 1 byte
```

The manifest points to all three chunks, and `tail` points to chunk 3.

## Append Semantics

Append is versioned and avoids rereading the whole file:

```text
1. Load latest manifest from ns:<ns>:path:<path>.
2. Save that manifest to ns:<ns>:filever:<path>:<version>.
3. If the last chunk is a partial tail, read only that tail.
4. Write a replacement tail chunk with old tail bytes + new append prefix.
5. Write any remaining append bytes as fresh chunks.
6. Publish a new latest manifest with version + 1.
```

Chunks are immutable. When append fills or extends a tail, NSFS writes a new
chunk and updates only the new manifest. Older versions still reference the old
tail chunk.

## Delete Semantics

`FILE_DELETE` is also versioned:

```text
1. Save the current manifest into filever history.
2. Replace the latest path record with a tombstone.
3. Increment the version.
```

The latest path record remains present with `"deleted": true`, while the
previous live version is still reachable through `previous` and `filever`.
Future GC can remove old chunks, old manifests, and tombstones when policy is
defined.

## Boot Demo

`kernelshed.asm` contains `nsfs_bmi_demo`, called during boot and also from
`idle_task` if task 0 runs later.

The demo sequence is:

```text
NS_DELETE    ns=0, payload empty       ; reset prior run
NS_CREATE    ns=0, payload empty
FILE_CREATE  ns=0, payload "etc/crash.txt"
FILE_APPEND  ns=0, payload u32 path_len + "etc/crash.txt" + "ABC\n"
FILE_DELETE  ns=0, payload "etc/crash.txt"
```

Expected VM log:

```text
opcode 2   NS_DELETE
opcode 1   NS_CREATE
opcode 16  FILE_CREATE
opcode 18  FILE_APPEND
opcode 17  FILE_DELETE
opcode 48  NSFS_INDEX
```

Expected NSFS state after the demo:

```text
ns:0:path:/etc/crash.txt      -> deleted tombstone, version 3
ns:0:filever:/etc/crash.txt:1 -> empty file manifest
ns:0:filever:/etc/crash.txt:2 -> live file manifest, size 4
ns:0:chunk:<id>               -> base64("ABC\n")
```

## Kernel Driver Direction

Current low-level helper:

```text
bmi_call(opcode, payload_ptr, payload_len, namespace)
```

Next NSFS driver functions should wrap BMI:

```text
nsfs_create_namespace(ns)
nsfs_delete_namespace(ns)
nsfs_create_file(ns, path_ptr, path_len)
nsfs_append_file(ns, path_ptr, path_len, data_ptr, data_len)
nsfs_delete_file(ns, path_ptr, path_len)
nsfs_create_dir(ns, path_ptr, path_len)
nsfs_delete_dir(ns, path_ptr, path_len)
```

`nsfs_refresh_index(ns)` calls `NSFS_INDEX` and rebuilds the kernel-side cache:

```text
nsfs_index_count
nsfs_index_table:
  u32 type
  u32 size
  u32 version
  u32 path_ptr
  u32 path_len
nsfs_index_path_pool:
  NUL-terminated copied paths for strcmp lookup
```

VFS mapping target:

```text
nsfs_lookup(path)       -> materialize inode from latest non-deleted manifest
nsfs_open(inode, flags) -> normal file object setup after lookup/create
nsfs_read(file, buf, n) -> later FILE_READ or cached chunk reads
nsfs_write(file, buf,n) -> FILE_APPEND for append mode, later overwrite support
nsfs_close(file)        -> no-op until dirty flush exists
nsfs_create(path, mode) -> FILE_CREATE or DIR_CREATE
nsfs_unlink(path)       -> FILE_DELETE
nsfs_mkdir(path, mode)  -> DIR_CREATE
nsfs_rmdir(path)        -> DIR_DELETE
```
