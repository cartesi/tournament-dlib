FROM node:12-alpine

# install dockerize, as we need to wait on ganache to be responding
RUN apk add --no-cache openssl
ENV DOCKERIZE_VERSION v0.6.1
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# install truffle globally
# following best practive for global dependencies
# https://github.com/nodejs/docker-node/blob/master/docs/BestPractices.md#global-npm-dependencies
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV PATH=$PATH:/home/node/.npm-global/bin

RUN apk add --no-cache --virtual .gyp python make g++ \
    && npm install truffle@5.0.35 \
    && apk del .gyp
#RUN npm install -g truffle

ENV BASE /usr/src/app

WORKDIR $BASE
COPY deployer/truffle-config.js $BASE/
COPY ./contracts/ $BASE/contracts
COPY ./migrations/ $BASE/migrations

CMD ["dockerize", "-wait", "tcp://ganache:8545", "truffle", "migrate"]
