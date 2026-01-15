// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDealerRendererHTML {
  // svg rendering
  function getHTML(string memory svg) external view returns (string memory);
}