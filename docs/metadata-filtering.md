# DeraineDB | 64-bit Metadata Filtering

DeraineDB implements a "Hardware-First" approach to categorical filtering. Instead of post-filtering results or using heavy string-based indexes, we use a 64-bit bitmask that is evaluated *during* the HNSW graph traversal.

## How it works
Every vector in DeraineDB has an associated `uint64` metadata mask. When you query with a `filter_mask`, the engine performs a bitwise `AND` and requires it to be non-zero (an "ANY of these bits" match, not "ALL of these bits"):

`if (vector.mask & query.filter_mask) != 0`

If the condition is met, the vector is evaluated. Otherwise, it is skipped entirely without ever invoking the math engine or SIMD registers.

> **Note:** this is an OR-style match. A vector tagged with *any single bit*
> present in `filter_mask` passes, even if it doesn't have every bit set. If
> you need a strict "must match all of these categories" (AND) filter, that
> would require a code change to `core/src/storage.zig` (`searchLayer`,
> `searchHNSW`, `searchFlat`) - today's implementation doesn't support it.

## Practical Example
Imagine an E-commerce store:
- Bit 0: Product Category (Electronics = 0x01)
- Bit 1: Gender (Men = 0x02)
- Bit 2: Season (Winter = 0x04)

Searching with `filter_mask = 0x02 | 0x04 = 0x06` matches any vector tagged
**Men OR Winter** (or both) - not only items that are both.

## SDK Usage (Python)
```python
# Search specifically for items matching the mask
results = client.search(query=vec, k=5, filter_mask=0x06)
```

## Performance Impact
This "Early Exit" strategy ensures that even if you have millions of vectors, the engine only calculates distances for the relevant subset, maintaining our **< 1ms** latency guarantee.
