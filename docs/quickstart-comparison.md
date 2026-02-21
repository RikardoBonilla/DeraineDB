# Quickstart Comparison: Multi-Language Search

See how to perform a filtered K-Nearest Neighbors search across the DeraineDB ecosystem. Every SDK is versioned at **v2.0.0** and optimized for its respective environment.

````carousel
```python
# Python SDK (AI/ML workflows)
from derainedb import DeraineClient

client = DeraineClient(host="localhost", port=50051)
results = client.search(
    query=[1.0, 2.0, 3.0, 4.0],
    k=3,
    mask=0x01 # Images Category
)

for m in results:
    print(f"ID: {m['id']}, Dist: {m['distance']}")
```
<!-- slide -->
```go
// Go SDK (Native Orchestration)
import "github.com/ricardo/deraine-db/sdk/go"

client, _ := derainedb.NewClient("localhost:50051")
results, _ := client.SearchKNN(ctx, 
    []float32{1.0, 2.0, 3.0, 4.0}, 
    3, 
    0x01
)

for _, m := range results {
    fmt.Printf("ID: %d, Dist: %f\n", m.ID, m.Distance)
}
```
<!-- slide -->
```rust
// Rust SDK (Zero-Cost Performance)
let mut client = Client::connect("http://localhost:50051".into()).await?;
let results = client.search(
    vec![1.0, 2.0, 3.0, 4.0],
    3,
    0x01
).await?;

for m in results {
    println!("ID: {}, Dist: {}", m.id, m.distance);
}
```
<!-- slide -->
```typescript
// JS/TS SDK (Fullstack/Web)
const client = new DeraineClient("localhost:50051");
const results = await client.search(
    [1.0, 2.0, 3.0, 4.0],
    3,
    0x01
);

results.forEach(m => console.log(m.id, m.distance));
```
````

### Key Observations
- **Versioning:** v2.0.0-stable is required for all clients.
- **Consistency:** The `metadata_mask` (64-bit) is a first-class citizen in every language.
- **Performance:** Local search overhead is sub-millisecond across all SDK wrappers.
