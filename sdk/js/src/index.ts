import * as grpc from '@grpc/grpc-js';
import { DeraineServiceClient } from './generated/deraine_grpc_pb';
import { WriteVectorRequest, SearchKNNRequest, GetEngineStatusRequest } from './generated/deraine_pb';

export class DeraineClient {
    private client: DeraineServiceClient;
    private metadata: grpc.Metadata;

    // apiKey must match the server's DERAINE_DB_API_KEY.
    constructor(address: string, apiKey?: string) {
        this.client = new DeraineServiceClient(
            address,
            grpc.credentials.createInsecure()
        );
        this.metadata = new grpc.Metadata();
        if (apiKey) {
            this.metadata.set('x-api-key', apiKey);
        }
    }

    public async write(id: number, data: number[], metadata_mask: number): Promise<void> {
        const req = new WriteVectorRequest();
        req.setId(id);
        req.setDataList(data);
        req.setMetadataMask(metadata_mask);

        return new Promise((resolve, reject) => {
            this.client.writeVector(req, this.metadata, (err) => {
                if (err) reject(err);
                else resolve();
            });
        });
    }

    public async search(query: number[], k: number, filter_mask: number): Promise<any[]> {
        const req = new SearchKNNRequest();
        req.setQueryVectorList(query);
        req.setK(k);
        req.setFilterMask(filter_mask);

        return new Promise((resolve, reject) => {
            this.client.searchKNN(req, this.metadata, (err, response) => {
                if (err) reject(err);
                else resolve(response.getMatchesList().map(m => ({
                    id: m.getId(),
                    distance: m.getDistance()
                })));
            });
        });
    }

    public close() {
        this.client.close();
    }
}
