// Atomically signals a cross-chain recall from the vault.
//
// Step 1: vault validates the recall request and emits the RecallEvent.
//         Accounting is NOT updated here for async adapters it updates
//         when funds arrive back via oft_bridge::lz_receive -> credit_bridge_return.
// Step 2: adapter sends the ACTION_RECALL LayerZero message to Ethereum.
//         Ethereum withdraws from the strategy and bridges APT back.
//
// amount is in APT octas. fee_amount is the LZ native fee in APT octas.
script {
    use YieldAggregator::yield_vault;
    use YieldAggregator::eth_bridge_adapter;
    use YieldAggregator::strategy_registry;

    fun recall_and_send(
        operator: signer,
        vault_addr: address,
        registry_addr: address,
        strategy_id: u64,
        amount: u64,
        fee_amount: u64,
    ) {
        yield_vault::recall_from_strategy(
            &operator, vault_addr, registry_addr, strategy_id, amount, fee_amount,
        );
        let adapter_addr = strategy_registry::get_adapter(registry_addr, strategy_id);
        eth_bridge_adapter::send_recall(&operator, adapter_addr, amount, fee_amount);
    }
}
