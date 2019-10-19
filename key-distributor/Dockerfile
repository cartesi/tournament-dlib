FROM alpine

RUN apk add --no-cache openssl jq gawk

ENV DOCKERIZE_VERSION v0.6.1
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# keys file location is /keys/keys
# writes to keys-%d/account and keys-%d/private_key

COPY distribute.sh /distribute.sh
CMD ["dockerize", "-wait", "file:///keys/keys", "/distribute.sh", "/keys/keys"]
