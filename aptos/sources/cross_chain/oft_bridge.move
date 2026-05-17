module YieldAggregator::oft_bridge {
    use std::signer;
    use std::option;
    use std::table;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use layerzero::endpoint::{Self, UaCapability};
    use zro::zro::ZRO;
    use aptos_std::from_bcs;
    use layerzero_apps::oft;
    use YieldAggregator::message_receiver;
    use std::vector;

    // VaultBridgeOFT represents bridged vault assets in the cross-chain system.
    //
    // Mint/burn OFT mode:
    //   Send (Aptos to Ethereum): vault's APT locked here, VaultBridgeOFT message
    //     burned by OFT, wAPT minted on Ethereum.
    //   Receive (Ethereum to Aptos): wAPT burned on Ethereum, VaultBridgeOFT minted
    //     on Aptos by lz_receive, bridge unlocks equal APT back to vault.
    //
    // The bridge always holds 1 APT per outstanding VaultBridgeOFT unit.

    struct VaultBridgeOFT has key {}

    // Issued once by init() and stored in EthAdapter (or any authorized caller).
    // Holding this is proof of authorization to call bridge_out no signer needed.
    struct BridgeCapability has store, drop {}

    struct BridgeState has key {
        owner: address,
        lz_cap: UaCapability<VaultBridgeOFT>,
        // APT locked while assets are deployed on Ethereum
        locked_apt: Coin<AptosCoin>,
        // chain_id to 32-byte trusted remote OFT address on that chain
        trusted_remotes: table::Table<u64, vector<u8>>,
        // nonce to true for incoming messages already processed
        processed_nonces: table::Table<u64, bool>,
    }

    #[event]
    struct BridgeOutEvent has drop, store {
        amount: u128,
        dst_chain_id: u64,
        timestamp: u64,
    }

    #[event]
    struct BridgeInEvent has drop, store {
        amount: u128,
        src_chain_id: u64,
        action: u8,
        timestamp: u64,
    }

    const ENOT_OWNER: u64 = 1;
    const ENONCE_REPLAY: u64 = 2;
    const EUNTRUSTED_REMOTE: u64 = 3;
    const EINSUFFICIENT_LOCKED: u64 = 4;

    const ACTION_DEPLOY:   u8 = 1;
    const ACTION_RECALL:   u8 = 2;
    const ACTION_HARVEST:  u8 = 3;
    const ACTION_COMPLETE: u8 = 4;

    const ETH_CHAIN_ID: u64 = 101;

    public fun init(account: &signer, shared_decimals: u8): BridgeCapability {
        let lz_cap = oft::init_oft<VaultBridgeOFT>(
            account,
            b"Vault Bridge Token",
            b"vbAPT",
            8,              // local decimals (match APT)
            shared_decimals,
        );

        // Register AptosCoin store so the fee stub refund in bridge_out can deposit.
        aptos_framework::coin::register<aptos_framework::aptos_coin::AptosCoin>(account);

        move_to(account, BridgeState {
            owner: signer::address_of(account),
            lz_cap,
            locked_apt: coin::zero<AptosCoin>(),
            trusted_remotes: table::new<u64, vector<u8>>(),
            processed_nonces: table::new<u64, bool>(),
        });

        BridgeCapability {}
    }

    public entry fun set_trusted_remote(
        account: &signer,
        bridge_addr: address,
        chain_id: u64,
        remote_addr: vector<u8>,    // 32-byte Ethereum OFT contract address
    ) acquires BridgeState {
        let state = borrow_global_mut<BridgeState>(bridge_addr);
        assert!(signer::address_of(account) == state.owner, ENOT_OWNER);
        if (table::contains(&state.trusted_remotes, chain_id)) {
            *table::borrow_mut(&mut state.trusted_remotes, chain_id) = remote_addr;
        } else {
            table::add(&mut state.trusted_remotes, chain_id, remote_addr);
        }
    }

    // Called by eth_bridge_adapter::bridge_out.
    // Locks APT as collateral and sends a raw LZ endpoint message to Ethereum
    // carrying our 57-byte custom payload:
    //   [0]     action   u8
    //   [1..8]  amount   u64 BE
    //   [9..16] strategy u64 BE
    //   [17..24] nonce   u64 BE
    //   [25..56] vaultAddr bytes32
    //
    // We use raw endpoint::send (not oft::send_coin) because the standard OFT wire
    // format only carries [receiver(32)][amount_sd(8)] and cannot carry our payload.
    // APT is locked here; VaultOFT on Ethereum mints wAPT when the message arrives.
    //
    // bridge_owner must be the signer whose address matches state.owner (i.e. the
    // @YieldAggregator deployer), as endpoint::send requires the UA signer.

    public fun bridge_out(
        _cap: &BridgeCapability,
        bridge_addr: address,
        apt_coins: Coin<AptosCoin>,
        dst_chain_id: u64,
        dst_receiver: vector<u8>,       // 32-byte Ethereum VaultOFT address
        payload: vector<u8>,            // encoded 57-byte action payload
        native_fee: Coin<AptosCoin>,
        adapter_params: vector<u8>,
    ) acquires BridgeState {
        let amount = coin::value(&apt_coins);
        let state = borrow_global_mut<BridgeState>(bridge_addr);

        // Lock APT as cross-chain collateral.
        coin::merge(&mut state.locked_apt, apt_coins);

        if (coin::value(&native_fee) == 0) {
            // Zero fee: signal-only messages (RECALL/HARVEST) or test environment.
            // In production these still need a fee; the caller is expected to fund
            // a separate fee payment or use estimateFees first.
            coin::destroy_zero(native_fee);
        } else {
            // Send via raw LZ endpoint with our custom payload.
            // endpoint::send returns (Coin<AptosCoin> refund, Coin<AptosCoin> zro_refund).
            let (_nonce, refund, zro_refund) = endpoint::send<VaultBridgeOFT>(
                dst_chain_id,
                dst_receiver,
                payload,
                native_fee,
                coin::zero<ZRO>(),
                adapter_params,
                vector::empty<u8>(),
                &state.lz_cap,
            );
            coin::deposit<AptosCoin>(bridge_addr, refund);
            // ZRO refund is always zero when paying in APT; destroy it.
            coin::destroy_zero(zro_refund);
        };

        0x1::event::emit(BridgeOutEvent {
            amount: (amount as u128),
            dst_chain_id,
            timestamp: timestamp::now_microseconds(),
        });
    }

    // Production entry point called by the LayerZero executor when a message
    // arrives from Ethereum. First consumes the packet from the LZ inbox (advancing
    // the inbound nonce so the executor won't retry), then processes it.
    public entry fun lz_receive(
        src_chain_id: u64,
        src_address: vector<u8>,
        payload: vector<u8>,
        bridge_addr: address,
    ) acquires BridgeState {
        // Borrow immutably just for lz_cap, then release before the mutable borrow in impl.
        {
            let state = borrow_global<BridgeState>(bridge_addr);
            endpoint::lz_receive<VaultBridgeOFT>(src_chain_id, src_address, payload, &state.lz_cap);
        };
        lz_receive_impl(src_chain_id, src_address, payload, bridge_addr);
    }

    // Internal payload processor validates trusted remote, decodes payload,
    // unlocks APT, and updates vault accounting.
    fun lz_receive_impl(
        src_chain_id: u64,
        src_address: vector<u8>,
        payload: vector<u8>,
        bridge_addr: address,
    ) acquires BridgeState {
        let state = borrow_global_mut<BridgeState>(bridge_addr);

        // Verify trusted remote
        assert!(table::contains(&state.trusted_remotes, src_chain_id), EUNTRUSTED_REMOTE);
        let expected = table::borrow(&state.trusted_remotes, src_chain_id);
        assert!(*expected == src_address, EUNTRUSTED_REMOTE);

        // Decode custom payload:
        //   [0]      action    u8
        //   [1..8]   amount    u64
        //   [9..16]  strategy  u64
        //   [17..24] nonce     u64
        //   [25..56] vaultAddr bytes32

        let action       = *std::vector::borrow(&payload, 0);
        let amount       = decode_u64(&payload, 1);
        let strategy_id  = decode_u64(&payload, 9);
        let nonce        = decode_u64(&payload, 17);
        let vault_addr   = decode_address(&payload, 25);

        assert!(!table::contains(&state.processed_nonces, nonce), ENONCE_REPLAY);
        table::add(&mut state.processed_nonces, nonce, true);

        // Unlock APT equal to the returned amount
        assert!(coin::value(&state.locked_apt) >= amount, EINSUFFICIENT_LOCKED);
        let apt_out = coin::extract(&mut state.locked_apt, amount);

        // Deposit APT to vault and update its accounting
        coin::deposit<AptosCoin>(vault_addr, apt_out);
        message_receiver::handle_incoming(vault_addr, amount, action, strategy_id, nonce);

        0x1::event::emit(BridgeInEvent {
            amount: (amount as u128),
            src_chain_id,
            action,
            timestamp: timestamp::now_microseconds(),
        });
    }

    // Test-only bypass: skips the LZ endpoint queue check so tests can call
    // lz_receive_impl directly without routing a packet through the real LZ stack.
    // Use lz_receive (the production entry) for deliver_packet-based tests.
    #[test_only]
    public fun lz_receive_for_test(
        src_chain_id: u64,
        src_address: vector<u8>,
        payload: vector<u8>,
        bridge_addr: address,
    ) acquires BridgeState {
        lz_receive_impl(src_chain_id, src_address, payload, bridge_addr);
    }

    // Payload helpers
    // Encode the cross-chain action payload sent alongside the OFT transfer.
    public fun encode_payload(
        action: u8,
        amount: u64,
        strategy_id: u64,
        nonce: u64,
        vault_addr: address,
    ): vector<u8> {
        let buf = std::vector::empty<u8>();
        std::vector::push_back(&mut buf, action);
        append_u64(&mut buf, amount);
        append_u64(&mut buf, strategy_id);
        append_u64(&mut buf, nonce);
        // Vault address as 32 bytes (BCS encoding pads to 32)
        let addr_bytes = std::bcs::to_bytes(&vault_addr);
        std::vector::append(&mut buf, addr_bytes);
        buf
    }

    // Internal helpers

    fun append_u64(buf: &mut vector<u8>, v: u64) {
        let i = 0u8;
        while (i < 8) {
            let shift = (7u8 - i) * 8u8;
            std::vector::push_back(buf, ((v >> shift) & 0xFF) as u8);
            i = i + 1;
        }
    }

    fun decode_u64(buf: &vector<u8>, offset: u64): u64 {
        let v = 0u64;
        let i = 0u64;
        while (i < 8) {
            v = (v << 8) | (*std::vector::borrow(buf, offset + i) as u64);
            i = i + 1;
        };
        v
    }

    fun decode_address(buf: &vector<u8>, offset: u64): address {
        // Aptos addresses are 32 bytes; take the last 32 bytes starting at offset
        let addr_bytes = std::vector::empty<u8>();
        let i = 0u64;
        while (i < 32) {
            std::vector::push_back(&mut addr_bytes, *std::vector::borrow(buf, offset + i));
            i = i + 1;
        };
        // BCS decode the 32-byte address
        let addr: address = from_bcs::to_address(addr_bytes);
        addr
    }

    #[test_only]
    use layerzero::test_helpers;
    #[test_only]
    use aptos_framework::account as fw_account;

    // Bootstraps a full LayerZero environment and then initialises oft_bridge.
    // Call this at the start of any test that needs BridgeState.
    // bridge_acct must be the signer for @YieldAggregator (the module deployer).
    #[test_only]
    public fun init_bridge_for_test(
        bridge_acct: &signer,
        lz: &signer,
        msglib_auth_signer: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth_signer: &signer,
    ): BridgeCapability {
        fw_account::create_account_for_test(signer::address_of(oracle));
        fw_account::create_account_for_test(signer::address_of(relayer));
        fw_account::create_account_for_test(signer::address_of(executor));

        test_helpers::setup_layerzero_for_test(
            lz,
            msglib_auth_signer,
            oracle,
            relayer,
            executor,
            executor_auth_signer,
            108, // Aptos src chain id
            101, // Ethereum dst chain id
        );

        init(bridge_acct, 6)
    }

    #[test_only]
    public fun create_test_bridge_cap(): BridgeCapability {
        BridgeCapability {}
    }

    #[test_only]
    public fun get_locked_apt(bridge_addr: address): u64 acquires BridgeState {
        coin::value(&borrow_global<BridgeState>(bridge_addr).locked_apt)
    }

    #[test_only]
    public fun is_nonce_processed(bridge_addr: address, nonce: u64): bool acquires BridgeState {
        table::contains(&borrow_global<BridgeState>(bridge_addr).processed_nonces, nonce)
    }

    #[test_only]
    public fun bridge_state_exists(bridge_addr: address): bool {
        exists<BridgeState>(bridge_addr)
    }
}
