import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";
// require('@openzeppelin/hardhat-upgrades'); // Commented out due to dependency conflict

// Abstract Network Configuration
// FileStore Address: 0xFe1411d6864592549AdE050215482e4385dFa0FB (both mainnet and testnet)

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
    abstract: {
      type: "http",
      url: "https://api.mainnet.abs.xyz",
      accounts: [configVariable("ABSTRACT_PRIVATE_KEY")],
      chainId: 2741,
    },
    abstractTestnet: {
      type: "http",
      url: "https://api.testnet.abs.xyz",
      accounts: [configVariable("ABSTRACT_TESTNET_PRIVATE_KEY")],
      chainId: 11124,
    },
  },
};

export default config;
