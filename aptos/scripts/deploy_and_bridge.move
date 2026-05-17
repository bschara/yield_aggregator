// Atomically deploys capital from the vault to a cross-chain strategy.
//
// Step 1: vault moves APT from its CoinStore to the adapter's CoinStore
//         and updates idle/deployed accounting.
// Step 2: adapter locks APT as LZ collateral and fires the cross-chain message.
//
// If either step fails the whole transaction rolls back vault accounting
// and the bridge send are always consistent.
//
// fee_amount is the LayerZero native fee in APT octas. Use the off-chain
// estimateFees helper to determine the correct value before submitting.
// The operator's account must have enough APT to cover the fee.
script {
    use YieldAggregator::yield_vault;
    use YieldAggregator::eth_bridge_adapter;
    use YieldAggregator::strategy_registry;

    fun deploy_and_bridge(
        operator: signer,
        vault_addr: address,
        registry_addr: address,
        strategy_id: u64,
        amount: u64,
        fee_amount: u64,
    ) {
        yield_vault::deploy_to_strategy(
            &operator, vault_addr, registry_addr, strategy_id, amount, fee_amount,
        );
        let adapter_addr = strategy_registry::get_adapter(registry_addr, strategy_id);
        eth_bridge_adapter::bridge_out(&operator, adapter_addr, amount, fee_amount);
    }
}
