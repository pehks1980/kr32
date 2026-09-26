# Direct-Mapped Cache — How It Works

## The Big Idea

A cache is a small, fast memory that holds recently used data from slow main memory. This one is **direct-mapped**: every memory address maps to **exactly one** cache line. No choices, no searching — just math.

**Parameters:** 16 lines × 16 bytes = 256 bytes total cache. Please remember here is cache b/w cpu and physical memory, so it works on _physical_ read write memory operations (read one byte from physical memory, write one byte to physical memory)

---

## Address Breakdown

Every address is split into three parts:

```
+--------+--------+--------+
|  Tag   | Index  | Offset |
+--------+--------+--------+
```

| Field | Formula | Purpose |
|-------|---------|---------|
| **Offset** | `address % 16` | Which byte inside the line (0–15) |
| **Index** | `(address // 16) % 16` | Which cache line to use (0–15) |
| **Tag** | `address // 256` | Confirms *which* block is stored there |

Main parts of this machinery:

_Cache_ is table consists of copy of memory block 16 lines and each line is 16 bytes long,
all blocks aligned by 256 (_Tags_) 

_Tag_ is memory block of 256 bytes in this case
so address 0-255 has tag 0, 256-511 tag 1 and so on...

_Valid_ is true if its actual memory was read to _Cache_ line

**Example:** Address `4660`
- Offset = 4660 % 16 = **4**
- Index  = (4660 // 16) % 16 = **3**
- Tag    = 4660 // 256 = **18**

→ Goes to **line 3, byte 4**, tagged **18**.

---

## The Three Arrays

```python
self.data  = [bytearray(16) for _ in range(16)]  # the actual bytes
self.tags  = [0] * 16                            # which block in cache in (init its 0 first 256 bytes of memory)
self.valid = [False] * 16                        # has this line been loaded?
```

Think of it like a locker room:
- `data` = what's inside each locker
- `tags` = name sticker on each locker
- `valid` = whether the locker has ever been used

---

## Read Operation

```
1. Compute index, tag, offset from address
2. Is valid[index] True AND tags[index] == tag?
      YES → HIT  → return data[index][offset]
      NO  → MISS → copy 16 bytes from memory into this line
                  set tag and valid
                  return the byte
```

**Why check both `valid` and `tag`?**
- `valid` alone: line might be empty (garbage data)
- `tag` alone: line might hold a *different* block that happens to share the index

Both must agree → real hit.

---

## Write Operation

```
1. Compute index, tag, offset
2. HIT?  → update byte in cache
   MISS? → load the whole line first, then update byte
3. ALWAYS write the byte to main memory too  (write-through)
```

Two policies at play:
- **Write-allocate** → on miss, pull the line into cache before writing
- **Write-through** → every write also goes to main memory, so RAM is never stale

---

## Hit vs Miss — Visualized

```
Address 0    → line 0, tag 0, valid false   → MISS → load block 0 into line 0 ? - not valid(false) data here! 
load block from memory make it valid=true

Address 4    → line 0, tag 0, valid true  → HIT  (same block, valid==true, different offset)
Address 256  → line 0, tag 1   → MISS (tag has chanhed) → load block 1 (tag 1),make valid=true, EVICTS block 0
Address 0    → line 0, tag 0   → MISS again! (tag is 0 here) (conflict miss) go and reread block 0 make it valid..
```

That last line is the classic **direct-mapped weakness**: two blocks fighting for the same line evict each other back and forth.

---

## Why Load the Whole Line on a Miss?

Because of **spatial locality** — if you read byte 4, you'll probably read bytes 5, 6, 7 soon. Loading all 16 bytes at once means those future accesses are hits.

---

## Stats

```python
stats() → {"accesses": N, "hits": H, "misses": M, "hit_rate": %)
```

- `hit_rate = hits / (hits + misses) × 100`
- Higher is better. >90% is great; <50% means thrashing.

---

## The 5 Rules to Remember

1. **One address → one line.** Index decides it, no choice.
2. **Hit = valid bit + matching tag.** Both must be true.
3. **Miss = load the whole 16-byte block.** Not just one byte.
4. **Writes go to cache AND memory.** Write-through keeps RAM fresh.
5. **Conflict misses happen.** Two blocks, same index → they evict each other.