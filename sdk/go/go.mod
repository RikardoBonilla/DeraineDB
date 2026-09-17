module github.com/RikardoBonilla/DeraineDB/sdk/go

go 1.26.0

require (
	github.com/ricardo/deraine-db/api/grpc/pb v0.0.0-00010101000000-000000000000
	google.golang.org/grpc v1.83.2
)

require (
	golang.org/x/net v0.59.0 // indirect
	golang.org/x/sys v0.48.0 // indirect
	golang.org/x/text v0.42.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260911204522-f61a6ca850bd // indirect
	google.golang.org/protobuf v1.36.12 // indirect
)

replace github.com/ricardo/deraine-db/api/grpc/pb => ../../api/grpc/pb
