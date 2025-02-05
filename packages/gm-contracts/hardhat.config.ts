import "dotenv/config";
import { HardhatUserConfig } from "hardhat/types";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-deploy";
import "hardhat-contract-sizer";
import "hardhat-dependency-compiler";
import "@nomicfoundation/hardhat-chai-matchers";

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  namedAccounts: {
    deployer: {
      hardhat: 0,
      fantom: 0,
      optimisticEthereum: 0,
      polygonMumbai: 0,
      arbitrum: 0,
      tfantom: 0,
      opTest: 0,
      bartio: 0,
    },
  },
  networks: {
    localhost: {
      saveDeployments: false,
      live: false,
    },
    hardhat: {
      saveDeployments: false,
      live: false,
    },

    bartio: {
      url: "https://bartio.rpc.berachain.com",
      accounts: [process.env.PRIVATE_KEY!],
      verify: {
        etherscan: {
          apiKey: "x",
          apiUrl: "https://api.routescan.io/v2/network/testnet/evm/80084/etherscan",
        },
      },
    },
  },
  etherscan: {
    apiKey: process.env.BARTIO_API_KEY,
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  solidity: {
    compilers: [
      {
        version: '0.6.12', settings: {
          optimizer: {
            enabled: true,
            runs: 17,
          },
        },
      },
      {
        version: '0.7.6', settings: {
          optimizer: {
            enabled: true,
            runs: 10000,
          },
        },
      },
      {
        version: '0.8.9', settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.8.16', settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
    overrides: {},
  },
};

export default config;
