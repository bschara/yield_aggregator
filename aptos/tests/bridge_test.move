// Tests for cross-chain bridge modules.
//
// Covered here:
//   1. oft_bridge payload encoding / decoding (pure functions, no state)
//   2. message_receiver::handle_incoming → vault accounting (no LZ needed)
//   3. eth_bridge_adapter::init + address derivation (no LZ needed)
//   4. oft_bridge BridgeState init, trusted remote, bridge_out, lz_receive (LZ required)
//   5. eth_bridge_adapter bridge_out nonce + deployed tracking (LZ required)

module YieldAggregator::bridge_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use YieldAggregator::yield_vault;
    use YieldAggregator::message_receiver;
    use YieldAggregator::oft_bridge;
    use YieldAggregator::eth_bridge_adapter;

    // ── Vault setup helper ────────────────────────────────────────────────────

    fun setup_vault(vault_owner: &signer, framework: &signer): address {
        timestamp::set_time_has_started_for_testing(framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);
        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);

        // Pre-fund vault with coins that will "arrive" from Ethereum
        let coins = coin::mint<aptos_coin::AptosCoin>(10_000, &mint_cap);
        coin::deposit<aptos_coin::AptosCoin>(vault_addr, coins);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
        vault_addr
    }

    // ── oft_bridge — payload encoding tests ───────────────────────────────────

    #[test]
    public fun test_encode_payload_length() {
        // 1 (action) + 8 (amount) + 8 (strategy_id) + 8 (nonce) + 32 (addr) = 57 bytes
        let payload = oft_bridge::encode_payload(1u8, 500u64, 42u64, 7u64, @0x123);
        assert!(vector::length(&payload) == 57, 0);
    }

    #[test]
    public fun test_encode_payload_action_byte() {
        let payload = oft_bridge::encode_payload(3u8, 0u64, 0u64, 0u64, @0x1);
        assert!(*vector::borrow(&payload, 0) == 3u8, 0);
    }

    #[test]
    public fun test_encode_payload_amount_roundtrip() {
        let amount: u64 = 999_888_777;
        let payload = oft_bridge::encode_payload(1u8, amount, 0u64, 0u64, @0x1);
        let decoded: u64 = 0;
        let i = 1u64;
        while (i < 9) {
            decoded = (decoded << 8) | (*vector::borrow(&payload, i) as u64);
            i = i + 1;
        };
        assert!(decoded == amount, 0);
    }

    #[test]
    public fun test_encode_payload_strategy_id_roundtrip() {
        let sid: u64 = 12345;
        let payload = oft_bridge::encode_payload(1u8, 0u64, sid, 0u64, @0x1);
        let decoded: u64 = 0;
        let i = 9u64;
        while (i < 17) {
            decoded = (decoded << 8) | (*vector::borrow(&payload, i) as u64);
            i = i + 1;
        };
        assert!(decoded == sid, 0);
    }

    #[test]
    public fun test_encode_payload_nonce_roundtrip() {
        let nonce: u64 = 0xDEADBEEF;
        let payload = oft_bridge::encode_payload(1u8, 0u64, 0u64, nonce, @0x1);
        let decoded: u64 = 0;
        let i = 17u64;
        while (i < 25) {
            decoded = (decoded << 8) | (*vector::borrow(&payload, i) as u64);
            i = i + 1;
        };
        assert!(decoded == nonce, 0);
    }

    #[test]
    public fun test_encode_payload_zero_values() {
        let payload = oft_bridge::encode_payload(1u8, 0u64, 0u64, 0u64, @0x0);
        assert!(vector::length(&payload) == 57, 0);
        // All numeric bytes except action should be zero
        let i = 1u64;
        while (i < 25) {
            assert!(*vector::borrow(&payload, i) == 0u8, (i as u64));
            i = i + 1;
        };
    }

    // ── message_receiver — COMPLETE action ────────────────────────────────────

    #[test(vault_owner = @0x200, framework = @0x1)]
    public fun test_complete_increases_idle_assets(
        vault_owner: &signer,
        framework: &signer,
    ) {
        let vault_addr = setup_vault(vault_owner, framework);
        // Seed deployed state so credit_bridge_return doesn't underflow
        yield_vault::set_deployed_for_test(vault_addr, 0u64, 1_000);

        let idle_before = yield_vault::get_idle_assets(vault_addr);
        // ACTION_COMPLETE = 4
        message_receiver::handle_incoming(vault_addr, 500, 4u8, 0u64, 1u64);
        assert!(yield_vault::get_idle_assets(vault_addr) == idle_before + 500, 0);
    }

    #[test(vault_owner = @0x200, framework = @0x1)]
    public fun test_complete_decreases_deployed_assets(
        vault_owner: &signer,
        framework: &signer,
    ) {
        let vault_addr = setup_vault(vault_owner, framework);
        yield_vault::set_deployed_for_test(vault_addr, 1u64, 800);

        let deployed_before = yield_vault::get_deployed_assets(vault_addr);
        message_receiver::handle_incoming(vault_addr, 300, 4u8, 1u64, 1u64);
        assert!(yield_vault::get_deployed_assets(vault_addr) == deployed_before - 300, 0);
    }

    #[test(vault_owner = @0x200, framework = @0x1)]
    public fun test_complete_reduces_strategy_allocation(
        vault_owner: &signer,
        framework: &signer,
    ) {
        let vault_addr = setup_vault(vault_owner, framework);
        yield_vault::set_deployed_for_test(vault_addr, 7u64, 600);

        let alloc_before = yield_vault::get_allocation(vault_addr, 7u64);
        message_receiver::handle_incoming(vault_addr, 200, 4u8, 7u64, 1u64);
        assert!(yield_vault::get_allocation(vault_addr, 7u64) == alloc_before - 200, 0);
    }

    // ── message_receiver — HARVEST action ─────────────────────────────────────

    #[test(vault_owner = @0x200, framework = @0x1)]
    public fun test_harvest_increases_total_assets(
        vault_owner: &signer,
        framework: &signer,
    ) {
        let vault_addr = setup_vault(vault_owner, framework);
        let total_before = yield_vault::get_total_assets(vault_addr);
        // ACTION_HARVEST = 3
        message_receiver::handle_incoming(vault_addr, 250, 3u8, 0u64, 1u64);
        assert!(yield_vault::get_total_assets(vault_addr) == total_before + 250, 0);
    }

    #[test(vault_owner = @0x200, framework = @0x1)]
    public fun test_harvest_increases_idle_assets(
        vault_owner: &signer,
        framework: &signer,
    ) {
        let vault_addr = setup_vault(vault_owner, framework);
        let idle_before = yield_vault::get_idle_assets(vault_addr);
        message_receiver::handle_incoming(vault_addr, 100, 3u8, 0u64, 1u64);
        assert!(yield_vault::get_idle_assets(vault_addr) == idle_before + 100, 0);
    }

    #[test(vault_owner = @0x200, framework = @0x1)]
    public fun test_harvest_does_not_change_deployed(
        vault_owner: &signer,
        framework: &signer,
    ) {
        let vault_addr = setup_vault(vault_owner, framework);
        yield_vault::set_deployed_for_test(vault_addr, 0u64, 500);
        let deployed_before = yield_vault::get_deployed_assets(vault_addr);
        message_receiver::handle_incoming(vault_addr, 75, 3u8, 0u64, 1u64);
        assert!(yield_vault::get_deployed_assets(vault_addr) == deployed_before, 0);
    }

    // ── message_receiver — unknown action is a no-op ──────────────────────────

    #[test(vault_owner = @0x200, framework = @0x1)]
    public fun test_unknown_action_is_noop(
        vault_owner: &signer,
        framework: &signer,
    ) {
        let vault_addr = setup_vault(vault_owner, framework);
        let total_before = yield_vault::get_total_assets(vault_addr);
        let idle_before  = yield_vault::get_idle_assets(vault_addr);
        // ACTION_DEPLOY (1) should never arrive as an incoming message; ignored.
        message_receiver::handle_incoming(vault_addr, 999, 1u8, 0u64, 1u64);
        assert!(yield_vault::get_total_assets(vault_addr) == total_before, 0);
        assert!(yield_vault::get_idle_assets(vault_addr)  == idle_before,  1);
    }

    // ── vault credit helpers ───────────────────────────────────────────────────

    #[test(vault_owner = @0x200, framework = @0x1)]
    public fun test_credit_bridge_harvest_increases_total_and_idle(
        vault_owner: &signer,
        framework: &signer,
    ) {
        let vault_addr = setup_vault(vault_owner, framework);
        let total_before = yield_vault::get_total_assets(vault_addr);
        let idle_before  = yield_vault::get_idle_assets(vault_addr);

        yield_vault::credit_bridge_harvest(vault_addr, 500);

        assert!(yield_vault::get_total_assets(vault_addr) == total_before + 500, 0);
        assert!(yield_vault::get_idle_assets(vault_addr)  == idle_before  + 500, 1);
    }

    #[test(vault_owner = @0x200, framework = @0x1)]
    public fun test_credit_bridge_return_adjusts_accounting(
        vault_owner: &signer,
        framework: &signer,
    ) {
        let vault_addr = setup_vault(vault_owner, framework);
        yield_vault::set_deployed_for_test(vault_addr, 3u64, 1_000);

        let idle_before     = yield_vault::get_idle_assets(vault_addr);
        let deployed_before = yield_vault::get_deployed_assets(vault_addr);
        let alloc_before    = yield_vault::get_allocation(vault_addr, 3u64);

        yield_vault::credit_bridge_return(vault_addr, 3u64, 400);

        assert!(yield_vault::get_idle_assets(vault_addr)     == idle_before     + 400, 0);
        assert!(yield_vault::get_deployed_assets(vault_addr) == deployed_before - 400, 1);
        assert!(yield_vault::get_allocation(vault_addr, 3u64) == alloc_before   - 400, 2);
    }

    // ── eth_bridge_adapter — init and address derivation ─────────────────────

    #[test(adapter_owner = @0x300, framework = @0x1)]
    public fun test_adapter_address_is_deterministic(
        adapter_owner: &signer,
        framework: &signer,
    ) {
        timestamp::set_time_has_started_for_testing(framework);
        let owner_addr = signer::address_of(adapter_owner);
        account::create_account_for_test(owner_addr);
        let addr1 = eth_bridge_adapter::adapter_address(owner_addr);
        let addr2 = eth_bridge_adapter::adapter_address(owner_addr);
        assert!(addr1 == addr2, 0);
    }

    #[test(adapter_owner = @0x300, framework = @0x1)]
    public fun test_adapter_init_state(
        adapter_owner: &signer,
        framework: &signer,
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(framework);
        timestamp::set_time_has_started_for_testing(framework);
        let owner_addr = signer::address_of(adapter_owner);
        account::create_account_for_test(owner_addr);

        let dst_executor = vector::empty<u8>();
        let i = 0u64;
        while (i < 32) { vector::push_back(&mut dst_executor, 0xABu8); i = i + 1; };

        eth_bridge_adapter::init(
            adapter_owner,
            @0x200,   // vault_addr
            @0x400,   // bridge_addr
            101u64,   // dst_chain_id (Ethereum)
            dst_executor,
            1u64,     // strategy_id
        );

        let adapter_addr = eth_bridge_adapter::adapter_address(owner_addr);
        assert!(eth_bridge_adapter::get_deployed(adapter_addr) == 0,     0);
        assert!(eth_bridge_adapter::get_nonce(adapter_addr)    == 0,     1);
        assert!(eth_bridge_adapter::get_vault_addr(adapter_addr) == @0x200, 2);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(adapter_owner = @0x300, framework = @0x1)]
    public fun test_adapter_stores_correct_vault_addr(
        adapter_owner: &signer,
        framework: &signer,
    ) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(framework);
        timestamp::set_time_has_started_for_testing(framework);
        let owner_addr = signer::address_of(adapter_owner);
        account::create_account_for_test(owner_addr);

        let dst_executor = vector::empty<u8>();
        let i = 0u64;
        while (i < 32) { vector::push_back(&mut dst_executor, 0u8); i = i + 1; };

        eth_bridge_adapter::init(
            adapter_owner,
            @0xABC,  // vault_addr
            @0x400,
            101u64,
            dst_executor,
            5u64,
        );

        let adapter_addr = eth_bridge_adapter::adapter_address(owner_addr);
        assert!(eth_bridge_adapter::get_vault_addr(adapter_addr) == @0xABC, 0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    // ── oft_bridge — full LZ integration tests ────────────────────────────────
    //
    // These tests bootstrap the LayerZero endpoint via init_bridge_for_test.
    // Required named addresses: YieldAggregator (bridge deployer), layerzero (0x102),
    // msglib_auth (0x105), executor_auth (0x100), oracle/relayer/executor (runtime).

    // Returns (mint_cap, burn_cap) so callers can do further coin operations.
    fun setup_lz_bridge(
        bridge_acct: &signer,
        lz: &signer,
        msglib_auth: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth: &signer,
        framework: &signer,
    ): (coin::MintCapability<aptos_coin::AptosCoin>, coin::BurnCapability<aptos_coin::AptosCoin>) {
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(framework);
        timestamp::set_time_has_started_for_testing(framework);
        account::create_account_for_test(signer::address_of(bridge_acct));
        // oft_bridge::init registers AptosCoin internally, so no need to register here
        oft_bridge::init_bridge_for_test(
            bridge_acct, lz, msglib_auth, oracle, relayer, executor, executor_auth,
        );
        (mint_cap, burn_cap)
    }

    #[test(
        bridge_acct = @YieldAggregator,
        lz = @layerzero,
        msglib_auth = @msglib_auth,
        oracle = @0x500,
        relayer = @0x501,
        executor = @0x502,
        executor_auth = @executor_auth,
        framework = @0x1,
    )]
    public fun test_bridge_state_initialized(
        bridge_acct: &signer,
        lz: &signer,
        msglib_auth: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth: &signer,
        framework: &signer,
    ) {
        let (mint_cap, burn_cap) = setup_lz_bridge(bridge_acct, lz, msglib_auth, oracle, relayer, executor, executor_auth, framework);
        let bridge_addr = signer::address_of(bridge_acct);
        assert!(oft_bridge::bridge_state_exists(bridge_addr), 0);
        assert!(oft_bridge::get_locked_apt(bridge_addr) == 0, 1);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(
        bridge_acct = @YieldAggregator,
        lz = @layerzero,
        msglib_auth = @msglib_auth,
        oracle = @0x500,
        relayer = @0x501,
        executor = @0x502,
        executor_auth = @executor_auth,
        framework = @0x1,
    )]
    public fun test_set_trusted_remote_by_owner(
        bridge_acct: &signer,
        lz: &signer,
        msglib_auth: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth: &signer,
        framework: &signer,
    ) {
        let (mint_cap, burn_cap) = setup_lz_bridge(bridge_acct, lz, msglib_auth, oracle, relayer, executor, executor_auth, framework);
        let bridge_addr = signer::address_of(bridge_acct);
        let remote = vector::empty<u8>();
        let i = 0u64; while (i < 32) { vector::push_back(&mut remote, 0xEEu8); i = i + 1; };
        // Should not abort
        oft_bridge::set_trusted_remote(bridge_acct, bridge_addr, 101u64, remote);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(
        bridge_acct = @YieldAggregator,
        non_owner = @0x999,
        lz = @layerzero,
        msglib_auth = @msglib_auth,
        oracle = @0x500,
        relayer = @0x501,
        executor = @0x502,
        executor_auth = @executor_auth,
        framework = @0x1,
    )]
    #[expected_failure(abort_code = 1)]
    public fun test_set_trusted_remote_owner_only(
        bridge_acct: &signer,
        non_owner: &signer,
        lz: &signer,
        msglib_auth: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth: &signer,
        framework: &signer,
    ) {
        let (mint_cap, burn_cap) = setup_lz_bridge(bridge_acct, lz, msglib_auth, oracle, relayer, executor, executor_auth, framework);
        let bridge_addr = signer::address_of(bridge_acct);
        let remote = vector::empty<u8>();
        let i = 0u64; while (i < 32) { vector::push_back(&mut remote, 0xAAu8); i = i + 1; };
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
        // non_owner should be rejected
        oft_bridge::set_trusted_remote(non_owner, bridge_addr, 101u64, remote);
    }

    #[test(
        bridge_acct = @YieldAggregator,
        lz = @layerzero,
        msglib_auth = @msglib_auth,
        oracle = @0x500,
        relayer = @0x501,
        executor = @0x502,
        executor_auth = @executor_auth,
        framework = @0x1,
    )]
    public fun test_bridge_out_locks_apt(
        bridge_acct: &signer,
        lz: &signer,
        msglib_auth: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth: &signer,
        framework: &signer,
    ) {
        let (mint_cap, burn_cap) = setup_lz_bridge(bridge_acct, lz, msglib_auth, oracle, relayer, executor, executor_auth, framework);
        let bridge_addr = signer::address_of(bridge_acct);

        let coins = coin::mint<aptos_coin::AptosCoin>(500, &mint_cap);
        let locked_before = oft_bridge::get_locked_apt(bridge_addr);
        let dst = vector::empty<u8>();
        let i = 0u64; while (i < 32) { vector::push_back(&mut dst, 0u8); i = i + 1; };
        let payload = oft_bridge::encode_payload(1u8, 500u64, 1u64, 1u64, @0x200);

        oft_bridge::bridge_out(bridge_acct, bridge_addr, coins, 101u64, dst, payload, coin::zero<aptos_coin::AptosCoin>(), vector::empty<u8>());

        assert!(oft_bridge::get_locked_apt(bridge_addr) == locked_before + 500, 0);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(
        vault_owner = @0x200,
        bridge_acct = @YieldAggregator,
        lz = @layerzero,
        msglib_auth = @msglib_auth,
        oracle = @0x500,
        relayer = @0x501,
        executor = @0x502,
        executor_auth = @executor_auth,
        framework = @0x1,
    )]
    #[expected_failure(abort_code = 3)]  // EUNTRUSTED_REMOTE
    public fun test_lz_receive_rejects_untrusted_remote(
        vault_owner: &signer,
        bridge_acct: &signer,
        lz: &signer,
        msglib_auth: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth: &signer,
        framework: &signer,
    ) {
        let (mint_cap, burn_cap) = setup_lz_bridge(bridge_acct, lz, msglib_auth, oracle, relayer, executor, executor_auth, framework);
        let bridge_addr = signer::address_of(bridge_acct);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
        // No trusted remote set; any lz_receive call should abort
        let src_addr = vector::empty<u8>();
        let i = 0u64; while (i < 32) { vector::push_back(&mut src_addr, 0xBBu8); i = i + 1; };
        let payload = oft_bridge::encode_payload(4u8, 100u64, 1u64, 1u64, @0x200);
        oft_bridge::lz_receive(101u64, src_addr, payload, bridge_addr);
    }

    #[test(
        vault_owner = @0x200,
        bridge_acct = @YieldAggregator,
        lz = @layerzero,
        msglib_auth = @msglib_auth,
        oracle = @0x500,
        relayer = @0x501,
        executor = @0x502,
        executor_auth = @executor_auth,
        framework = @0x1,
    )]
    #[expected_failure(abort_code = 3)]  // EUNTRUSTED_REMOTE — unknown chain
    public fun test_lz_receive_rejects_unknown_chain(
        vault_owner: &signer,
        bridge_acct: &signer,
        lz: &signer,
        msglib_auth: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth: &signer,
        framework: &signer,
    ) {
        let (mint_cap, burn_cap) = setup_lz_bridge(bridge_acct, lz, msglib_auth, oracle, relayer, executor, executor_auth, framework);
        let bridge_addr = signer::address_of(bridge_acct);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
        // Register Ethereum (101) but try to receive from Polygon (109)
        let remote = vector::empty<u8>();
        let i = 0u64; while (i < 32) { vector::push_back(&mut remote, 0xCCu8); i = i + 1; };
        oft_bridge::set_trusted_remote(bridge_acct, bridge_addr, 101u64, remote);
        let payload = oft_bridge::encode_payload(4u8, 100u64, 1u64, 1u64, @0x200);
        oft_bridge::lz_receive(109u64, remote, payload, bridge_addr); // wrong chain
    }

    #[test(
        vault_owner = @0x200,
        bridge_acct = @YieldAggregator,
        lz = @layerzero,
        msglib_auth = @msglib_auth,
        oracle = @0x500,
        relayer = @0x501,
        executor = @0x502,
        executor_auth = @executor_auth,
        framework = @0x1,
    )]
    public fun test_lz_receive_happy_path(
        vault_owner: &signer,
        bridge_acct: &signer,
        lz: &signer,
        msglib_auth: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth: &signer,
        framework: &signer,
    ) {
        let (mint_cap, burn_cap) = setup_lz_bridge(bridge_acct, lz, msglib_auth, oracle, relayer, executor, executor_auth, framework);
        let bridge_addr = signer::address_of(bridge_acct);

        // Set up vault without re-initialising AptosCoin (already done in setup_lz_bridge)
        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);
        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        // Fund vault so it can receive the unlocked APT
        let seed = coin::mint<aptos_coin::AptosCoin>(10_000, &mint_cap);
        coin::deposit(vault_addr, seed);

        // Seed deployed so credit_bridge_return doesn't underflow
        yield_vault::set_deployed_for_test(vault_addr, 1u64, 300);

        // Lock 300 APT in the bridge (simulates a prior bridge_out)
        let lock_coins = coin::mint<aptos_coin::AptosCoin>(300, &mint_cap);
        let dst = vector::empty<u8>(); let i = 0u64; while (i < 32) { vector::push_back(&mut dst, 0u8); i = i + 1; };
        let out_payload = oft_bridge::encode_payload(1u8, 300u64, 1u64, 0u64, vault_addr);
        oft_bridge::bridge_out(bridge_acct, bridge_addr, lock_coins, 101u64, dst, out_payload, coin::zero<aptos_coin::AptosCoin>(), vector::empty<u8>());
        assert!(oft_bridge::get_locked_apt(bridge_addr) == 300, 0);

        // Register trusted remote
        let remote = vector::empty<u8>(); let i = 0u64; while (i < 32) { vector::push_back(&mut remote, 0xDDu8); i = i + 1; };
        oft_bridge::set_trusted_remote(bridge_acct, bridge_addr, 101u64, remote);

        let idle_before = yield_vault::get_idle_assets(vault_addr);

        // ACTION_COMPLETE returning 200 APT
        let in_payload = oft_bridge::encode_payload(4u8, 200u64, 1u64, 1u64, vault_addr);
        oft_bridge::lz_receive(101u64, remote, in_payload, bridge_addr);

        assert!(oft_bridge::get_locked_apt(bridge_addr) == 100, 1);      // 300 - 200
        assert!(yield_vault::get_idle_assets(vault_addr) == idle_before + 200, 2);
        assert!(oft_bridge::is_nonce_processed(bridge_addr, 1u64), 3);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(
        vault_owner = @0x200,
        bridge_acct = @YieldAggregator,
        lz = @layerzero,
        msglib_auth = @msglib_auth,
        oracle = @0x500,
        relayer = @0x501,
        executor = @0x502,
        executor_auth = @executor_auth,
        framework = @0x1,
    )]
    #[expected_failure(abort_code = 2)]  // ENONCE_REPLAY
    public fun test_lz_receive_rejects_nonce_replay(
        vault_owner: &signer,
        bridge_acct: &signer,
        lz: &signer,
        msglib_auth: &signer,
        oracle: &signer,
        relayer: &signer,
        executor: &signer,
        executor_auth: &signer,
        framework: &signer,
    ) {
        let (mint_cap, burn_cap) = setup_lz_bridge(bridge_acct, lz, msglib_auth, oracle, relayer, executor, executor_auth, framework);
        let bridge_addr = signer::address_of(bridge_acct);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);
        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        let seed = coin::mint<aptos_coin::AptosCoin>(10_000, &mint_cap);
        coin::deposit(vault_addr, seed);

        yield_vault::set_deployed_for_test(vault_addr, 1u64, 600);

        // Lock 600 APT
        let lock_coins = coin::mint<aptos_coin::AptosCoin>(600, &mint_cap);
        let dst = vector::empty<u8>(); let i = 0u64; while (i < 32) { vector::push_back(&mut dst, 0u8); i = i + 1; };
        let out_payload = oft_bridge::encode_payload(1u8, 600u64, 1u64, 0u64, vault_addr);
        oft_bridge::bridge_out(bridge_acct, bridge_addr, lock_coins, 101u64, dst, out_payload, coin::zero<aptos_coin::AptosCoin>(), vector::empty<u8>());

        let remote = vector::empty<u8>(); let i = 0u64; while (i < 32) { vector::push_back(&mut remote, 0xEEu8); i = i + 1; };
        oft_bridge::set_trusted_remote(bridge_acct, bridge_addr, 101u64, remote);

        let in_payload = oft_bridge::encode_payload(4u8, 100u64, 1u64, 5u64, vault_addr);
        // First call succeeds
        oft_bridge::lz_receive(101u64, remote, in_payload, bridge_addr);
        // Second call with same nonce must abort (caps won't be destroyed due to expected failure)
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
        oft_bridge::lz_receive(101u64, remote, in_payload, bridge_addr);
    }
}
