FROM node:12-alpine as builder

## Install build toolchain, install node deps and compile native add-ons
RUN apk add --no-cache python make g++ git

COPY ./package.json .
COPY ./npm-shrinkwrap.json .

ARG NPM_TOKEN
RUN echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" > ~/.npmrc
RUN npm install

FROM node:12-alpine

# install dockerize, as we need to wait on ganache to be responding
RUN apk add --no-cache openssl
ENV DOCKERIZE_VERSION v0.6.1
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# must create base dir before switching to user node, so its owned by root
WORKDIR /usr/src/app

COPY ./contracts ./contracts
COPY ./migrations ./migrations
COPY ./truffle-config.js .
COPY ./package.json .
COPY ./npm-shrinkwrap.json .

COPY --from=builder node_modules ./node_modules

ENV ETHEREUM_HOST "ganache"
ENV ETHEREUM_PORT "8545"
ENV ETHEREUM_TIMEOUT "10s"

CMD dockerize \
    -wait tcp://${ETHEREUM_HOST}:${ETHEREUM_PORT} \
    -timeout ${ETHEREUM_TIMEOUT} \
    node_modules/.bin/truffle migrate \
    && touch build/contracts/deploy_done
