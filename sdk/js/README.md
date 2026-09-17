# DeraineDB JS/TS SDK (v2.0.0)

This SDK generates its gRPC/protobuf client code from `../../proto/deraine.proto`
at build time - you don't need `protoc` installed separately, it's pulled in
via the `grpc-tools` and `ts-protoc-gen` devDependencies.

## Setup
1. Install dependencies:
   ```bash
   npm install
   ```

2. Build (this runs codegen into `src/generated/` and then `tsc`):
   ```bash
   npm run build
   ```

   If you only need to (re)generate the protobuf/gRPC code without a full
   TypeScript build, run `npm run generate`.

## Usage
The server requires an API key on every call (`DERAINE_DB_API_KEY` on the
server side). Pass the same key as the second constructor argument:

```typescript
import { DeraineClient } from './src';

const client = new DeraineClient('localhost:50051', process.env.DERAINE_DB_API_KEY);
const results = await client.search([1.0, 2.0, 3.0, 4.0], 3, 0x01);
console.log(results);
```
