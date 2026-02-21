# DeraineDB | 64-bit Metadata Filtering

DeraineDB implements a "Hardware-First" approach to categorical filtering. Instead of post-filtering results or using heavy string-based indexes, we use a 64-bit bitmask that is evaluated *during* the HNSW graph traversal.

## How it works
Every vector in DeraineDB has an associated `uint64` metadata mask. When you query with a `filter_mask`, the engine performs a bitwise `AND` operation:

`if (vector.mask & query.filter_mask) == query.filter_mask`

If the condition is met, the vector is evaluated. Otherwise, it is skipped entirely without ever invoking the math engine or SIMD registers.

## Practical Example
Imagine an E-commerce store:
- Bit 0: Product Category (Electronics = 0x01)
- Bit 1: Gender (Men = 0x02)
- Bit 2: Season (Winter = 0x04)

To search for **"Winter Clothes for Men"**, your `filter_mask` would be `0x02 | 0x04 = 0x06`. 

## SDK Usage (Python)
```python
# Search specifically for items matching the mask
results = client.search(query=vec, k=5, mask=0x06)
```

## Performance Impact
This "Early Exit" strategy ensures that even if you have millions of vectors, the engine only calculates distances for the relevant subset, maintaining our **< 1ms** latency guarantee.
