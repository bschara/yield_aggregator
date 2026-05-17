module YieldAggregator::eth_bridge_adapter {
    use std::signer;
    use std::vector;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::timestamp;
    use YieldAggregator::oft_bridge;

    const ADAPTER_SEED: vector<u8> = b"EthBridgeAdapter";

    const ACTION_DEPLOY:  u8 = 1;
    const ACTION_RECALL:  u8 = 2;
    const ACTION_HARVEST: u8 = 3;

    const ENOT_OWNER: u64 = 1;

    struct EthAdapter has key {
        owner: address,
        signer_cap: SignerCapability,
        vault_addr: address,       // vault this adapter reports to
        bridge_addr: address,      // oft_bridge module address
        dst_chain_id: u64,         // Ethereum LayerZero chain ID (101)
        dst_executor: vector<u8>,  // 32-byte EthStrategyExecutor address on Ethereum
        strategy_id: u64,          // strategy ID in the vault registry
        deployed: u128,            // informational: APT currently on Ethereum
        nonce: u64,                // monotonic counter for cross-chain messages
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

    public entry fun init(
        account: &signer,
        vault_addr: address,
        bridge_addr: address,
        dst_chain_id: u64,
        dst_executor: vector<u8>,
        strategy_id: u64,
    ) {
        let owner = signer::address_of(account);
        let (adapter_signer, signer_cap) = account::create_resource_account(account, ADAPTER_SEED);
        coin::register<AptosCoin>(&adapter_signer);

        move_to(&adapter_signer, EthAdapter {
            owner,
            signer_cap,
            vault_addr,
            bridge_addr,
            dst_chain_id,
            dst_executor,
            strategy_id,
            deployed: 0,
            nonce: 0,
        });
    }

    // Returns the deterministic adapter address for a given owner.
    public fun adapter_address(owner: address): address {
        account::create_resource_address(&owner, ADAPTER_SEED)
    }

    // Two-step deploy flow:
    //   1. Vault calls deploy_to_strategy to deposits APT to adapter's CoinStore.
    //   2. Operator calls bridge_out here to withdraws APT and forwards via oft_bridge.
    // The vault address encoded in the payload tells Ethereum where to return funds.

    public entry fun bridge_out(
        account: &signer,
        adapter_addr: address,
        amount: u64,
    ) acquires EthAdapter {
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);

        state.nonce = state.nonce + 1;
        let nonce = state.nonce;

        let adapter_signer = account::create_signer_with_capability(&state.signer_cap);
        let coins = coin::withdraw<AptosCoin>(&adapter_signer, amount);

        let payload = oft_bridge::encode_payload(
            ACTION_DEPLOY,
            amount,
            state.strategy_id,
            nonce,
            state.vault_addr,
        );

        let bridge_addr = state.bridge_addr;
        oft_bridge::bridge_out(
            account,
            bridge_addr,
            coins,
            state.dst_chain_id,
            state.dst_executor,
            payload,
            coin::zero<AptosCoin>(),  // fee stub: caller funds fee separately or uses estimateFees
            vector::empty<u8>(),
        );

        state.deployed = state.deployed + (amount as u128);

        0x1::event::emit(DeployBridgedEvent {
            amount,
            nonce,
            timestamp: timestamp::now_microseconds(),
        });
    }

    // Signals Ethereum to withdraw `amount` from the strategy and send it back.
    // No APT is locked here the principal is already on Ethereum.
    // Coins return asynchronously via oft_bridge::lz_receive to message_receiver.

    public entry fun send_recall(
        account: &signer,
        adapter_addr: address,
        amount: u64,
    ) acquires EthAdapter {
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);

        state.nonce = state.nonce + 1;
        let nonce = state.nonce;

        let payload = oft_bridge::encode_payload(
            ACTION_RECALL,
            amount,
            state.strategy_id,
            nonce,
            state.vault_addr,
        );

        let bridge_addr = state.bridge_addr;
        oft_bridge::bridge_out(
            account,
            bridge_addr,
            coin::zero<AptosCoin>(),  // no new APT locked; recall returns existing locked APT
            state.dst_chain_id,
            state.dst_executor,
            payload,
            coin::zero<AptosCoin>(),
            vector::empty<u8>(),
        );

        0x1::event::emit(RecallSentEvent {
            amount,
            nonce,
            timestamp: timestamp::now_microseconds(),
        });
    }

    // Send harvest message (Aptos to Ethereum)
    // Instructs Ethereum to collect accumulated yield and send it back as APT.

    public entry fun send_harvest(
        account: &signer,
        adapter_addr: address,
    ) acquires EthAdapter {
        let state = borrow_global_mut<EthAdapter>(adapter_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);

        state.nonce = state.nonce + 1;
        let nonce = state.nonce;

        let payload = oft_bridge::encode_payload(
            ACTION_HARVEST,
            0,   // amount=0; Ethereum determines how much yield to send
            state.strategy_id,
            nonce,
            state.vault_addr,
        );

        let bridge_addr = state.bridge_addr;
        oft_bridge::bridge_out(
            account,
            bridge_addr,
            coin::zero<AptosCoin>(),
            state.dst_chain_id,
            state.dst_executor,
            payload,
            coin::zero<AptosCoin>(),
            vector::empty<u8>(),
        );

        0x1::event::emit(HarvestSentEvent {
            nonce,
            timestamp: timestamp::now_microseconds(),
        });
    }

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
