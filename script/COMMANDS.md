# Dealers NFT — reserve & reveal cast commands (testnet)

# Resolve the current NFT address from the deployment file (or paste it inline).
DEALERS_NFT=$(jq -r .nft script/data/deployments/testnet.json)
RPC=https://api.testnet.abs.xyz

# === Reserve (owner-only, no payment) ===

# mint N to the owner
cast send $DEALERS_NFT "reserve(uint256)" 1 --rpc-url $RPC --account dealersKeystore

# mint N to a specific recipient
cast send $DEALERS_NFT "reserveTo(uint256,address)" 1 0x2f4e1B00b40aDe60F69DD0D93c6060144e0690ea --rpc-url $RPC --account dealersKeystore

# mint N to each of several recipients
cast send $DEALERS_NFT "reserveToMany(uint256,address[])" 1 "[0x6298949CE2477ea8D059C2637D468B7Ee9Cbb680,0x...]" --rpc-url $RPC --account dealersKeystore

# === Reveal (permissionless; assigns the token's pool art) ===
# Wait REVEAL_DELAY (2) blocks after minting before resolving — resolve reverts TooEarly otherwise.

# reveal one token
cast send $DEALERS_NFT "resolve(uint256)" 52 --rpc-url $RPC --account dealersKeystore

# reveal many in one tx (skips tokens that are already revealed or not yet revealable)
cast send $DEALERS_NFT "resolveMany(uint256[])" "[53,54,55,56]" --rpc-url $RPC --account dealersKeystore
