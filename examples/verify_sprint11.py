import grpc
import time
import sys
import os
import shutil

# Add proto directory to path
sys.path.append(os.path.join(os.getcwd(), 'proto'))

import deraine_pb2
import deraine_pb2_grpc

def run_disaster_test():
    print("🚀 Initiating Sprint 11: The Disaster Test...")
    
    channel = grpc.insecure_channel('localhost:50051')
    stub = deraine_pb2_grpc.DeraineServiceStub(channel)

    # 1. Check Engine Status
    print("Checking engine status...")
    status = stub.GetEngineStatus(deraine_pb2.GetEngineStatusRequest())
    print(f"  Healthy: {status.healthy} | Vectors: {status.vector_count} | Max Level: {status.index_level}")

    # 2. Ingest vectors
    print("\nIngesting 5000 vectors...")
    for i in range(5000):
        vec = [float(i), 1.0, 2.0, 3.0]
        stub.WriteVector(deraine_pb2.WriteVectorRequest(id=i, data=vec))
        if i % 1000 == 0: print(f"  Progress: {i}/5000")

    # 3. Trigger Snapshot
    snapshot_path = "backup_sprint11"
    print(f"\nTriggering Snapshot to '{snapshot_path}'...")
    snap_res = stub.CreateSnapshot(deraine_pb2.CreateSnapshotRequest(target_path=snapshot_path))
    if snap_res.success:
        print("✅ Snapshot created successfully.")
    else:
        print(f"❌ Snapshot failed: {snap_res.error_message}")
        return

    # 4. Verify snapshot files exist
    if os.path.exists(f"{snapshot_path}.drb") and os.path.exists(f"{snapshot_path}.dridx"):
        print("✅ Snapshot files confirmed on disk.")
    else:
        print("❌ Snapshot files missing!")
        return

    # 5. DISASTER: Delete original index file
    print("\n🔥 SIMULATING DISASTER: Deleting 'test_hnsw.dridx'...")
    if os.path.exists("test_hnsw.dridx"):
        os.remove("test_hnsw.dridx")
        print("Original index deleted. Server needs to restart to recover (or we can implement live recovery).")
    
    print("\nPlease RESTART the server manually or look at the logs to see the AUTO-HEAL in action.")
    print("Verification script part 1 concluded.")

if __name__ == '__main__':
    run_disaster_test()
