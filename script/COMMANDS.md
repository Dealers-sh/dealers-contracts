# mint for someone
cast send 0xCa4BC92b565A110952933C90f581A7765415e6Ed "reserveTo(uint256,address)" 1 0x8a0C4e96a7456032F647780f0DA82f66C9070418 --rpc-url https://api.testnet.abs.xyz --account dealersKeystore

# set appUrl on renderer
cast send 0xECD68943649cdd75679f6eba1d426593dC839022 "setAppUrl(string)" "https://dealers.sh" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore

source .env && cast send 0x026fE01BC06Bc56e52cdB77BF0Aba6c119d32583 "reveal()" --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore 

source .env && cast send 0x026fE01BC06Bc56e52cdB77BF0Aba6c119d32583 \
    "setTraitForToken(uint256,uint8,uint8)" 1 2 18 \
    --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore 


 cast send 0x8dC006a61012F1a6f3EAd24eEfaf0e634d0635f4 "authorizeContract(address,bool)" 0xacEB129b6b2928dE29FD21b09D508cEc03D64ffA true --rpc-url https://api.testnet.abs.xyz --account dealersKeystore