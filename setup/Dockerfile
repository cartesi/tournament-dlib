FROM cartesi/blockchain-config-generator

# install dockerize, as we need to wait on ganache to be responding
USER root
RUN apk add --no-cache openssl
ENV DOCKERIZE_VERSION v0.6.1
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz

ENV BASE /opt/cartesi
RUN mkdir -p $BASE
WORKDIR $BASE

COPY config-template.yaml .

ENV PATH=$PATH:/home/node/.npm-global/bin
CMD blockchain-config-generator -d $BASE/blockchain -i '*' -c DAppMock,MatchInstantiator,MatchManagerInstantiator,RevealMock,VGMock -a `cat $BASE/keys/account` -o $BASE/dispatcher/config/config.yaml -t config-template.yaml -w 120 \
    && touch $BASE/dispatcher/config/config_done

ENTRYPOINT [ "dockerize", \
    "-wait", "file:///opt/cartesi/keys/account", \
    "-timeout", "120s" ]
