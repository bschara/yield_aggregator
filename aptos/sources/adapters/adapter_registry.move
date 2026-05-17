module YieldAggregator::adapter_registry {
    use std::signer;

    const TYPE_ETH_BRIDGE: u8 = 1;
    const TYPE_LENDING:    u8 = 2;

    const EINVALID_TYPE:       u64 = 1;
    const EALREADY_REGISTERED: u64 = 2;

    struct AdapterMarker has key {
        adapter_type: u8,
        // true for cross-chain adapters: vault recall/harvest accounting updates
        // happen asynchronously via credit_bridge_return / credit_bridge_harvest,
        // not immediately in the same transaction.
        is_async: bool,
    }

    public fun register_adapter(account: &signer, adapter_type: u8, is_async: bool) {
        assert!(adapter_type == TYPE_ETH_BRIDGE || adapter_type == TYPE_LENDING, EINVALID_TYPE);
        assert!(!exists<AdapterMarker>(signer::address_of(account)), EALREADY_REGISTERED);
        move_to(account, AdapterMarker { adapter_type, is_async });
    }

    public fun is_registered(adapter_addr: address): bool {
        exists<AdapterMarker>(adapter_addr)
    }

    public fun get_type(adapter_addr: address): u8 acquires AdapterMarker {
        borrow_global<AdapterMarker>(adapter_addr).adapter_type
    }

    public fun is_async_adapter(adapter_addr: address): bool acquires AdapterMarker {
        borrow_global<AdapterMarker>(adapter_addr).is_async
    }

    public fun type_eth_bridge(): u8 { TYPE_ETH_BRIDGE }
    public fun type_lending(): u8 { TYPE_LENDING }

    #[test_only]
    public fun register_for_test(account: &signer, adapter_type: u8, is_async: bool) {
        move_to(account, AdapterMarker { adapter_type, is_async });
    }
}
