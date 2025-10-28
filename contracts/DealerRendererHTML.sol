// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IDealerRendererHTML.sol";
import { IFileStore } from "./IFileStore.sol";

contract DealerRendererHTML is IDealerRendererHTML {

  string public dealerGzipFilename = "src6.min.js.gz";

  IFileStore public fileStore;
  address public deployer;

  constructor() {
    deployer = msg.sender;
    fileStore = IFileStore(0xFe1411d6864592549AdE050215482e4385dFa0FB);
  }

  function setFileStore(address fileStoreAddress) external {
    require(msg.sender == deployer, "Only deployer can set file store");
    fileStore = IFileStore(fileStoreAddress);
  }

  function setDealerGzipFilename(string memory _dealerGzipFilename) external {
      require(msg.sender == deployer, "Only the deployer can set the gzip filename");
      dealerGzipFilename = _dealerGzipFilename;
  }

  function getGzip() public view returns (string memory) {
    return string.concat(
      "<script src=\"data:text/javascript;base64,",
      fileStore.getFile("gunzipScripts-0.0.1.js").read(),
      "\"></script>"
    );
  }

  function getScriptJs() public view returns (string memory) {
    return string.concat(
      "<script type=\"text/javascript+gzip\" src=\"data:text/javascript;base64,",
      fileStore.getFile(dealerGzipFilename).read(),
      "\"></script>"
    );
  }

  function getHTML(string memory svg) external view override returns (string memory) {
    string memory image = string(abi.encodePacked(
      unicode'<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Dealer # 0000</title><style></style>',

      getScriptJs(),
      getGzip(),
      
      unicode'</head><body>',
      svg,
      unicode'</body></html>'
    ));

    return image;
  }
}
