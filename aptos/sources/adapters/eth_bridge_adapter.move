module YieldAggregator::eth_bridge_adapter {
    use std::signer;
    use std::vector;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::timestamp;
    use YieldAggregator::oft_bridge::{Self, BridgeCapability};
    use YieldAggregator::adapter_registry;

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

    // Manual operator entry point use when you want explicit control over bridging
    // rather than relying on trigger_deposit from the vault dispatch path.
    // Fee is withdrawn from caller's account; APT must already be in adapter CoinStore.
    public entry fun bridge_out(
        account: &signer,
        adapter_addr: address,
        amount: u64,
        fee_amount: u64,
    ) acquires EthAdapter {
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);

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

    // Signal Ethereum to withdraw `amount` and send it back.
    // Fee withdrawn from caller's account.
    public entry fun send_recall(
        account: &signer,
        adapter_addr: address,
        amount: u64,
        fee_amount: u64,
    ) acquires EthAdapter {
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);

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

    // Signal Ethereum to collect yield and send it back.
    // Fee withdrawn from caller's account.
    public entry fun send_harvest(
        account: &signer,
        adapter_addr: address,
        fee_amount: u64,
    ) acquires EthAdapter {
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);

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
