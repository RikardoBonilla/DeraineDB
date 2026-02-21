package derainedb

import (
	"context"
	"time"

	pb "github.com/ricardo/deraine-db/api/grpc/pb"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

const Version = "2.0.0"

type SearchMatch struct {
	ID       uint64
	Distance float32
}

type Client struct {
	conn   *grpc.ClientConn
	client pb.DeraineServiceClient
}

func NewClient(addr string) (*Client, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	conn, err := grpc.DialContext(ctx, addr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	)
	if err != nil {
		return nil, err
	}

	return &Client{
		conn:   conn,
		client: pb.NewDeraineServiceClient(conn),
	}, nil
}

func (c *Client) Close() error {
	return c.conn.Close()
}

func (c *Client) WriteVector(ctx context.Context, id uint64, data []float32, mask uint64) error {
	_, err := c.client.WriteVector(ctx, &pb.WriteVectorRequest{
		Id:           id,
		Data:         data,
		MetadataMask: mask,
	})
	return err
}

func (c *Client) SearchKNN(ctx context.Context, query []float32, k int, mask uint64) ([]SearchMatch, error) {
	res, err := c.client.SearchKNN(ctx, &pb.SearchKNNRequest{
		QueryVector: query,
		K:           uint32(k),
		FilterMask:  mask,
	})
	if err != nil {
		return nil, err
	}

	matches := make([]SearchMatch, len(res.Matches))
	for i, m := range res.Matches {
		matches[i] = SearchMatch{
			ID:       m.Id,
			Distance: m.Distance,
		}
	}
	return matches, nil
}

func (c *Client) GetStatus(ctx context.Context) (bool, string, uint64, int32, error) {
	res, err := c.client.GetEngineStatus(ctx, &pb.GetEngineStatusRequest{})
	if err != nil {
		return false, "", 0, 0, err
	}
	return res.Healthy, res.Version, res.VectorCount, res.IndexLevel, nil
}

func (c *Client) CreateSnapshot(ctx context.Context, targetPath string) (bool, error) {
	res, err := c.client.CreateSnapshot(ctx, &pb.CreateSnapshotRequest{
		TargetPath: targetPath,
	})
	if err != nil {
		return false, err
	}
	return res.Success, nil
}
