package main

import (
	"context"
	"fmt"
	"log"

	derainedb "github.com/RikardoBonilla/DeraineDB/sdk/go"
)

func main() {
	// 1. Connect to DeraineDB
	client, err := derainedb.NewClient("localhost:50051")
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer client.Close()

	// 2. Insert with 64-bit metadata_mask
	ctx := context.Background()
	err = client.WriteVector(ctx, 1001, []float32{1.1, 2.2, 3.3, 4.4}, 0x01)
	if err != nil {
		log.Fatalf("Failed to write: %v", err)
	}
	fmt.Println("✅ Vector 1001 inserted with metadata_mask=0x01")

	// 3. Filtered KNN Search
	results, err := client.SearchKNN(ctx, []float32{1.0, 2.0, 3.0, 4.0}, 3, 0x01)
	if err != nil {
		log.Fatalf("Search failed: %v", err)
	}

	fmt.Printf("🔍 Found %d matches:\n", len(results))
	for _, m := range results {
		fmt.Printf(" - ID: %d, Distance: %f\n", m.ID, m.Distance)
	}
}
