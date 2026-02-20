import grpc
import sys
import time
import os

# grpc_tools generating absolute imports fix
sys.path.insert(0, os.path.abspath('proto'))
import deraine_pb2
import deraine_pb2_grpc

def run():
    print("Initiating Python Client for DeraineDB (gRPC)...")
    
    # Connect
    channel = grpc.insecure_channel('localhost:50051')
    stub = deraine_pb2_grpc.DeraineServiceStub(channel)

    query = [500.0, 501.0, 502.0, 503.0]
    req = deraine_pb2.SearchKNNRequest(query_vector=query, k=3, filter_tag=0)
    
    try:
        stub.SearchKNN(req)
    except Exception as e:
        print("Server not ready or Error: ", e)
        return

    # Benchmark
    start = time.perf_counter()
    response = stub.SearchKNN(req)
    end = time.perf_counter()

    print(f"✅ Search Completed in Python: {(end - start) * 1000:.3f} ms")
    print(f"Results: {len(response.matches)} matches found.")
    for i, match in enumerate(response.matches):
        print(f"  #{i+1} -> ID: {match.id} | Distance: {match.distance:.4f}")

if __name__ == '__main__':
    run()
