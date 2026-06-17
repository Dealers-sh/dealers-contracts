# Dealers NFT — reserve & reveal cast commands (testnet)

# Resolve the current NFT address from the deployment file (or paste it inline).
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
RPC=https://api.testnet.abs.xyz

# === Reserve (owner-only, no payment) ===

# mint N to the owner
cast send $DEALERS_NFT "reserve(uint256)" 1 --rpc-url $RPC --account dealersKeystore

# mint N to a specific recipient
cast send $DEALERS_NFT "reserveTo(uint256,address)" 50 0x8a0C4e96a7456032F647780f0DA82f66C9070418 --rpc-url $RPC --account dealersKeystore

# mint N to each of several recipients
cast send $DEALERS_NFT "reserveToMany(uint256,address[])" 1 "[0x6298949CE2477ea8D059C2637D468B7Ee9Cbb680,0x...]" --rpc-url $RPC --account dealersKeystore

# === Reveal (permissionless; assigns the token's pool art) ===
# Wait REVEAL_DELAY (2) blocks after minting before resolving — resolve reverts TooEarly otherwise.

# reveal one token
cast send $DEALERS_NFT "resolve(uint256)" 52 --rpc-url $RPC --account dealersKeystore

# reveal many in one tx (skips tokens that are already revealed or not yet revealable)
cast send $DEALERS_NFT "resolveMany(uint256[])" "[57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107]" --rpc-url $RPC --account dealersKeystore
