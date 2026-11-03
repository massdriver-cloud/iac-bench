hclast: main.go go.mod go.sum
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o hclast .
	cat main.go go.mod go.sum | sha256sum | cut -d" " -f1 > hclast.sha256
