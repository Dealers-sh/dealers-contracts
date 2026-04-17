# mint for someone
cast send 0x3d843eD202E16B56BaE5FF344CE4DB9aDfc2BB78 "reserveTo(uint256,address)" 1 0x917a67DE1a4e29d8820E1AeAfd1E7e53F19F2Df7 --rpc-url https://api.testnet.abs.xyz --account dealersKeystore

# set appUrl on renderer
cast send 0xECD68943649cdd75679f6eba1d426593dC839022 "setAppUrl(string)" "https://dealers.sh" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore