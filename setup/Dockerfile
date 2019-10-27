FROM python:3.7-alpine

# install dockerize, as we need to wait on ganache to be responding
RUN apk add --no-cache openssl jq
ENV DOCKERIZE_VERSION v0.6.1
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# install yaml2json dependency
RUN pip3 install pyyaml
COPY yaml2json /usr/local/bin/

ENV BASE /opt/cartesi

RUN mkdir -p $BASE

WORKDIR $BASE

# Copy scripts to create the dispatcher config
COPY create-config dispatcher-config.jq ./

CMD $BASE/create-config $BASE/blockchain/contracts `cat $BASE/dispatcher/config/account` $BASE/dispatcher/config/config.yaml \
    && touch $BASE/dispatcher/config/config_done

ENTRYPOINT [ "dockerize", \
    "-wait", "file:///opt/cartesi/blockchain/contracts/deploy_done", \
    "-wait", "file:///opt/cartesi/dispatcher/config/keys_done", \
    "-timeout", "120s" ]
