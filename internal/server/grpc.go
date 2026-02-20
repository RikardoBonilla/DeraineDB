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

	// Convert Go slice to C array
	cData := make([]C.float, len(req.Data))
	for i, v := range req.Data {
		cData[i] = C.float(v)
	}

	res := C.deraine_write_vector(
		s.dbHandle,
		C.uint64_t(req.Id),
		C.uint32_t(req.Tag),
		&cData[0],
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

	cQuery := make([]C.float, len(req.QueryVector))
	for i, v := range req.QueryVector {
		cQuery[i] = C.float(v)
	}

	k := req.K
	if k == 0 {
		k = 3 // default
	}

	outIds := make([]C.uint64_t, k)
	outDists := make([]C.float, k)

	matches := C.deraine_search(
		s.dbHandle,
		&cQuery[0],
		C.uint32_t(len(req.QueryVector)),
		C.uint32_t(req.FilterTag),
		C.uint32_t(k),
		&outIds[0],
		&outDists[0],
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

func (s *DeraineServer) DeleteVector(ctx context.Context, req *pb.DeleteVectorRequest) (*pb.DeleteVectorResponse, error) {
	res := C.deraine_delete_vector(s.dbHandle, C.uint64_t(req.Id))
	if res != 0 {
		return &pb.DeleteVectorResponse{Success: false}, fmt.Errorf("delete failed with code %d", res)
	}
	return &pb.DeleteVectorResponse{Success: true}, nil
}

func (s *DeraineServer) GetStats(ctx context.Context, req *pb.GetStatsRequest) (*pb.GetStatsResponse, error) {
	// Not fully implemented in C yet, mock returning some data
	return &pb.GetStatsResponse{
		VectorCount:      0, // TO-DO: Implement stats via CGO if needed
		MemoryUsageBytes: 0,
	}, nil
}

// Ensure safe reads are tested
func (s *DeraineServer) ReadSafe(id uint64, length uint32) ([]float32, error) {
	outData := make([]C.float, length)
	res := C.deraine_read_vector(s.dbHandle, C.uint64_t(id), &outData[0], C.uint32_t(length))
	if res != 0 {
		return nil, fmt.Errorf("Safe read failed: %d", res)
	}

	goOut := make([]float32, length)
	for i := 0; i < int(length); i++ {
		goOut[i] = float32(outData[i])
	}
	return goOut, nil
}
