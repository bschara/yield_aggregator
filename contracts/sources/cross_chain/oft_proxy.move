module YieldAggregator::proxy_oft {
    use YieldAggregator::strategy_executor;
    use layerzero_apps::oft;
    use aptos_framework::aptos_coin::AptosCoin;
    use crate::risk::circuit_breaker;

    struct Nonce has key {
        last_nonce: u64,
    }

public entry fun init(admin: &signer);

public entry fun send_apt(
    user: &signer,
    dst_chain_id: u64,
    dst_receiver: vector<u8>,
    amount: u64,
    min_amount: u64,
    native_fee: u64
);


    public entry fun receive_message(msg: CrossChainMessage) acquires Nonce {
        let nonce_store = borrow_global_mut<Nonce>(msg.target_chain);
        assert!(msg.nonce > nonce_store.last_nonce, 1);
        nonce_store.last_nonce = msg.nonce;

        // validate signature, chain IDs, etc.
        // call strategy executor on target chain
    }
}
