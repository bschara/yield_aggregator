import {
  Account,
  Ed25519PrivateKey,
  UserTransactionResponse,
} from "@aptos-labs/ts-sdk";
import { aptos as sharedClient } from "../indexer/on_chain_listener.js";
import { ExecutionIntent } from "./intent_builder.js";

// strategy_engine::execute_intent is a public fun (not entry), so it cannot
// be called directly from a transaction. The executor submits compiled Move
// scripts that call execute_intent internally.
//
// Generate bytecodes with: cd ../aptos && aptos move compile
// Bytecodes land in: ../aptos/build/yield_aggregator/bytecode_scripts/

import { readFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPTS_DIR = join(__dirname, "../../aptos/build/yield_aggregator/bytecode_scripts");

function loadScript(name: string): Uint8Array | null {
  const path = join(SCRIPTS_DIR, `${name}.mv`);
  if (!existsSync(path)) {
    console.warn(`[executor] script not found: ${path}`);
    console.warn(`[executor] run: cd ../aptos && aptos move compile`);
    return null;
  }
  return readFileSync(path);
}

function loadOperator(): Account {
  const privKey = new Ed25519PrivateKey(process.env.OPERATOR_PRIVATE_KEY!);
  return Account.fromPrivateKey({ privateKey: privKey });
}

export interface ExecutionResult {
  txHash: string;
  success: boolean;
  strategyId: number;
  action: string;
  error?: string;
}

async function submitScript(
  bytecode: Uint8Array,
  functionArguments: unknown[],
  operator: Account
): Promise<string> {
  const txn = await sharedClient.transaction.build.simple({
    sender: operator.accountAddress,
    data: { bytecode, functionArguments },
  });
  const signed = await sharedClient.signAndSubmitTransaction({ signer: operator, transaction: txn });
  const committed = (await sharedClient.waitForTransaction({
    transactionHash: signed.hash,
  })) as UserTransactionResponse;
  if (!committed.success) throw new Error(committed.vm_status);
  return signed.hash;
}

export async function executeIntent(
  intent: ExecutionIntent,
  vaultAddr: string,
  registryAddr: string,
  engineAddr: string
): Promise<ExecutionResult> {
  const actionNames = ["deploy", "recall", "harvest", "exit"] as const;
  const scriptNames = ["deploy_and_bridge", "recall_and_send", "harvest_and_send", "recall_and_send"];
  const actionName = actionNames[intent.action];
  const scriptName = scriptNames[intent.action];

  console.log(
    `[executor] ${actionName} strategy=${intent.strategy_id} amount=${intent.amount} nonce=${intent.nonce}`
  );

  const bytecode = loadScript(scriptName);
  if (!bytecode) {
    return {
      txHash: "",
      success: false,
      strategyId: intent.strategy_id,
      action: actionName,
      error: "bytecode missing — run: cd ../aptos && aptos move compile",
    };
  }

  try {
    const operator = loadOperator();
    const args = [
      engineAddr,
      vaultAddr,
      registryAddr,
      BigInt(intent.strategy_id),
      BigInt(intent.amount),
      BigInt(intent.fee_amount),
      BigInt(intent.nonce),
    ];
    const txHash = await submitScript(bytecode, args, operator);
    console.log(`[executor] tx=${txHash}`);
    return { txHash, success: true, strategyId: intent.strategy_id, action: actionName };
  } catch (err) {
    const error = err instanceof Error ? err.message : String(err);
    console.error(`[executor] failed: ${error}`);
    return { txHash: "", success: false, strategyId: intent.strategy_id, action: actionName, error };
  }
}
