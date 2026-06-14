# mint for someone
cast send 0xCa4BC92b565A110952933C90f581A7765415e6Ed "reserveTo(uint256,address)" 1 0x2f4e1B00b40aDe60F69DD0D93c6060144e0690ea --rpc-url https://api.testnet.abs.xyz --account dealersKeystore

# set appUrl on renderer
cast send 0xECD68943649cdd75679f6eba1d426593dC839022 "setAppUrl(string)" "https://dealers.sh" --rpc-url https://api.testnet.abs.xyz --account dealersKeystore

source .env && cast send 0x026fE01BC06Bc56e52cdB77BF0Aba6c119d32583 "reveal()" --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore 

source .env && cast send 0x026fE01BC06Bc56e52cdB77BF0Aba6c119d32583 \
    "setTraitForToken(uint256,uint8,uint8)" 1 2 18 \
    --rpc-url $ABSTRACT_TESTNET_RPC --account dealersKeystore 


 cast send 0x8dC006a61012F1a6f3EAd24eEfaf0e634d0635f4 "authorizeContract(address,bool)" 0xacEB129b6b2928dE29FD21b09D508cEc03D64ffA true --rpc-url https://api.testnet.abs.xyz --account dealersKeystore

 Coffee: 0x917a67DE1a4e29d8820E1AeAfd1E7e53F19F2Df7
 Mason: 0x2f4e1B00b40aDe60F69DD0D93c6060144e0690ea