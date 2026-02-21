# DeraineDB JS/TS SDK (v2.0.0)

This SDK requires the gRPC protobuf files to be generated for your environment.

## Setup
1. Install dependencies:
   ```bash
   npm install
   ```

2. Generate Protobuf files:
   Make sure you have `protoc` and the `grpc-tools` installed. Run:
   ```bash
   mkdir -p src/generated
   npx grpc_tools_node_protoc \
     --js_out=import_style=commonjs,binary:src/generated \
     --grpc_out=grpc_js:src/generated \
     --plugin=protoc-gen-grpc=`which grpc_tools_node_protoc_plugin` \
     -I ../../proto ../../proto/deraine.proto
   ```

3. Build:
   ```bash
   npm run build
   ```

## Usage
```typescript
import { DeraineClient } from './src';

const client = new DeraineClient('localhost:50051');
const results = await client.search([1.0, 2.0, 3.0, 4.0], 3, 0x01);
console.log(results);
```
