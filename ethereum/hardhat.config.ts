import { defineConfig } from "hardhat/config";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import * as dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x" + "0".repeat(64);
const RPC_URL_MAINNET = process.env.RPC_URL_MAINNET || "";
const RPC_URL_SEPOLIA = process.env.RPC_URL_SEPOLIA || "";

export default defineConfig({
  plugins: [hardhatEthers],
  solidity: {
    version: "0.8.22",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat:   { type: "edr-simulated" },
    localhost: { type: "http", url: "http://127.0.0.1:8545" },
    ...(RPC_URL_SEPOLIA && { sepolia: { type: "http" as const, url: RPC_URL_SEPOLIA, accounts: [PRIVATE_KEY] } }),
    ...(RPC_URL_MAINNET && { mainnet: { type: "http" as const, url: RPC_URL_MAINNET, accounts: [PRIVATE_KEY] } }),
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
});
