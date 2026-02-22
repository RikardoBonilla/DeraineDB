import grpc
import time
from typing import List, Tuple, Optional

# Assuming protoc generates these in the future, we point to the proto directory for now
# or we would package them inside the lib.
import deraine_pb2
import deraine_pb2_grpc

class DeraineClient:
    """
    Official Python SDK for DeraineDB (v2.0.0).
    The '1.8MB Vector Engine that thinks in Microseconds'.
    """
    
    VERSION = "2.0.0"

    def __init__(self, host: str = "localhost", port: int = 50051):
        self.channel = grpc.insecure_channel(f"{host}:{port}")
        self.stub = deraine_pb2_grpc.DeraineServiceStub(self.channel)

    def write(self, id: int, data: List[float], metadata_mask: int = 0) -> bool:
        """Writes a vector to the engine with a 64-bit metadata mask."""
        try:
            request = deraine_pb2.WriteVectorRequest(
                id=id,
                data=data,
                metadata_mask=metadata_mask
            )
            self.stub.WriteVector(request)
            return True
        except grpc.RpcError as e:
            print(f"Write error: {e}")
            return False

    def search(self, query: List[float], k: int = 3, filter_mask: int = 0) -> List[dict]:
        """Performs a K-Nearest Neighbors search with high-impact metadata filtering."""
        start_time = time.time()
        try:
            request = deraine_pb2.SearchKNNRequest(
                query=query,
                k=k,
                filter_mask=filter_mask
            )
            response = self.stub.SearchKNN(request)
            end_time = time.time()
            
            results = []
            for m in response.matches:
                results.append({
                    "id": m.id,
                    "distance": m.distance,
                    "latency_ms": (end_time - start_time) * 1000
                })
            return results
        except grpc.RpcError as e:
            print(f"Search error: {e}")
            return []

    def get_status(self) -> dict:
        """Retrieves real-time engine health and stats."""
        try:
            response = self.stub.GetEngineStatus(deraine_pb2.GetEngineStatusRequest())
            return {
                "healthy": response.healthy,
                "version": response.version,
                "vector_count": response.vector_count,
                "index_level": response.index_level
            }
        except grpc.RpcError:
            return {"healthy": False}

    def close(self):
        """Closes the gRPC channel."""
        self.channel.close()
