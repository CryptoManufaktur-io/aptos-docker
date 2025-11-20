FROM ubuntu AS builder

RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    pkg-config \
    libssl-dev \
    git \
    bash \
    cmake

RUN git clone https://github.com/aptos-labs/aptos-core.git && \
    cd aptos-core && \
    git checkout --track origin/mainnet

WORKDIR /aptos-core

RUN ./scripts/dev_setup.sh
# RUN test -f ./scripts/dev_setup.sh && chmod +x ./scripts/dev_setup.sh

# RUN ./scripts/dev_setup.sh
# ENV PATH="/root/.cargo/bin:${PATH}"

# RUN cargo build

# FROM ubuntu

# COPY --from=builder /root/aptos-core/target/release/aptos /usr/local/bin/aptos
