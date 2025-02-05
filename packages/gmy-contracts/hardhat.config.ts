import "dotenv/config";
import { HardhatUserConfig } from "hardhat/types";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-deploy";
import "hardhat-contract-sizer";
import "hardhat-dependency-compiler";
import "@nomicfoundation/hardhat-chai-matchers";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.4.18', settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: '0.6.12', settings: {
          optimizer: {
            enabled: true,
            runs: 14,
          },
        },
      },
      {
        version: '0.7.6', settings: {
          optimizer: {
            enabled: true,
            runs: 3000,
          },
        },
      },
      {
        version: '0.8.16', settings: {
          optimizer: {
            enabled: true,
            runs: 250,
          },
        },
      },
    ],
    overrides: {},
  },
  namedAccounts: {
    deployer: 0,
  },
  networks: {
    hardhat: {
      initialBaseFeePerGas: 0, // to fix : https://github.com/sc-forks/solidity-coverage/issues/652, see https://github.com/sc-forks/solidity-coverage/issues/652#issuecomment-896330136
    },
    bartio: {
      url: "https://bartio.rpc.berachain.com",
      accounts: [process.env.PRIVATE_KEY!],
      gas: "auto",
      verify: {
        etherscan: {
          apiKey: "BARTIO_API_KEY",
          apiUrl: "https://api.routescan.io/v2/network/testnet/evm/80084/etherscan",
        },
      },
    },
  },
  paths: {
    sources: "contracts",
  },

  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  mocha: {
    timeout: 0,
  },
  etherscan: {
    apiKey: "?",
  },

};

export default config;
