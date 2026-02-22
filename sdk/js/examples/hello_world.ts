import { DeraineClient } from '../src';

async function main() {
    // 1. Connect to DeraineDB
    const client = new DeraineClient("localhost:50051");
    console.log("🚀 Connected to DeraineDB");

    try {
        // 2. Insert with metadata_mask
        await client.write(1001, [1.1, 2.2, 3.3, 4.4], 0x01);
        console.log("✅ Vector 1001 inserted with metadata_mask=0x01");

        // 3. Filtered KNN Search
        const results = await client.search([1.0, 2.0, 3.0, 4.0], 3, 0x01);

        console.log("🔍 Search results (filter_mask=0x01):");
        results.forEach(m => {
            console.log(` - ID: ${m.id}, Distance: ${m.distance}`);
        });
    } catch (err) {
        console.error("❌ Error:", err);
    } finally {
        client.close();
    }
}

main();
