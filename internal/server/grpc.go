package server

import (
	"context"
	"fmt"
	"unsafe"

	pb "github.com/ricardo/deraine-db/api/grpc/pb"
)

/*
#cgo CFLAGS: -I../../core/include
#cgo LDFLAGS: -L../../core/zig-out/lib -lcore
#include "deraine_core.h"
#include <stdlib.h>
*/
import "C"

type DeraineServer struct {
	pb.UnimplementedDeraineServiceServer
	dbHandle unsafe.Pointer
}

func NewDeraineServer(handle unsafe.Pointer) *DeraineServer {
	return &DeraineServer{
		dbHandle: handle,
	}
}

func (s *DeraineServer) WriteVector(ctx context.Context, req *pb.WriteVectorRequest) (*pb.WriteVectorResponse, error) {
	if len(req.Data) == 0 {
		return &pb.WriteVectorResponse{Success: false}, fmt.Errorf("vector data cannot be empty")
	}

	res := C.deraine_write_vector(
		s.dbHandle,
		C.uint64_t(req.Id),
		C.uint64_t(req.MetadataMask),
		(*C.float)(unsafe.Pointer(&req.Data[0])),
		C.uint32_t(len(req.Data)),
	)

	if res != 0 {
		return &pb.WriteVectorResponse{Success: false}, fmt.Errorf("write failed with code %d", res)
	}

	return &pb.WriteVectorResponse{Success: true}, nil
}

func (s *DeraineServer) SearchKNN(ctx context.Context, req *pb.SearchKNNRequest) (*pb.SearchKNNResponse, error) {
	if len(req.QueryVector) == 0 {
		return &pb.SearchKNNResponse{}, fmt.Errorf("query vector cannot be empty")
	}

	k := req.K
	if k == 0 {
		k = 3
	}

	outIds := make([]C.uint64_t, k)
	outDists := make([]C.float, k)

	matches := C.deraine_search(
		s.dbHandle,
		(*C.float)(unsafe.Pointer(&req.QueryVector[0])),
		C.uint32_t(len(req.QueryVector)),
		C.uint64_t(req.FilterMask),
		C.uint32_t(k),
		&outIds[0],
		&outDists[0],
		C.int32_t(1),
	)

	if matches < 0 {
		return &pb.SearchKNNResponse{}, fmt.Errorf("search failed with code %d", matches)
	}

	var pbMatches []*pb.Match
	for i := 0; i < int(matches); i++ {
		pbMatches = append(pbMatches, &pb.Match{
			Id:       uint64(outIds[i]),
			Distance: float32(outDists[i]),
		})
	}

	return &pb.SearchKNNResponse{Matches: pbMatches}, nil
}

func (s *DeraineServer) GetEngineStatus(ctx context.Context, req *pb.GetEngineStatusRequest) (*pb.GetEngineStatusResponse, error) {
	var status C.deraine_status_t
	res := C.deraine_get_status(s.dbHandle, &status)
	if res != 0 {
		return &pb.GetEngineStatusResponse{Healthy: false}, fmt.Errorf("failed to get engine status")
	}

	return &pb.GetEngineStatusResponse{
		Healthy:     status.healthy != 0,
		Version:     fmt.Sprintf("v%d.0", status.version),
		VectorCount: uint64(status.vector_count),
		IndexLevel:  int32(status.max_level),
	}, nil
}

func (s *DeraineServer) CreateSnapshot(ctx context.Context, req *pb.CreateSnapshotRequest) (*pb.CreateSnapshotResponse, error) {
	if req.TargetPath == "" {
		return &pb.CreateSnapshotResponse{Success: false, ErrorMessage: "target path cannot be empty"}, nil
	}

	cPath := C.CString(req.TargetPath)
	defer C.free(unsafe.Pointer(cPath))

	res := C.deraine_create_snapshot(s.dbHandle, cPath)
	if res != 0 {
		return &pb.CreateSnapshotResponse{Success: false, ErrorMessage: fmt.Sprintf("snapshot failed with code %d", res)}, nil
	}

	return &pb.CreateSnapshotResponse{Success: true}, nil
}

func (s *DeraineServer) RebuildIndex() error {
	res := C.deraine_rebuild_index(s.dbHandle)
	if res != 0 {
		return fmt.Errorf("rebuild failed with code %d", res)
	}
	return nil
}

func (s *DeraineServer) DeleteVector(ctx context.Context, req *pb.DeleteVectorRequest) (*pb.DeleteVectorResponse, error) {
	res := C.deraine_delete_vector(s.dbHandle, C.uint64_t(req.Id))
	if res != 0 {
		return &pb.DeleteVectorResponse{Success: false}, fmt.Errorf("delete failed with code %d", res)
	}
	return &pb.DeleteVectorResponse{Success: true}, nil
}

func (s *DeraineServer) GetStats(ctx context.Context, req *pb.GetStatsRequest) (*pb.GetStatsResponse, error) {
	return &pb.GetStatsResponse{
		VectorCount:      0,
		MemoryUsageBytes: 0,
	}, nil
}
