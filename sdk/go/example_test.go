package derainedb_test

import (
	"context"
	"fmt"
	"log"

	derainedb "github.com/ricardo/deraine-db/sdk/go"
)

func main() {
	// 1. Initialize v2.0.0 Client
	client, err := derainedb.NewClient("localhost:50051")
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer client.Close()

	fmt.Printf("DeraineDB Go SDK %s Initialized\n", derainedb.Version)

	// 2. Write
	ctx := context.Background()
	err = client.WriteVector(ctx, 42, []float32{1.0, 2.0, 3.0, 4.0}, 0x01)
	if err != nil {
		log.Fatalf("Write failed: %v", err)
	}

	// 3. Search
	results, err := client.SearchKNN(ctx, []float32{1.1, 2.1, 3.1, 4.1}, 1, 0x01)
	if err != nil {
		log.Fatalf("Search failed: %v", err)
	}

	for _, m := range results {
		fmt.Printf("Match ID: %d, Distance: %f\n", m.ID, m.Distance)
	}
}
