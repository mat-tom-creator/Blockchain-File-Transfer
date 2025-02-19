require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("hardhat-contract-sizer");
require("dotenv").config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "0000000000000000000000000000000000000000000000000000000000000000";
const INFURA_API_KEY = process.env.INFURA_API_KEY || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const COINMARKETCAP_API_KEY = process.env.COINMARKETCAP_API_KEY || "";

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      allowUnlimitedContractSize: true
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [PRIVATE_KEY],
      gasMultiplier: 1.2
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [PRIVATE_KEY],
      gasMultiplier: 1.2
    },
    mumbai: {
      url: `https://polygon-mumbai.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [PRIVATE_KEY],
      gasMultiplier: 1.2
    },
    polygon: {
      url: `https://polygon-mainnet.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [PRIVATE_KEY],
      gasMultiplier: 1.2
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [PRIVATE_KEY],
      gasMultiplier: 1.2
    }
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    coinmarketcap: COINMARKETCAP_API_KEY,
    outputFile: "gas-report.txt",
    noColors: true
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 60000
  }
};