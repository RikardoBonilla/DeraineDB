from derainedb import DeraineClient
import time

def main():
    # 1. Connect to DeraineDB
    client = DeraineClient(host="localhost", port=50051)
    
    # 2. Insert with metadata_mask (e.g. 0x01 for images)
    success = client.write(id=1001, data=[1.1, 2.2, 3.3, 4.4], metadata_mask=0x01)
    if success:
        print("✅ Vector 1001 inserted with metadata_mask=0x01")

    # 3. Filtered KNN Search
    print("🔍 Searching for nearest neighbors (filter_mask=0x01)...")
    results = client.search(query=[1.0, 2.0, 3.0, 4.0], k=3, filter_mask=0x01)
    
    for match in results:
        print(f" - ID: {match['id']}, Dist: {match['distance']:.4f}, Latency: {match['latency_ms']:.2f}ms")

if __name__ == "__main__":
    main()
