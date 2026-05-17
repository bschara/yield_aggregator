module YieldAggregator::adapter_interface {
    use YieldAggregator::adapter_registry;
    use YieldAggregator::lending_adapter;

    // Vault calls these four functions to interact with strategies.
    //
    // Eth bridge is absent from the dispatch chain it creates a module cycle:
    //   vault -> adapter_interface -> eth_bridge_adapter -> oft_bridge -> message_receiver -> vault
    // For eth bridge, vault::deploy_to_strategy deposits APT to the adapter CoinStore,
    // then the operator calls eth_bridge_adapter::bridge_out (or trigger functions are
    // invoked via a script). Accounting for async strategies is updated by
    // credit_bridge_return / credit_bridge_harvest when funds arrive from Ethereum.
    //
    // Adding a new sync adapter: (1) add type constant in adapter_registry,
    // (2) implement trigger_* functions, (3) add a branch below.

    const ENOT_REGISTERED: u64 = 1;

    public fun deposit(adapter_addr: address, amount: u64, fee_amount: u64) {
        assert!(adapter_registry::is_registered(adapter_addr), ENOT_REGISTERED);
        let t = adapter_registry::get_type(adapter_addr);
        if (t == adapter_registry::type_lending()) {
            lending_adapter::trigger_deposit(adapter_addr, amount, fee_amount)
        };
    }

    public fun withdraw(adapter_addr: address, amount: u64, fee_amount: u64) {
        assert!(adapter_registry::is_registered(adapter_addr), ENOT_REGISTERED);
        let t = adapter_registry::get_type(adapter_addr);
        if (t == adapter_registry::type_lending()) {
            lending_adapter::trigger_withdraw(adapter_addr, amount, fee_amount)
        };
    }

    public fun harvest(adapter_addr: address, fee_amount: u64) {
        assert!(adapter_registry::is_registered(adapter_addr), ENOT_REGISTERED);
        let t = adapter_registry::get_type(adapter_addr);
        if (t == adapter_registry::type_lending()) {
            lending_adapter::trigger_harvest(adapter_addr, fee_amount)
        };
    }

    public fun emergency_exit(adapter_addr: address, fee_amount: u64) {
        assert!(adapter_registry::is_registered(adapter_addr), ENOT_REGISTERED);
        let t = adapter_registry::get_type(adapter_addr);
        if (t == adapter_registry::type_lending()) {
            lending_adapter::trigger_emergency_exit(adapter_addr, fee_amount)
        };
    }
}
