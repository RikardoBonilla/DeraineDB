import * as grpc from '@grpc/grpc-js';
import { DeraineServiceClient } from './generated/deraine_grpc_pb';
import { WriteVectorRequest, SearchKNNRequest, GetEngineStatusRequest } from './generated/deraine_pb';

export class DeraineClient {
    private client: DeraineServiceClient;

    constructor(address: string) {
        this.client = new DeraineServiceClient(
            address,
            grpc.credentials.createInsecure()
        );
    }

    public async write(id: number, data: number[], mask: number): Promise<void> {
        const req = new WriteVectorRequest();
        req.setId(id);
        req.setDataList(data);
        req.setMetadataMask(mask);

        return new Promise((resolve, reject) => {
            this.client.writeVector(req, (err) => {
                if (err) reject(err);
                else resolve();
            });
        });
    }

    public async search(query: number[], k: number, mask: number): Promise<any[]> {
        const req = new SearchKNNRequest();
        req.setQueryList(query);
        req.setK(k);
        req.setFilterMask(mask);

        return new Promise((resolve, reject) => {
            this.client.searchKNN(req, (err, response) => {
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
