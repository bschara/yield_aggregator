module YieldAggregator::registry_tests {
    use std::signer;
    use std::option;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use YieldAggregator::strategy_registry;

    #[test(owner = @0x200, framework = @0x1)]
    public fun test_registry_init(owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(owner);
        account::create_account_for_test(owner_addr);

        strategy_registry::init(owner);

        assert!(!strategy_registry::strategy_exists(owner_addr, 0), 0);
    }

    #[test(owner = @0x200, framework = @0x1)]
    public fun test_add_strategy(owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(owner);
        account::create_account_for_test(owner_addr);

        strategy_registry::init(owner);

        let adapter_addr = @0x300;
        strategy_registry::add_strategy(owner, owner_addr, adapter_addr, 1000, strategy_registry::risk_low());

        assert!(strategy_registry::strategy_exists(owner_addr, 0), 0);
        assert!(strategy_registry::is_active(owner_addr, 0), 1);
        assert!(strategy_registry::get_adapter(owner_addr, 0) == adapter_addr, 2);
        assert!(strategy_registry::get_max_exposure(owner_addr, 0) == 1000, 3);
        assert!(!strategy_registry::strategy_exists(owner_addr, 1), 4);
    }

    #[test(owner = @0x200, framework = @0x1)]
    public fun test_add_two_strategies_sequential_ids(owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(owner);
        account::create_account_for_test(owner_addr);

        strategy_registry::init(owner);
        strategy_registry::add_strategy(owner, owner_addr, @0x301, 500, strategy_registry::risk_low());
        strategy_registry::add_strategy(owner, owner_addr, @0x302, 800, strategy_registry::risk_medium());

        assert!(strategy_registry::strategy_exists(owner_addr, 0), 0);
        assert!(strategy_registry::strategy_exists(owner_addr, 1), 1);
        assert!(strategy_registry::get_adapter(owner_addr, 0) == @0x301, 2);
        assert!(strategy_registry::get_adapter(owner_addr, 1) == @0x302, 3);
        assert!(!strategy_registry::strategy_exists(owner_addr, 2), 4);
    }

    #[test(owner = @0x200, framework = @0x1)]
    public fun test_update_strategy_max_exposure(owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(owner);
        account::create_account_for_test(owner_addr);

        strategy_registry::init(owner);
        strategy_registry::add_strategy(owner, owner_addr, @0x300, 1000, strategy_registry::risk_low());

        strategy_registry::update_strategy(
            owner,
            owner_addr,
            0,
            option::none(),
            option::some(2000),
            option::none(),
        );

        assert!(strategy_registry::get_max_exposure(owner_addr, 0) == 2000, 0);
        assert!(strategy_registry::get_adapter(owner_addr, 0) == @0x300, 1);
        assert!(strategy_registry::is_active(owner_addr, 0), 2);
    }

    #[test(owner = @0x200, framework = @0x1)]
    public fun test_update_strategy_deactivate(owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(owner);
        account::create_account_for_test(owner_addr);

        strategy_registry::init(owner);
        strategy_registry::add_strategy(owner, owner_addr, @0x300, 1000, strategy_registry::risk_low());

        strategy_registry::update_strategy(
            owner,
            owner_addr,
            0,
            option::none(),
            option::none(),
            option::some(false),
        );

        assert!(!strategy_registry::is_active(owner_addr, 0), 0);
    }

    #[test(owner = @0x200, framework = @0x1)]
    public fun test_remove_strategy(owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(owner);
        account::create_account_for_test(owner_addr);

        strategy_registry::init(owner);
        strategy_registry::add_strategy(owner, owner_addr, @0x300, 1000, strategy_registry::risk_low());

        assert!(strategy_registry::is_active(owner_addr, 0), 0);

        strategy_registry::remove_strategy(owner, owner_addr, 0);

        assert!(!strategy_registry::is_active(owner_addr, 0), 1);
    }

    #[test(owner = @0x200, non_owner = @0x201, framework = @0x1)]
    #[expected_failure(abort_code = 1)]
    public fun test_add_strategy_not_owner(owner: &signer, non_owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(owner);
        account::create_account_for_test(owner_addr);
        account::create_account_for_test(signer::address_of(non_owner));

        strategy_registry::init(owner);
        strategy_registry::add_strategy(non_owner, owner_addr, @0x300, 1000, strategy_registry::risk_low());
    }

    #[test(owner = @0x200, non_owner = @0x201, framework = @0x1)]
    #[expected_failure(abort_code = 1)]
    public fun test_update_strategy_not_owner(owner: &signer, non_owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(owner);
        account::create_account_for_test(owner_addr);
        account::create_account_for_test(signer::address_of(non_owner));

        strategy_registry::init(owner);
        strategy_registry::add_strategy(owner, owner_addr, @0x300, 1000, strategy_registry::risk_low());

        strategy_registry::update_strategy(
            non_owner,
            owner_addr,
            0,
            option::none(),
            option::some(500),
            option::none(),
        );
    }

    #[test(owner = @0x200, non_owner = @0x201, framework = @0x1)]
    #[expected_failure(abort_code = 1)]
    public fun test_remove_strategy_not_owner(owner: &signer, non_owner: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        let owner_addr = signer::address_of(owner);
        account::create_account_for_test(owner_addr);
        account::create_account_for_test(signer::address_of(non_owner));

        strategy_registry::init(owner);
        strategy_registry::add_strategy(owner, owner_addr, @0x300, 1000, strategy_registry::risk_low());

        strategy_registry::remove_strategy(non_owner, owner_addr, 0);
    }
}
