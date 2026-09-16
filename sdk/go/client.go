package derainedb

import (
	"context"
	"time"

	pb "github.com/ricardo/deraine-db/api/grpc/pb"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
)

const Version = "2.0.0"

type SearchMatch struct {
	ID       uint64
	Distance float32
}

type Client struct {
	conn   *grpc.ClientConn
	client pb.DeraineServiceClient
	apiKey string
}

// NewClient connects to a DeraineDB server at addr, authenticating every
// call with apiKey (must match the server's DERAINE_DB_API_KEY).
func NewClient(addr string, apiKey string) (*Client, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	c := &Client{apiKey: apiKey}

	conn, err := grpc.DialContext(ctx, addr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
		grpc.WithUnaryInterceptor(c.authUnaryInterceptor),
	)
	if err != nil {
		return nil, err
	}

	c.conn = conn
	c.client = pb.NewDeraineServiceClient(conn)
	return c, nil
}

func (c *Client) authUnaryInterceptor(ctx context.Context, method string, req, reply interface{}, cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption) error {
	ctx = metadata.AppendToOutgoingContext(ctx, "x-api-key", c.apiKey)
	return invoker(ctx, method, req, reply, cc, opts...)
}

func (c *Client) Close() error {
	return c.conn.Close()
}

func (c *Client) WriteVector(ctx context.Context, id uint64, data []float32, metadata_mask uint64) error {
	_, err := c.client.WriteVector(ctx, &pb.WriteVectorRequest{
		Id:           id,
		Data:         data,
		MetadataMask: metadata_mask,
	})
	return err
}

func (c *Client) SearchKNN(ctx context.Context, query []float32, k int, filter_mask uint64) ([]SearchMatch, error) {
	res, err := c.client.SearchKNN(ctx, &pb.SearchKNNRequest{
		QueryVector: query,
		K:           uint32(k),
		FilterMask:  filter_mask,
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
