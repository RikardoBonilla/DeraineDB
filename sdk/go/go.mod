module github.com/RikardoBonilla/DeraineDB/sdk/go

go 1.25

require (
	github.com/ricardo/deraine-db/api/grpc/pb v0.0.0-00010101000000-000000000000
	google.golang.org/grpc v1.70.0
)

require (
	golang.org/x/net v0.32.0 // indirect
	golang.org/x/sys v0.28.0 // indirect
	golang.org/x/text v0.21.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20241202173237-19429a94021a // indirect
	google.golang.org/protobuf v1.35.2 // indirect
)

replace github.com/ricardo/deraine-db/api/grpc/pb => ../../api/grpc/pb
