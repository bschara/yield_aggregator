import {
  Aptos,
  AptosConfig,
  Network,
  Account,
  Ed25519PrivateKey,
  InputEntryFunctionData,
  CommittedTransactionResponse,
} from "@aptos-labs/ts-sdk";

export function localnetClient(): Aptos {
  return new Aptos(new AptosConfig({ network: Network.LOCAL }));
}

export async function submitAndWait(
  client: Aptos,
  account: Account,
  payload: InputEntryFunctionData,
): Promise<CommittedTransactionResponse> {
  const tx = await client.transaction.build.simple({
    sender: account.accountAddress,
    data: payload,
  });
  const signed = await client.transaction.sign({ signer: account, transaction: tx });
  const res = await client.transaction.submit.simple({
    transaction: tx,
    senderAuthenticator: signed,
  });
  return client.waitForTransaction({ transactionHash: res.hash });
}

// Read vault state via view function
export async function getVaultState(
  client: Aptos,
  moduleAddr: string,
  vaultAddr: string,
): Promise<{ total_assets: bigint; idle_assets: bigint; deployed_assets: bigint }> {
  const [total, idle, deployed] = await client.view({
    payload: {
      function: `${moduleAddr}::yield_vault::get_assets` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [vaultAddr],
    },
  });
  return {
    total_assets: BigInt(total as string),
    idle_assets: BigInt(idle as string),
    deployed_assets: BigInt(deployed as string),
  };
}

// Load an operator account from a private key hex string (for localnet)
export function operatorFromKey(privateKeyHex: string): Account {
  return Account.fromPrivateKey({
    privateKey: new Ed25519PrivateKey(privateKeyHex),
  });
}

// Fund an account from the localnet faucet
export async function fundAccount(
  client: Aptos,
  address: string,
  amount = 100_000_000_000,
): Promise<void> {
  await client.fundAccount({ accountAddress: address, amount });
}
