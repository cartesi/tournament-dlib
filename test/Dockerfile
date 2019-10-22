FROM jwilder/dockerize

RUN apk add --no-cache jq gawk

CMD ["dockerize", "-wait", "file:///truffle-data/contracts/DAppMock.json", "-timeout", "120s", "find", "/truffle-data"]
