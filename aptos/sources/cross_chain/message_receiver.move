module YieldAggregator::message_receiver {
    use aptos_framework::timestamp;
    use YieldAggregator::yield_vault;

    #[event]
    struct CrossChainReceiveEvent has drop, store {
        vault_addr: address,
        amount: u64,
        action: u8,
        strategy_id: u64,
        nonce: u64,
        timestamp: u64,
    }

    const ACTION_HARVEST:  u8 = 3;
    const ACTION_COMPLETE: u8 = 4;

    // Called by oft_bridge::lz_receive after:
    //   1. Trusted remote has been verified.
    //   2. Nonce has been deduplicated (processed_nonces in BridgeState).
    //   3. APT coins have been deposited to vault_addr via coin::deposit.
    //
    // This function only updates vault accounting numbers to reflect the
    // newly deposited coins. It does not touch coins itself.

    public fun handle_incoming(
        vault_addr: address,
        amount: u64,
        action: u8,
        strategy_id: u64,
        nonce: u64,
    ) {
        if (action == ACTION_COMPLETE) {
            // Funds returned from Ethereum (recall or harvest principal).
            // Move amount from deployed to idle in vault accounting.
            yield_vault::credit_bridge_return(vault_addr, strategy_id, amount);
        } else if (action == ACTION_HARVEST) {
            // New yield arrived from Ethereum.
            // Increase total_assets and idle_assets by the yield amount.
            yield_vault::credit_bridge_harvest(vault_addr, amount);
        };
        // ACTION_DEPLOY and ACTION_RECALL are Aptos to Ethereum messages;
        // they never arrive here as incoming messages.

        0x1::event::emit(CrossChainReceiveEvent {
            vault_addr,
            amount,
            action,
            strategy_id,
            nonce,
            timestamp: timestamp::now_microseconds(),
        });
    }
}
