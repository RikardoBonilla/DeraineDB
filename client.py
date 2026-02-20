import grpc
import time
import sys
import os

# Add proto directory to path
sys.path.append(os.path.join(os.getcwd(), 'proto'))

import deraine_pb2
import deraine_pb2_grpc

def run_filter_test():
    print("🚀 Initiating Sprint 10: Metadata Filter Validation...")
    
    channel = grpc.insecure_channel('localhost:50051')
    stub = deraine_pb2_grpc.DeraineServiceStub(channel)

    # 1. Insert 1000 vectors with partitioned metadata
    # Even IDs = Category A (Bit 0, mask=1)
    # Odd IDs = Category B (Bit 1, mask=2)
    print("Inserting 1000 vectors with partitioned metadata...")
    for i in range(1000):
        mask = 1 if i % 2 == 0 else 2
        vec = [float(i), float(i+1), float(i+2), float(i+3)]
        req = deraine_pb2.WriteVectorRequest(id=i, metadata_mask=mask, data=vec)
        stub.WriteVector(req)

    query = [500.0, 501.0, 502.0, 503.0]
    
    # 2. Search FLAT with Filter A
    print("\n--- [FLAT] Searching Category A (Even IDs only) ---")
    req_a = deraine_pb2.SearchKNNRequest(
        query_vector=query, 
        k=5, 
        filter_mask=1, 
        mode=deraine_pb2.SEARCH_FLAT
    )
    res_a = stub.SearchKNN(req_a)
    for m in res_a.matches:
        print(f"  Match ID: {m.id} | Distance: {m.distance:.4f} | {'PASS' if m.id % 2 == 0 else 'FAIL - WRONG CATEGORY'}")

    # 3. Search HNSW with Filter B
    print("\n--- [HNSW] Searching Category B (Odd IDs only) ---")
    req_b = deraine_pb2.SearchKNNRequest(
        query_vector=query, 
        k=5, 
        filter_mask=2, 
        mode=deraine_pb2.SEARCH_HNSW
    )
    start = time.perf_counter()
    res_b = stub.SearchKNN(req_b)
    end = time.perf_counter()
    
    for m in res_b.matches:
        print(f"  Match ID: {m.id} | Distance: {m.distance:.4f} | {'PASS' if m.id % 2 != 0 else 'FAIL - WRONG CATEGORY'}")
    
    print(f"\nHNSW Filtered Latency: {(end - start) * 1000:.3f} ms")

    # 4. Stress Test: 10k vectors, search with highly selective filter
    print("\nInserting 9000 more vectors with mask=4...")
    for i in range(1001, 10001):
        vec = [float(i), float(i+1), float(i+2), float(i+3)]
        req = deraine_pb2.WriteVectorRequest(id=i, metadata_mask=4, data=vec)
        stub.WriteVector(req)
        if i % 2000 == 0: print(f"  Progress: {i}/10000")

    print("\nSearching Category A in 10k set (Target: IDs < 1000 and even)...")
    req_stress = deraine_pb2.SearchKNNRequest(
        query_vector=query, 
        k=5, 
        filter_mask=1, 
        mode=deraine_pb2.SEARCH_HNSW
    )
    start = time.perf_counter()
    res_stress = stub.SearchKNN(req_stress)
    end = time.perf_counter()
    
    for m in res_stress.matches:
        print(f"  Match ID: {m.id} | Distance: {m.distance:.4f}")
    
    print(f"Stress Latency (10k vectors, filtered): {(end - start) * 1000:.3f} ms")

    print("\n✅ Sprint 10 validation concluded.")

if __name__ == '__main__':
    run_filter_test()
