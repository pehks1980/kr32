"""Host-side NSFS key/value storage for BMI requests."""

from __future__ import annotations

import base64
import copy
import json
import struct
from pathlib import Path
from time import time


NS_CREATE = 0x01    #Create a new namespace
NS_DELETE = 0x02    #Delete an existing namespace
FILE_CREATE = 0x10  #Create a new file in a namespace
FILE_DELETE = 0x11  #Delete an existing file in a namespace
FILE_APPEND = 0x12  #Append bytes to an existing file in a namespace
DIR_CREATE = 0x20   #Create a new directory in a namespace  
DIR_DELETE = 0x21   #Delete an existing directory in a namespace
NSFS_INDEX = 0x30   #Return active namespace file/dir index

NSFS_CHUNK_SIZE = 1024
NSFS_OK = 0
NSFS_EINVAL = 22
NSFS_ENOENT = 2
NSFS_EEXIST = 17
NSFS_ENOTEMPTY = 39
NSFS_E2BIG = 7
NSFS_TYPE_FILE = 1
NSFS_TYPE_DIR = 2
NSFS_INDEX_MAX_PAYLOAD = 4096 - 12


class NSFSStore:        # class NSFSStore: deal with KV store for NSFS
    """Tiny JSON-backed KV store used by the VM for NSFS debugging."""

    def __init__(self, path="nsfs_store.json"):
        self.path = Path(path)
        self.data = self._load()

    def _load(self):
        if not self.path.exists():
            return {"version": 1, "next_txid": 1, "next_chunk_id": 1, "kv": {}}

        with self.path.open("r", encoding="utf-8") as f:
            data = json.load(f)

        data.setdefault("version", 1)
        data.setdefault("next_txid", 1)
        data.setdefault("next_chunk_id", 1)
        data.setdefault("kv", {})
        return data

    def _flush(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as f:
            json.dump(self.data, f, indent=2, sort_keys=True)
            f.write("\n")
        tmp.replace(self.path)

    def _key(self, namespace, *parts):
        return ":".join(("ns", str(namespace), *map(str, parts)))

    def _txid(self):
        txid = self.data["next_txid"]
        self.data["next_txid"] = txid + 1
        return txid

    def _chunk_id(self):
        chunk_id = self.data["next_chunk_id"]
        self.data["next_chunk_id"] = chunk_id + 1
        return chunk_id

    def _append_log(self, namespace, op, **fields):
        txid = self._txid()
        self.data["kv"][self._key(namespace, "log", txid)] = {
            "op": op,
            "time": time(),
            **fields,
        }
        return txid

    def namespace_exists(self, namespace):
        return self._key(namespace, "meta") in self.data["kv"]

    def _decode_path(self, payload):
        path = payload.decode("utf-8").strip("\x00")
        if not path:
            return None
        if not path.startswith("/"):
            path = "/" + path
        return path

    def _path_key(self, namespace, path):
        return self._key(namespace, "path", path)

    def _chunk_key(self, namespace, chunk_id):
        return self._key(namespace, "chunk", chunk_id)

    def _filever_key(self, namespace, path, version):
        return self._key(namespace, "filever", path, version)

    def _index_entry_type(self, node):
        if node.get("type") == "file":
            return NSFS_TYPE_FILE
        if node.get("type") == "dir":
            return NSFS_TYPE_DIR
        return 0

    def _decode_file_payload(self, payload):
        """Decode path-only or u32 path_len + path + data payloads."""
        if len(payload) >= 4:
            path_len = int.from_bytes(payload[:4], "little")
            if 0 < path_len <= len(payload) - 4:
                raw_path = payload[4:4 + path_len]
                path = self._decode_path(raw_path)
                if path is not None:
                    return path, payload[4 + path_len:]

        path = self._decode_path(payload)
        if path is None:
            return None, b""
        return path, b""

    def _read_chunk(self, namespace, chunk_id):
        node = self.data["kv"].get(self._chunk_key(namespace, chunk_id))
        if node is None:
            return None
        return base64.b64decode(node["data"].encode("ascii"))

    def _put_chunk(self, namespace, data):
        chunk_id = self._chunk_id()
        self.data["kv"][self._chunk_key(namespace, chunk_id)] = {
            "size": len(data),
            "data": base64.b64encode(data).decode("ascii"),
        }
        return chunk_id

    def _put_chunks(self, namespace, data):
        chunk_ids = []
        for offset in range(0, len(data), NSFS_CHUNK_SIZE):
            chunk_ids.append(self._put_chunk(namespace, data[offset:offset + NSFS_CHUNK_SIZE]))
        return chunk_ids

    def _tail_chunk(self, namespace, chunks):
        if not chunks:
            return None, b""
        chunk_id = chunks[-1]
        data = self._read_chunk(namespace, chunk_id)
        if data is None:
            return None, None
        if len(data) >= NSFS_CHUNK_SIZE:
            return None, b""
        return chunk_id, data

    def _save_old_version(self, namespace, path, manifest):
        key = self._filever_key(namespace, path, manifest["version"])
        self.data["kv"][key] = copy.deepcopy(manifest)
        return key
    
    # make a new namespace, if it already exists, return NSFS_EEXIST
    def create_namespace(self, namespace): 
        key = self._key(namespace, "meta")
        if key in self.data["kv"]:
            return NSFS_EEXIST, b""

        txid = self._append_log(namespace, "ns_create")
        self.data["kv"][key] = {
            "env": {},
            "admissions": [],
            "version": 1,
            "checkpoint": None,
            "created_txid": txid,
        }
        self.data["kv"][self._key(namespace, "checkpoint")] = {
            "root": {"type": "dir", "children": {}}
        }
        self._flush()
        return NSFS_OK, b""
    
    # delete a namespace, if it does not exist, return NSFS_ENOENT
    def delete_namespace(self, namespace):
        prefix = self._key(namespace)
        keys = [key for key in self.data["kv"] if key == prefix or key.startswith(prefix + ":")]
        if not keys:
            return NSFS_ENOENT, b""

        for key in keys:
            del self.data["kv"][key]
        self._flush()
        return NSFS_OK, b""
    
    # create a new file in a namespace, if it already exists, return NSFS_EEXIST
    def create_file(self, namespace, payload):
        if not self.namespace_exists(namespace):
            return NSFS_ENOENT, b""
        path, initial_data = self._decode_file_payload(payload)
        if path is None:
            return NSFS_EINVAL, b""

        key = self._path_key(namespace, path)
        node = self.data["kv"].get(key)
        if node is not None and not node.get("deleted", False):
            return NSFS_EEXIST, b""

        chunk_ids = self._put_chunks(namespace, initial_data)
        txid = self._append_log(namespace, "file_create", path=path)
        self.data["kv"][key] = {
            "type": "file",
            "version": 1,
            "size": len(initial_data),
            "chunks": chunk_ids,
            "tail": chunk_ids[-1] if chunk_ids and len(initial_data) % NSFS_CHUNK_SIZE else None,
            "previous": None,
            "deleted": False,
            "created_txid": txid,
            "modified_txid": txid,
        }
        self._flush()
        print(f"[NSFS] create file ns={namespace} path={path} size={len(initial_data)} chunks={len(chunk_ids)} version=1")
        return NSFS_OK, b""

    def append_file(self, namespace, payload):
        if not self.namespace_exists(namespace):
            return NSFS_ENOENT, b""
        path, append_data = self._decode_file_payload(payload)
        if path is None:
            return NSFS_EINVAL, b""

        key = self._path_key(namespace, path)
        manifest = self.data["kv"].get(key)
        if manifest is None or manifest.get("type") != "file" or manifest.get("deleted", False):
            return NSFS_ENOENT, b""

        old_version_key = self._save_old_version(namespace, path, manifest)
        new_manifest = copy.deepcopy(manifest)
        chunks = list(new_manifest.get("chunks", []))
        remaining = append_data
        tail_id, tail_data = self._tail_chunk(namespace, chunks)
        if tail_data is None:
            return NSFS_EINVAL, b""

        reused_tail = False
        if tail_id is not None and remaining:
            space = NSFS_CHUNK_SIZE - len(tail_data)
            merged = tail_data + remaining[:space]
            chunks[-1] = self._put_chunk(namespace, merged)
            remaining = remaining[space:]
            reused_tail = True

        chunks.extend(self._put_chunks(namespace, remaining))
        txid = self._append_log(
            namespace,
            "file_append",
            path=path,
            bytes=len(append_data),
            old_version=manifest["version"],
            new_version=manifest["version"] + 1,
        )
        new_size = manifest["size"] + len(append_data)
        new_manifest.update({
            "version": manifest["version"] + 1,
            "size": new_size,
            "chunks": chunks,
            "tail": chunks[-1] if chunks and new_size % NSFS_CHUNK_SIZE else None,
            "previous": old_version_key,
            "modified_txid": txid,
        })
        self.data["kv"][key] = new_manifest
        self._flush()
        print(
            f"[NSFS] append file ns={namespace} path={path} bytes={len(append_data)} "
            f"size={new_size} chunks={len(chunks)} version={new_manifest['version']} tail_replaced={reused_tail}"
        )
        return NSFS_OK, b""

    # delete a file in a namespace, if it does not exist, return NSFS_ENOENT
    def delete_file(self, namespace, payload):
        if not self.namespace_exists(namespace):
            return NSFS_ENOENT, b""
        path = self._decode_path(payload)
        if path is None:
            return NSFS_EINVAL, b""

        key = self._path_key(namespace, path)
        node = self.data["kv"].get(key)
        if node is None or node.get("type") != "file" or node.get("deleted", False):
            return NSFS_ENOENT, b""

        old_version_key = self._save_old_version(namespace, path, node)
        txid = self._append_log(namespace, "file_delete", path=path, old_version=node["version"])
        tombstone = copy.deepcopy(node)
        tombstone.update({
            "version": node["version"] + 1,
            "deleted": True,
            "previous": old_version_key,
            "modified_txid": txid,
        })
        self.data["kv"][key] = tombstone
        self._flush()
        print(f"[NSFS] delete file ns={namespace} path={path} tombstone_version={tombstone['version']}")
        return NSFS_OK, b""

    # create a new directory in a namespace, if it already exists, return NSFS_EEXIST
    def create_dir(self, namespace, payload):
        if not self.namespace_exists(namespace):
            return NSFS_ENOENT, b""
        path = self._decode_path(payload)
        if path is None:
            return NSFS_EINVAL, b""

        key = self._path_key(namespace, path)
        if key in self.data["kv"]:
            return NSFS_EEXIST, b""

        txid = self._append_log(namespace, "dir_create", path=path)
        self.data["kv"][key] = {
            "type": "dir",
            "children": {},
            "created_txid": txid,
            "modified_txid": txid,
        }
        self._flush()
        return NSFS_OK, b""
    
    # delete a directory in a namespace, if it does not exist, return NSFS_ENOENT
    def delete_dir(self, namespace, payload):
        path = self._decode_path(payload)
        if path is None:
            return NSFS_EINVAL, b""

        key = self._path_key(namespace, path)
        node = self.data["kv"].get(key)
        if node is None or node.get("type") != "dir":
            return NSFS_ENOENT, b""

        child_prefix = key.rstrip("/") + "/"
        if any(other.startswith(child_prefix) for other in self.data["kv"]):
            return NSFS_ENOTEMPTY, b""

        self._append_log(namespace, "dir_delete", path=path)
        del self.data["kv"][key]
        self._flush()
        return NSFS_OK, b""

    def namespace_index(self, namespace):
        if not self.namespace_exists(namespace):
            return NSFS_ENOENT, b""

        prefix = self._key(namespace, "path") + ":"
        entries = []
        for key, node in sorted(self.data["kv"].items()):
            if not key.startswith(prefix):
                continue
            if node.get("deleted", False):
                continue
            entry_type = self._index_entry_type(node)
            if entry_type == 0:
                continue
            path = key[len(prefix):]
            path_bytes = path.encode("utf-8")
            entry = struct.pack(
                "<LLLL",
                entry_type,
                int(node.get("size", 0)),
                int(node.get("version", 1)),
                len(path_bytes),
            )
            entry += path_bytes
            entry += b"\x00" * ((4 - (len(path_bytes) % 4)) % 4)
            entries.append(entry)

        payload = struct.pack("<L", len(entries)) + b"".join(entries)
        if len(payload) > NSFS_INDEX_MAX_PAYLOAD:
            return NSFS_E2BIG, b""

        print(f"[NSFS] index ns={namespace} entries={len(entries)} bytes={len(payload)}")
        return NSFS_OK, payload

    # handle_packet: dispatches the packet to the appropriate handler based on opcode
    # func will add new fetures to NSFS 
    def handle_packet(self, packet):
        opcode = packet["opcode"]
        namespace = packet["namespace"]

        if opcode == NS_CREATE:
            return self.create_namespace(namespace)
        if opcode == NS_DELETE:
            return self.delete_namespace(namespace)
        if opcode == FILE_CREATE:
            return self.create_file(namespace, packet["payload"])
        if opcode == FILE_DELETE:
            return self.delete_file(namespace, packet["payload"])
        if opcode == FILE_APPEND:
            return self.append_file(namespace, packet["payload"])
        if opcode == DIR_CREATE:
            return self.create_dir(namespace, packet["payload"])
        if opcode == DIR_DELETE:
            return self.delete_dir(namespace, packet["payload"])
        if opcode == NSFS_INDEX:
            return self.namespace_index(namespace)

        return NSFS_EINVAL, b""
