# Swift Basis-Image
FROM swift:5.7 as build

WORKDIR /app
COPY ../../ .
RUN swift build -c release --product MiataruTestApp

# Runtime-Image
FROM swift:5.7-slim
WORKDIR /app
COPY --from=build /app/.build/release/MiataruTestApp ./
CMD ["./MiataruTestApp"] 