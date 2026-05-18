import {
  Account,
  Ed25519PrivateKey,
  UserTransactionResponse,
} from "@aptos-labs/ts-sdk";
import { aptos as sharedClient } from "../indexer/on_chain_listener.js";
import { ExecutionIntent } from "./intent_builder.js";

const MODULE_ADDR = process.env.APTOS_MODULE_ADDR!;

const ENTRY_FUNCTIONS: Record<string, string> = {
  deploy_and_bridge: `${MODULE_ADDR}::eth_bridge_adapter::deploy_and_bridge_entry`,
  recall_and_send:   `${MODULE_ADDR}::eth_bridge_adapter::recall_and_send_entry`,
  harvest_and_send:  `${MODULE_ADDR}::eth_bridge_adapter::harvest_and_send_entry`,
};

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

async function submitEntryFunction(
  fn: string,
  functionArguments: unknown[],
  operator: Account
): Promise<string> {
  const txn = await sharedClient.transaction.build.simple({
    sender: operator.accountAddress,
    data: { function: fn, functionArguments },
  });
  const signed = await sharedClient.signAndSubmitTransaction({ signer: operator, transaction: txn });
  const committed = (await sharedClient.waitForTransaction({
    transactionHash: signed.hash,
  })) as UserTransactionResponse;
  if (!committed.success) throw new Error(committed.vm_status);
  return signed.hash;
}

// Argument lists must exactly match the Move entry function signatures:
//   deploy_and_bridge_entry(operator, vault_addr, registry_addr, strategy_id, amount, fee_amount)
//   recall_and_send_entry  (operator, vault_addr, registry_addr, strategy_id, amount, fee_amount)
//   harvest_and_send_entry (operator, vault_addr, registry_addr, strategy_id, fee_amount)  ← no amount
function buildFunctionArgs(
  fnKey: string,
  vaultAddr: string,
  registryAddr: string,
  intent: ExecutionIntent
): unknown[] {
  const base = [vaultAddr, registryAddr, BigInt(intent.strategy_id)];
  if (fnKey === "harvest_and_send") {
    return [...base, BigInt(intent.fee_amount)];
  }
  return [...base, BigInt(intent.amount), BigInt(intent.fee_amount)];
}

export async function executeIntent(
  intent: ExecutionIntent,
  vaultAddr: string,
  registryAddr: string,
): Promise<ExecutionResult> {
  const actionNames = ["deploy", "recall", "harvest", "exit"] as const;
  const fnKeys = ["deploy_and_bridge", "recall_and_send", "harvest_and_send", "recall_and_send"];
  const actionName = actionNames[intent.action];
  const fnKey = fnKeys[intent.action];

  console.log(
    `[executor] ${actionName} strategy=${intent.strategy_id} amount=${intent.amount}`
  );

  const fn = ENTRY_FUNCTIONS[fnKey];
  if (!fn) {
    return {
      txHash: "",
      success: false,
      strategyId: intent.strategy_id,
      action: actionName,
      error: `unknown function key: ${fnKey}`,
    };
  }

  try {
    const operator = loadOperator();
    const args = buildFunctionArgs(fnKey, vaultAddr, registryAddr, intent);
    const txHash = await submitEntryFunction(fn, args, operator);
    console.log(`[executor] tx=${txHash}`);
    return { txHash, success: true, strategyId: intent.strategy_id, action: actionName };
  } catch (err) {
    const error = err instanceof Error ? err.message : String(err);
    console.error(`[executor] failed: ${error}`);
    return { txHash: "", success: false, strategyId: intent.strategy_id, action: actionName, error };
  }
}
