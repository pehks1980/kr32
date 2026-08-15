"""Host-side NSFS key/value storage for BMI requests."""

from __future__ import annotations

from ast import Delete
import json
from pathlib import Path
from time import time
from xxlimited import new


NS_CREATE = 0x01    #Create a new namespace
NS_DELETE = 0x02    #Delete an existing namespace
FILE_CREATE = 0x10  #Create a new file in a namespace
FILE_DELETE = 0x11  #Delete an existing file in a namespace
DIR_CREATE = 0x20   #Create a new directory in a namespace  
DIR_DELETE = 0x21   #Delete an existing directory in a namespace

NSFS_OK = 0
NSFS_EINVAL = 22
NSFS_ENOENT = 2
NSFS_EEXIST = 17
NSFS_ENOTEMPTY = 39


class NSFSStore:        # class NSFSStore: deal with KV store for NSFS
    """Tiny JSON-backed KV store used by the VM for NSFS debugging."""

    def __init__(self, path="nsfs_store.json"):
        self.path = Path(path)
        self.data = self._load()

    def _load(self):
        if not self.path.exists():
            return {"version": 1, "next_txid": 1, "kv": {}}

        with self.path.open("r", encoding="utf-8") as f:
            data = json.load(f)

        data.setdefault("version", 1)
        data.setdefault("next_txid", 1)
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
        path = self._decode_path(payload)
        if path is None:
            return NSFS_EINVAL, b""

        key = self._path_key(namespace, path)
        if key in self.data["kv"]:
            return NSFS_EEXIST, b""

        txid = self._append_log(namespace, "file_create", path=path)
        self.data["kv"][key] = {
            "type": "file",
            "size": 0,
            "data": "",
            "created_txid": txid,
            "modified_txid": txid,
        }
        self._flush()
        return NSFS_OK, b""

    # delete a file in a namespace, if it does not exist, return NSFS_ENOENT
    def delete_file(self, namespace, payload):
        path = self._decode_path(payload)
        if path is None:
            return NSFS_EINVAL, b""

        key = self._path_key(namespace, path)
        node = self.data["kv"].get(key)
        if node is None or node.get("type") != "file":
            return NSFS_ENOENT, b""

        self._append_log(namespace, "file_delete", path=path)
        del self.data["kv"][key]
        self._flush()
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
        if opcode == DIR_CREATE:
            return self.create_dir(namespace, packet["payload"])
        if opcode == DIR_DELETE:
            return self.delete_dir(namespace, packet["payload"])

        return NSFS_EINVAL, b""
