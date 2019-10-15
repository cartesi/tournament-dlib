docker build -t cartesi/image-tournament-blockchain-base .

rm -rf blockchain_files
mkdir -p blockchain_files
id=$(docker create cartesi/image-tournament-blockchain-base)
docker cp $id:/opt/cartesi/blockchain_files/wallets.yaml blockchain_files/wallets.yaml
docker rm -v $id
