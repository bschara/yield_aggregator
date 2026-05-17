module YieldAggregator::vault_tests {
    use std::signer;
    use std::debug;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use YieldAggregator::yield_vault;

    #[test(vault_owner = @0x123, user = @0x5446, framework = @0x1)]
    public fun test_vault_deposit(vault_owner: &signer, user: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
        coin::register<aptos_coin::AptosCoin>(user);
        coin::deposit(user_addr, coin::mint(1000, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        yield_vault::deposit(user, 100, vault_addr);

        let user_balance = coin::balance<aptos_coin::AptosCoin>(user_addr);
        debug::print(&user_balance);
        assert!(user_balance == 900, 0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, framework = @0x1)]
    public fun test_init_state(vault_owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);

        assert!(yield_vault::get_total_assets(vault_addr) == 0, 0);
        assert!(yield_vault::get_total_shares(vault_addr) == 0, 1);
        assert!(yield_vault::get_idle_assets(vault_addr) == 0, 2);
        assert!(yield_vault::get_deployed_assets(vault_addr) == 0, 3);
        assert!(!yield_vault::is_paused(vault_addr), 4);
        assert!(yield_vault::get_strategies_len(vault_addr) == 0, 5);

        assert!(yield_vault::was_init_vault_event_emitted(owner_addr, vault_addr, 0), 6);
    }

    #[test(vault_owner = @0x123, user = @0x5446, framework = @0x1)]
    public fun test_first_deposit_one_to_one(vault_owner: &signer, user: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
        coin::register<aptos_coin::AptosCoin>(user);
        coin::deposit(user_addr, coin::mint(500, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        yield_vault::deposit(user, 300, vault_addr);

        assert!(yield_vault::get_total_shares(vault_addr) == 300, 0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, user = @0x5446, framework = @0x1)]
    public fun test_deposit_updates_vault_accounting(vault_owner: &signer, user: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
        coin::register<aptos_coin::AptosCoin>(user);
        coin::deposit(user_addr, coin::mint(1000, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        yield_vault::deposit(user, 400, vault_addr);

        assert!(yield_vault::get_total_assets(vault_addr) == 400, 0);
        assert!(yield_vault::get_idle_assets(vault_addr) == 400, 1);
        assert!(yield_vault::get_total_shares(vault_addr) == 400, 2);
        assert!(yield_vault::get_deployed_assets(vault_addr) == 0, 3);
        assert!(coin::balance<aptos_coin::AptosCoin>(user_addr) == 600, 4);

        assert!(yield_vault::was_deposit_event_emitted(user_addr, 0, 400, 400), 5);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, user1 = @0x5446, user2 = @0x789, framework = @0x1)]
    public fun test_two_deposits_accumulate(vault_owner: &signer, user1: &signer, user2: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let user1_addr = signer::address_of(user1);
        account::create_account_for_test(user1_addr);
        coin::register<aptos_coin::AptosCoin>(user1);
        coin::deposit(user1_addr, coin::mint(1000, &mint_cap));

        let user2_addr = signer::address_of(user2);
        account::create_account_for_test(user2_addr);
        coin::register<aptos_coin::AptosCoin>(user2);
        coin::deposit(user2_addr, coin::mint(1000, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        yield_vault::deposit(user1, 400, vault_addr);
        yield_vault::deposit(user2, 200, vault_addr);

        assert!(yield_vault::get_total_assets(vault_addr) == 600, 0);
        assert!(yield_vault::get_idle_assets(vault_addr) == 600, 1);
        assert!(yield_vault::get_total_shares(vault_addr) == 600, 2);
        assert!(coin::balance<aptos_coin::AptosCoin>(user1_addr) == 600, 3);
        assert!(coin::balance<aptos_coin::AptosCoin>(user2_addr) == 800, 4);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    // Deposit after yield: total_assets grows without new shares, so new depositor gets fewer shares per coin.
    #[test(vault_owner = @0x123, user1 = @0x5446, user2 = @0x789, framework = @0x1)]
    public fun test_proportional_shares_after_yield(vault_owner: &signer, user1: &signer, user2: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let user1_addr = signer::address_of(user1);
        account::create_account_for_test(user1_addr);
        coin::register<aptos_coin::AptosCoin>(user1);
        coin::deposit(user1_addr, coin::mint(2000, &mint_cap));

        let user2_addr = signer::address_of(user2);
        account::create_account_for_test(user2_addr);
        coin::register<aptos_coin::AptosCoin>(user2);
        coin::deposit(user2_addr, coin::mint(2000, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);

        yield_vault::deposit(user1, 1000, vault_addr);
        yield_vault::simulate_yield(vault_addr, 1000, &mint_cap);
        yield_vault::deposit(user2, 200, vault_addr);

        assert!(yield_vault::get_total_assets(vault_addr) == 2200, 0);
        assert!(yield_vault::get_total_shares(vault_addr) == 1100, 1);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, user = @0x5446, framework = @0x1)]
    #[expected_failure]
    public fun test_deposit_fails_insufficient_balance(vault_owner: &signer, user: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
        coin::register<aptos_coin::AptosCoin>(user);
        coin::deposit(user_addr, coin::mint(50, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        yield_vault::deposit(user, 100, vault_addr);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, user = @0x5446, framework = @0x1)]
    public fun test_withdraw_returns_coins(vault_owner: &signer, user: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
        coin::register<aptos_coin::AptosCoin>(user);
        coin::deposit(user_addr, coin::mint(1000, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        let deposit_obj_addr = yield_vault::deposit(user, 500, vault_addr);

        assert!(coin::balance<aptos_coin::AptosCoin>(user_addr) == 500, 0);

        yield_vault::withdraw(user, deposit_obj_addr, vault_addr);

        assert!(coin::balance<aptos_coin::AptosCoin>(user_addr) == 1000, 1);
        assert!(yield_vault::get_total_assets(vault_addr) == 0, 2);
        assert!(yield_vault::get_total_shares(vault_addr) == 0, 3);
        assert!(yield_vault::get_idle_assets(vault_addr) == 0, 4);

        assert!(yield_vault::was_withdraw_event_emitted(user_addr, 0, 500, 500), 5);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, user1 = @0x5446, framework = @0x1)]
    public fun test_withdraw_with_yield(vault_owner: &signer, user1: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let user1_addr = signer::address_of(user1);
        account::create_account_for_test(user1_addr);
        coin::register<aptos_coin::AptosCoin>(user1);
        coin::deposit(user1_addr, coin::mint(1000, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        let deposit_obj_addr = yield_vault::deposit(user1, 1000, vault_addr);

        yield_vault::simulate_yield(vault_addr, 1000, &mint_cap);

        yield_vault::withdraw(user1, deposit_obj_addr, vault_addr);

        assert!(coin::balance<aptos_coin::AptosCoin>(user1_addr) == 2000, 0);
        assert!(yield_vault::get_total_assets(vault_addr) == 0, 1);
        assert!(yield_vault::get_total_shares(vault_addr) == 0, 2);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, user = @0x5446, framework = @0x1)]
    #[expected_failure(abort_code = 0x50002)]
    public fun test_withdraw_wrong_owner(vault_owner: &signer, user: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
        coin::register<aptos_coin::AptosCoin>(user);
        coin::deposit(user_addr, coin::mint(500, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);
        let deposit_obj_addr = yield_vault::deposit(user, 300, vault_addr);

        yield_vault::withdraw(vault_owner, deposit_obj_addr, vault_addr);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

}
