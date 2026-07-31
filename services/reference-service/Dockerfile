FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/reference-service .

FROM gcr.io/distroless/static-debian12
COPY --from=build /out/reference-service /reference-service
EXPOSE 8080
ENTRYPOINT ["/reference-service"]
