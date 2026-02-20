import grpc
import sys
import time
import os
import random

# grpc_tools generating absolute imports fix
sys.path.insert(0, os.path.abspath('proto'))
import deraine_pb2
import deraine_pb2_grpc

def run_scale_test():
    print("🚀 Initiating HNSW Scale Test (Interoperability Check)...")
    
    channel = grpc.insecure_channel('localhost:50051')
    stub = deraine_pb2_grpc.DeraineServiceStub(channel)

    # 1. Insert 100,000 vectors
    print("Inserting 100,000 vectors...")
    for i in range(100000):
        if i % 10000 == 0: print(f"  Inserted {i} vectors...")
        vec = [float(i), float(i+1), float(i+2), float(i+3)]
        req = deraine_pb2.WriteVectorRequest(id=i, tag=1, data=vec)
        stub.WriteVector(req)

    query = [1000.0, 1001.0, 1002.0, 1003.0]
    
    # 2. Bench Flat Search
    print("\n--- Benchmarking FLAT Search ---")
    req_flat = deraine_pb2.SearchKNNRequest(query_vector=query, k=5, mode=deraine_pb2.SEARCH_FLAT)
    start = time.perf_counter()
    res_flat = stub.SearchKNN(req_flat)
    end = time.perf_counter()
    print(f"Latency: {(end - start) * 1000:.3f} ms | First Match ID: {res_flat.matches[0].id if res_flat.matches else 'N/A'}")

    # 3. Bench HNSW Search
    print("\n--- Benchmarking HNSW Search ---")
    req_hnsw = deraine_pb2.SearchKNNRequest(query_vector=query, k=5, mode=deraine_pb2.SEARCH_HNSW)
    start = time.perf_counter()
    res_hnsw = stub.SearchKNN(req_hnsw)
    end = time.perf_counter()
    print(f"Latency: {(end - start) * 1000:.3f} ms | First Match ID: {res_hnsw.matches[0].id if res_hnsw.matches else 'N/A'}")

    print("\n✅ Scale test concluded.")

if __name__ == '__main__':
    run_scale_test()
