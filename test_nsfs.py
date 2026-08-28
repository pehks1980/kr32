#!/usr/bin/env python3
"""Regression tests for chunked NSFS file manifests."""

from tempfile import TemporaryDirectory

from device.nsfs import (
    FILE_APPEND,
    FILE_CREATE,
    FILE_DELETE,
    DIR_CREATE,
    NS_CREATE,
    NSFS_INDEX,
    NSFS_CHUNK_SIZE,
    NSFS_OK,
    NSFSStore,
)


def file_payload(path, data=b""):
    path_bytes = path.encode("utf-8")
    return len(path_bytes).to_bytes(4, "little") + path_bytes + data


def decode_index(payload):
    count = int.from_bytes(payload[:4], "little")
    offset = 4
    entries = []
    for _ in range(count):
        entry_type = int.from_bytes(payload[offset:offset + 4], "little")
        size = int.from_bytes(payload[offset + 4:offset + 8], "little")
        version = int.from_bytes(payload[offset + 8:offset + 12], "little")
        path_len = int.from_bytes(payload[offset + 12:offset + 16], "little")
        offset += 16
        path = payload[offset:offset + path_len].decode("utf-8")
        offset += path_len
        offset += (4 - (path_len % 4)) % 4
        entries.append((entry_type, size, version, path))
    return entries


def main():
    with TemporaryDirectory() as tmpdir:
        store = NSFSStore(f"{tmpdir}/nsfs_store.json")
        assert store.handle_packet({"opcode": NS_CREATE, "namespace": 0, "payload": b"", "flags": 0}) == (NSFS_OK, b"")

        initial = (b"a" * NSFS_CHUNK_SIZE) + (b"b" * NSFS_CHUNK_SIZE) + b"c"
        assert store.handle_packet({
            "opcode": FILE_CREATE,
            "namespace": 0,
            "payload": file_payload("/demo.txt", initial),
            "flags": 0,
        }) == (NSFS_OK, b"")

        key = store._path_key(0, "/demo.txt")
        manifest_v1 = store.data["kv"][key]
        assert manifest_v1["size"] == 2049
        assert manifest_v1["version"] == 1
        assert len(manifest_v1["chunks"]) == 3
        assert store.data["kv"][store._chunk_key(0, manifest_v1["chunks"][0])]["size"] == 1024
        assert store.data["kv"][store._chunk_key(0, manifest_v1["chunks"][1])]["size"] == 1024
        assert store.data["kv"][store._chunk_key(0, manifest_v1["chunks"][2])]["size"] == 1

        assert store.handle_packet({
            "opcode": FILE_APPEND,
            "namespace": 0,
            "payload": file_payload("/demo.txt", b"0123456789"),
            "flags": 0,
        }) == (NSFS_OK, b"")

        manifest_v2 = store.data["kv"][key]
        old_manifest = store.data["kv"][store._filever_key(0, "/demo.txt", 1)]
        assert manifest_v2["version"] == 2
        assert manifest_v2["size"] == 2059
        assert len(manifest_v2["chunks"]) == 3
        assert old_manifest["chunks"][2] != manifest_v2["chunks"][2]
        assert store.data["kv"][store._chunk_key(0, old_manifest["chunks"][2])]["size"] == 1
        assert store.data["kv"][store._chunk_key(0, manifest_v2["chunks"][2])]["size"] == 11

        assert store.handle_packet({
            "opcode": FILE_DELETE,
            "namespace": 0,
            "payload": b"/demo.txt",
            "flags": 0,
        }) == (NSFS_OK, b"")

        tombstone = store.data["kv"][key]
        assert tombstone["deleted"] is True
        assert tombstone["version"] == 3
        assert store._filever_key(0, "/demo.txt", 2) in store.data["kv"]

        assert store.handle_packet({
            "opcode": DIR_CREATE,
            "namespace": 0,
            "payload": b"/live",
            "flags": 0,
        }) == (NSFS_OK, b"")
        assert store.handle_packet({
            "opcode": FILE_CREATE,
            "namespace": 0,
            "payload": file_payload("/live/a.txt", b"xy"),
            "flags": 0,
        }) == (NSFS_OK, b"")

        status, payload = store.handle_packet({
            "opcode": NSFS_INDEX,
            "namespace": 0,
            "payload": b"",
            "flags": 0,
        })
        assert status == NSFS_OK
        assert decode_index(payload) == [
            (2, 0, 1, "/live"),
            (1, 2, 1, "/live/a.txt"),
        ]

    print("NSFS chunk regression test passed")


if __name__ == "__main__":
    main()
