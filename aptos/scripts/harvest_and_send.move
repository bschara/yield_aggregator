// Atomically signals a yield harvest from a cross-chain strategy.
//
// Step 1: vault validates the harvest request and emits the HarvestEvent.
//         total_assets is NOT updated here it updates when yield arrives
//         via oft_bridge::lz_receive -> credit_bridge_harvest.
// Step 2: adapter sends the ACTION_HARVEST LayerZero message to Ethereum.
//         Ethereum collects accumulated yield and bridges it back as APT.
//
// fee_amount is the LZ native fee in APT octas.
script {
    use YieldAggregator::yield_vault;
    use YieldAggregator::eth_bridge_adapter;
    use YieldAggregator::strategy_registry;

    fun harvest_and_send(
        operator: signer,
        vault_addr: address,
        registry_addr: address,
        strategy_id: u64,
        fee_amount: u64,
    ) {
        yield_vault::harvest_strategy(
            &operator, vault_addr, registry_addr, strategy_id, fee_amount,
        );
        let adapter_addr = strategy_registry::get_adapter(registry_addr, strategy_id);
        eth_bridge_adapter::send_harvest(&operator, adapter_addr, fee_amount);
    }
}
