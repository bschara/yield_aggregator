module YieldAggregator::eth_bridge_adapter {
    use std::signer;
    use std::vector;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::timestamp;
    use YieldAggregator::oft_bridge::{Self, BridgeCapability};
    use YieldAggregator::adapter_registry;
    use YieldAggregator::yield_vault;
    use YieldAggregator::strategy_registry;

    const ADAPTER_SEED: vector<u8> = b"EthBridgeAdapter";

    const ACTION_DEPLOY:  u8 = 1;
    const ACTION_RECALL:  u8 = 2;
    const ACTION_HARVEST: u8 = 3;

    const ENOT_OWNER: u64 = 1;

    struct EthAdapter has key {
        owner: address,
        signer_cap: SignerCapability,
        bridge_cap: BridgeCapability,  // authorizes calls to oft_bridge::bridge_out
        vault_addr: address,
        bridge_addr: address,
        dst_chain_id: u64,
        // 32-byte VaultOFT address on Ethereum the LayerZero receiver contract.
        // EthStrategyExecutor is called internally by VaultOFT after LZ delivery.
        dst_vault_oft: vector<u8>,
        strategy_id: u64,
        deployed: u128,
        nonce: u64,
    }

    #[event]
    struct DeployBridgedEvent has drop, store {
        amount: u64,
        nonce: u64,
        timestamp: u64,
    }

    #[event]
    struct RecallSentEvent has drop, store {
        amount: u64,
        nonce: u64,
        timestamp: u64,
    }

    #[event]
    struct HarvestSentEvent has drop, store {
        nonce: u64,
        timestamp: u64,
    }

    public fun init(
        account: &signer,
        vault_addr: address,
        bridge_addr: address,
        dst_chain_id: u64,
        dst_vault_oft: vector<u8>,  // 32-byte VaultOFT address on Ethereum
        strategy_id: u64,
        bridge_cap: BridgeCapability,
    ) {
        let owner = signer::address_of(account);
        let (adapter_signer, signer_cap) = account::create_resource_account(account, ADAPTER_SEED);
        coin::register<AptosCoin>(&adapter_signer);

        move_to(&adapter_signer, EthAdapter {
            owner,
            signer_cap,
            bridge_cap,
            vault_addr,
            bridge_addr,
            dst_chain_id,
            dst_vault_oft,
            strategy_id,
            deployed: 0,
            nonce: 0,
        });

        adapter_registry::register_adapter(&adapter_signer, adapter_registry::type_eth_bridge(), true);
    }

    public fun adapter_address(owner: address): address {
        account::create_resource_address(&owner, ADAPTER_SEED)
    }

    // -----------------------------------------------------------------------
    // Private helpers contain the bridge logic so entry funs can delegate
    // without violating the rule that entry funs cannot call other entry funs.
    // -----------------------------------------------------------------------

    fun inner_bridge_out(account: &signer, state: &mut EthAdapter, amount: u64, fee_amount: u64) {
        state.nonce = state.nonce + 1;
        let nonce = state.nonce;

        let adapter_signer = account::create_signer_with_capability(&state.signer_cap);
        let coins = coin::withdraw<AptosCoin>(&adapter_signer, amount);
        let fee   = coin::withdraw<AptosCoin>(account, fee_amount);

        let payload = oft_bridge::encode_payload(
            ACTION_DEPLOY, amount, state.strategy_id, nonce, state.vault_addr,
        );

        let bridge_addr   = state.bridge_addr;
        let dst_chain_id  = state.dst_chain_id;
        let dst_vault_oft = state.dst_vault_oft;
        oft_bridge::bridge_out(
            &state.bridge_cap, bridge_addr, coins,
            dst_chain_id, dst_vault_oft, payload, fee, vector::empty<u8>(),
        );

        state.deployed = state.deployed + (amount as u128);

        0x1::event::emit(DeployBridgedEvent { amount, nonce, timestamp: timestamp::now_microseconds() });
    }

    fun inner_send_recall(account: &signer, state: &mut EthAdapter, amount: u64, fee_amount: u64) {
        state.nonce = state.nonce + 1;
        let nonce = state.nonce;
        let fee = coin::withdraw<AptosCoin>(account, fee_amount);

        let payload = oft_bridge::encode_payload(
            ACTION_RECALL, amount, state.strategy_id, nonce, state.vault_addr,
        );

        let bridge_addr   = state.bridge_addr;
        let dst_chain_id  = state.dst_chain_id;
        let dst_vault_oft = state.dst_vault_oft;
        oft_bridge::bridge_out(
            &state.bridge_cap, bridge_addr, coin::zero<AptosCoin>(),
            dst_chain_id, dst_vault_oft, payload, fee, vector::empty<u8>(),
        );

        0x1::event::emit(RecallSentEvent { amount, nonce, timestamp: timestamp::now_microseconds() });
    }

    fun inner_send_harvest(account: &signer, state: &mut EthAdapter, fee_amount: u64) {
        state.nonce = state.nonce + 1;
        let nonce = state.nonce;
        let fee = coin::withdraw<AptosCoin>(account, fee_amount);

        let payload = oft_bridge::encode_payload(
            ACTION_HARVEST, 0, state.strategy_id, nonce, state.vault_addr,
        );

        let bridge_addr   = state.bridge_addr;
        let dst_chain_id  = state.dst_chain_id;
        let dst_vault_oft = state.dst_vault_oft;
        oft_bridge::bridge_out(
            &state.bridge_cap, bridge_addr, coin::zero<AptosCoin>(),
            dst_chain_id, dst_vault_oft, payload, fee, vector::empty<u8>(),
        );

        0x1::event::emit(HarvestSentEvent { nonce, timestamp: timestamp::now_microseconds() });
    }

    // -----------------------------------------------------------------------
    // Single-step entry points (bridge only vault accounting done separately)
    // -----------------------------------------------------------------------

    // Manual operator entry point: use when you want explicit control over bridging
    // rather than relying on the combined entry functions below.
    // Fee is withdrawn from caller's account; APT must already be in adapter CoinStore.
    public entry fun bridge_out(
        account: &signer,
        adapter_addr: address,
        amount: u64,
        fee_amount: u64,
    ) acquires EthAdapter {
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);
        inner_bridge_out(account, state, amount, fee_amount);
    }

    // Signal Ethereum to withdraw `amount` and send it back.
    public entry fun send_recall(
        account: &signer,
        adapter_addr: address,
        amount: u64,
        fee_amount: u64,
    ) acquires EthAdapter {
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);
        inner_send_recall(account, state, amount, fee_amount);
    }

    // Signal Ethereum to collect yield and send it back.
    public entry fun send_harvest(
        account: &signer,
        adapter_addr: address,
        fee_amount: u64,
    ) acquires EthAdapter {
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);
        inner_send_harvest(account, state, fee_amount);
    }

    // -----------------------------------------------------------------------
    // Combined entry points vault accounting + bridge in one transaction.
    // These replace the Move scripts (deploy_and_bridge.move etc.) and are
    // called directly by the offchain executor via function name.
    // -----------------------------------------------------------------------

    public entry fun deploy_and_bridge_entry(
        account: &signer,
        vault_addr: address,
        registry_addr: address,
        strategy_id: u64,
        amount: u64,
        fee_amount: u64,
    ) acquires EthAdapter {
        yield_vault::deploy_to_strategy(account, vault_addr, registry_addr, strategy_id, amount, fee_amount);
        let adapter_addr = strategy_registry::get_adapter(registry_addr, strategy_id);
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);
        inner_bridge_out(account, state, amount, fee_amount);
    }

    public entry fun recall_and_send_entry(
        account: &signer,
        vault_addr: address,
        registry_addr: address,
        strategy_id: u64,
        amount: u64,
        fee_amount: u64,
    ) acquires EthAdapter {
        yield_vault::recall_from_strategy(account, vault_addr, registry_addr, strategy_id, amount, fee_amount);
        let adapter_addr = strategy_registry::get_adapter(registry_addr, strategy_id);
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);
        inner_send_recall(account, state, amount, fee_amount);
    }

    public entry fun harvest_and_send_entry(
        account: &signer,
        vault_addr: address,
        registry_addr: address,
        strategy_id: u64,
        fee_amount: u64,
    ) acquires EthAdapter {
        yield_vault::harvest_strategy(account, vault_addr, registry_addr, strategy_id, fee_amount);
        let adapter_addr = strategy_registry::get_adapter(registry_addr, strategy_id);
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);
        inner_send_harvest(account, state, fee_amount);
    }

    public fun trigger_emergency_exit(_adapter_addr: address, _fee_amount: u64) {}

    #[test_only]
    public fun get_deployed(adapter_addr: address): u128 acquires EthAdapter {
        borrow_global<EthAdapter>(adapter_addr).deployed
    }

    #[test_only]
    public fun get_nonce(adapter_addr: address): u64 acquires EthAdapter {
        borrow_global<EthAdapter>(adapter_addr).nonce
    }

    #[test_only]
    public fun get_vault_addr(adapter_addr: address): address acquires EthAdapter {
        borrow_global<EthAdapter>(adapter_addr).vault_addr
    }
}
