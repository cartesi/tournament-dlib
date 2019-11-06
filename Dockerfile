FROM rust:1.38 as build

ENV BASE /opt/cartesi

RUN \
    apt-get update && \
    apt-get install --no-install-recommends -y cmake && \
    rm -rf /var/lib/apt/lists/*

WORKDIR $BASE

COPY ./arbitration-dlib/ $BASE/arbitration-dlib

WORKDIR $BASE/tournament

# Compile dependencies
COPY ./tournament/Cargo.toml ./
COPY ./tournament/Cargo.lock ./
RUN mkdir -p ./src && echo "fn main() { }" > ./src/main.rs
RUN cargo build -j $(nproc) --release

# Compile tournament test
COPY ./tournament/src ./src

RUN cargo install -j $(nproc) --path .

# Runtime image
FROM debian:buster-slim

RUN \
    apt-get update && \
    apt-get install --no-install-recommends -y ca-certificates wget jq gawk && \
    rm -rf /var/lib/apt/lists/*

ENV DOCKERIZE_VERSION v0.6.1
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

WORKDIR /opt/cartesi

# Copy the build artifact from the build stage
COPY --from=build /usr/local/cargo/bin/test .

# Copy dispatcher scripts
COPY ./dispatcher-entrypoint.sh .

CMD dockerize \
    -wait file:///opt/cartesi/keys/keys_done \
    -wait file:///opt/cartesi/dispatcher/config/config_done \
    -wait tcp://ganache:8545 \
    -wait tcp://machine-manager:50051 \
    -wait tcp://logger:50051 \
    -timeout 120s \
    ./dispatcher-entrypoint.sh
