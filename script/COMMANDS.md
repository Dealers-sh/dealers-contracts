# mint for someone
cast send 0x63244621aF369609693b588fe28F0BE3e219D839 "reserveTo(uint256,address)" 1 0x8a0C4e96a7456032F647780f0DA82f66C9070418 --rpc-url https://api.testnet.abs.xyz --account dealersKeystore

# set appUrl on renderer
cast send 0xECD68943649cdd75679f6eba1d426593dC839022 "setAppUrl(string)" "https://dealers.sh" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore