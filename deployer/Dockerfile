FROM node:12.13.0-alpine

# install dockerize, as we need to wait on ganache to be responding
RUN apk add --no-cache openssl
ENV DOCKERIZE_VERSION v0.6.1
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# install truffle globally
# following best practive for global dependencies
# https://github.com/nodejs/docker-node/blob/master/docs/BestPractices.md#global-npm-dependencies
USER node
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV PATH=$PATH:/home/node/.npm-global/bin
RUN npm install truffle@5.0.35 -g

ENV BASE /usr/src/app

# must create base dir before switching to user node, so its owned by root
WORKDIR $BASE

COPY deployer/truffle-config.js $BASE/
COPY ./contracts/ $BASE/contracts
COPY ./migrations/ $BASE/migrations

USER root
CMD dockerize \
    -wait tcp://ganache:8545 \
    truffle migrate \
    && touch $BASE/build/contracts/deploy_done