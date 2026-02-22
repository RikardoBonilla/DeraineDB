use derainedb_rust::Client;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 1. Connect to DeraineDB
    let mut client = Client::connect("http://localhost:50051".into()).await?;
    println!("🚀 Connected to DeraineDB");

    // 2. Insert with metadata_mask
    client.write(1001, vec![1.1, 2.2, 3.3, 4.4], 0x01).await?;
    println!("✅ Vector 1001 inserted with metadata_mask=0x01");

    // 3. Filtered KNN Search
    let results = client.search(vec![1.0, 2.0, 3.0, 4.0], 3, 0x01).await?;
    
    println!("🔍 Search results (filter_mask=0x01):");
    for m in results {
        println!(" - ID: {}, Distance: {}", m.id, m.distance);
    }

    Ok(())
}
