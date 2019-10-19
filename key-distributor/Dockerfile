FROM jwilder/dockerize

RUN apk add --no-cache jq gawk

# keys file location is /keys/keys
# writes to keys-%d/account and keys-%d/private_key

COPY distribute.sh /distribute.sh
CMD ["dockerize", "-wait", "file:///keys/keys", "/distribute.sh", "/keys/keys"]
