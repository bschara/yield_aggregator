module YieldAggregator::strategy_tests {
    use std::signer;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use YieldAggregator::yield_vault;
    use YieldAggregator::strategy_registry;
    use YieldAggregator::strategy_executor;

    fun setup(
        vault_owner: &signer,
        adapter: &signer,
        user: &signer,
        framework: &signer,
        max_exposure: u64,
        deposit_amount: u64,
    ): (address, address, coin::BurnCapability<aptos_coin::AptosCoin>, coin::MintCapability<aptos_coin::AptosCoin>) {
        timestamp::set_time_has_started_for_testing(framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(framework);

        let owner_addr = signer::address_of(vault_owner);
        account::create_account_for_test(owner_addr);

        let adapter_addr = signer::address_of(adapter);
        account::create_account_for_test(adapter_addr);
        coin::register<aptos_coin::AptosCoin>(adapter);

        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
        coin::register<aptos_coin::AptosCoin>(user);
        coin::deposit(user_addr, coin::mint(deposit_amount + 1000, &mint_cap));

        yield_vault::init(vault_owner);
        let vault_addr = yield_vault::vault_address(owner_addr);

        strategy_registry::init(vault_owner);
        strategy_registry::add_strategy(vault_owner, owner_addr, adapter_addr, max_exposure, strategy_registry::risk_low());

        yield_vault::deposit(user, deposit_amount, vault_addr);

        (vault_addr, owner_addr, burn_cap, mint_cap)
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, framework = @0x1)]
    public fun test_deploy_to_strategy(
        vault_owner: &signer, adapter: &signer, user: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        yield_vault::deploy_to_strategy(vault_owner, vault_addr, owner_addr, 0, 200);

        assert!(yield_vault::get_idle_assets(vault_addr) == 300, 0);
        assert!(yield_vault::get_deployed_assets(vault_addr) == 200, 1);
        assert!(yield_vault::get_allocation(vault_addr, 0) == 200, 2);

        assert!(yield_vault::was_deploy_event_emitted(0, 200, 0), 3);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, framework = @0x1)]
    public fun test_deploy_total_assets_unchanged(
        vault_owner: &signer, adapter: &signer, user: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        yield_vault::deploy_to_strategy(vault_owner, vault_addr, owner_addr, 0, 200);

        assert!(yield_vault::get_total_assets(vault_addr) == 500, 0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, framework = @0x1)]
    public fun test_recall_from_strategy(
        vault_owner: &signer, adapter: &signer, user: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        yield_vault::deploy_to_strategy(vault_owner, vault_addr, owner_addr, 0, 300);
        yield_vault::recall_from_strategy(vault_owner, vault_addr, owner_addr, 0, 300);

        assert!(yield_vault::get_idle_assets(vault_addr) == 500, 0);
        assert!(yield_vault::get_deployed_assets(vault_addr) == 0, 1);
        assert!(yield_vault::get_allocation(vault_addr, 0) == 0, 2);

        assert!(yield_vault::was_recall_event_emitted(0, 300, 0), 3);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, framework = @0x1)]
    public fun test_partial_recall(
        vault_owner: &signer, adapter: &signer, user: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        yield_vault::deploy_to_strategy(vault_owner, vault_addr, owner_addr, 0, 300);
        yield_vault::recall_from_strategy(vault_owner, vault_addr, owner_addr, 0, 100);

        assert!(yield_vault::get_idle_assets(vault_addr) == 300, 0);
        assert!(yield_vault::get_deployed_assets(vault_addr) == 200, 1);
        assert!(yield_vault::get_allocation(vault_addr, 0) == 200, 2);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, framework = @0x1)]
    #[expected_failure]
    public fun test_deploy_exceeds_max_exposure(
        vault_owner: &signer, adapter: &signer, user: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 100, 500);

        yield_vault::deploy_to_strategy(vault_owner, vault_addr, owner_addr, 0, 200);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, framework = @0x1)]
    #[expected_failure]
    public fun test_deploy_exceeds_idle(
        vault_owner: &signer, adapter: &signer, user: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 10000, 300);

        yield_vault::deploy_to_strategy(vault_owner, vault_addr, owner_addr, 0, 400);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, framework = @0x1)]
    #[expected_failure]
    public fun test_deploy_inactive_strategy(
        vault_owner: &signer, adapter: &signer, user: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        strategy_registry::remove_strategy(vault_owner, owner_addr, 0);
        yield_vault::deploy_to_strategy(vault_owner, vault_addr, owner_addr, 0, 200);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, non_owner = @0x999, framework = @0x1)]
    #[expected_failure(abort_code = 0x5000A)]
    public fun test_deploy_non_operator(
        vault_owner: &signer, adapter: &signer, user: &signer, non_owner: &signer, framework: signer,
    ) {
        account::create_account_for_test(signer::address_of(non_owner));
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        yield_vault::deploy_to_strategy(non_owner, vault_addr, owner_addr, 0, 200);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, framework = @0x1)]
    #[expected_failure]
    public fun test_recall_exceeds_allocation(
        vault_owner: &signer, adapter: &signer, user: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        yield_vault::deploy_to_strategy(vault_owner, vault_addr, owner_addr, 0, 200);
        yield_vault::recall_from_strategy(vault_owner, vault_addr, owner_addr, 0, 300);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, framework = @0x1)]
    public fun test_harvest_strategy(
        vault_owner: &signer, adapter: &signer, user: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        yield_vault::deploy_to_strategy(vault_owner, vault_addr, owner_addr, 0, 200);
        yield_vault::harvest_strategy(vault_owner, vault_addr, owner_addr, 0);

        assert!(yield_vault::was_harvest_event_emitted(0, 0), 0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, engine = @0x400, framework = @0x1)]
    public fun test_set_operator_allows_new_operator(
        vault_owner: &signer, adapter: &signer, user: &signer, engine: &signer, framework: signer,
    ) {
        account::create_account_for_test(signer::address_of(engine));
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        let engine_addr = signer::address_of(engine);
        yield_vault::set_operator(vault_owner, vault_addr, engine_addr);

        yield_vault::deploy_to_strategy(engine, vault_addr, owner_addr, 0, 200);

        assert!(yield_vault::get_deployed_assets(vault_addr) == 200, 0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, non_owner = @0x999, framework = @0x1)]
    #[expected_failure]
    public fun test_set_operator_not_owner(
        vault_owner: &signer, adapter: &signer, user: &signer, non_owner: &signer, framework: signer,
    ) {
        account::create_account_for_test(signer::address_of(non_owner));
        let (vault_addr, _owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, &framework, 1000, 500);

        yield_vault::set_operator(non_owner, vault_addr, signer::address_of(non_owner));

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    fun setup_with_engine(
        vault_owner: &signer,
        adapter: &signer,
        user: &signer,
        engine: &signer,
        framework: &signer,
    ): (address, address, coin::BurnCapability<aptos_coin::AptosCoin>, coin::MintCapability<aptos_coin::AptosCoin>) {
        account::create_account_for_test(signer::address_of(engine));
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup(vault_owner, adapter, user, framework, 1000, 500);

        strategy_executor::init(engine);
        let engine_addr = signer::address_of(engine);
        yield_vault::set_operator(vault_owner, vault_addr, engine_addr);

        (vault_addr, owner_addr, burn_cap, mint_cap)
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, engine = @0x400, framework = @0x1)]
    public fun test_engine_init(
        vault_owner: &signer, adapter: &signer, user: &signer, engine: &signer, framework: signer,
    ) {
        let (_vault_addr, _owner_addr, burn_cap, mint_cap) =
            setup_with_engine(vault_owner, adapter, user, engine, &framework);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, engine = @0x400, framework = @0x1)]
    public fun test_execute_deposit_intent(
        vault_owner: &signer, adapter: &signer, user: &signer, engine: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup_with_engine(vault_owner, adapter, user, engine, &framework);
        let engine_addr = signer::address_of(engine);

        strategy_executor::execute_intent(
            engine,
            engine_addr,
            vault_addr,
            owner_addr,
            strategy_executor::make_deposit_intent(0, 200, 1),
        );

        assert!(yield_vault::get_idle_assets(vault_addr) == 300, 0);
        assert!(yield_vault::get_deployed_assets(vault_addr) == 200, 1);
        assert!(yield_vault::get_allocation(vault_addr, 0) == 200, 2);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, engine = @0x400, framework = @0x1)]
    public fun test_execute_withdraw_intent(
        vault_owner: &signer, adapter: &signer, user: &signer, engine: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup_with_engine(vault_owner, adapter, user, engine, &framework);
        let engine_addr = signer::address_of(engine);

        strategy_executor::execute_intent(
            engine, engine_addr, vault_addr, owner_addr,
            strategy_executor::make_deposit_intent(0, 300, 1),
        );
        strategy_executor::execute_intent(
            engine, engine_addr, vault_addr, owner_addr,
            strategy_executor::make_withdraw_intent(0, 300, 2),
        );

        assert!(yield_vault::get_idle_assets(vault_addr) == 500, 0);
        assert!(yield_vault::get_deployed_assets(vault_addr) == 0, 1);
        assert!(yield_vault::get_allocation(vault_addr, 0) == 0, 2);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, engine = @0x400, framework = @0x1)]
    public fun test_execute_harvest_intent(
        vault_owner: &signer, adapter: &signer, user: &signer, engine: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup_with_engine(vault_owner, adapter, user, engine, &framework);
        let engine_addr = signer::address_of(engine);

        strategy_executor::execute_intent(
            engine, engine_addr, vault_addr, owner_addr,
            strategy_executor::make_deposit_intent(0, 200, 1),
        );
        strategy_executor::execute_intent(
            engine, engine_addr, vault_addr, owner_addr,
            strategy_executor::make_harvest_intent(0, 2),
        );

        assert!(yield_vault::was_harvest_event_emitted(0, 0), 0);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, engine = @0x400, framework = @0x1)]
    #[expected_failure(abort_code = 2)]
    public fun test_nonce_replay_rejected(
        vault_owner: &signer, adapter: &signer, user: &signer, engine: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup_with_engine(vault_owner, adapter, user, engine, &framework);
        let engine_addr = signer::address_of(engine);

        strategy_executor::execute_intent(
            engine, engine_addr, vault_addr, owner_addr,
            strategy_executor::make_deposit_intent(0, 100, 1),
        );
        strategy_executor::execute_intent(
            engine, engine_addr, vault_addr, owner_addr,
            strategy_executor::make_deposit_intent(0, 100, 1),
        );

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, engine = @0x400, non_op = @0x999, framework = @0x1)]
    #[expected_failure(abort_code = 1)]
    public fun test_non_operator_rejected(
        vault_owner: &signer, adapter: &signer, user: &signer, engine: &signer, non_op: &signer, framework: signer,
    ) {
        account::create_account_for_test(signer::address_of(non_op));
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup_with_engine(vault_owner, adapter, user, engine, &framework);
        let engine_addr = signer::address_of(engine);

        strategy_executor::execute_intent(
            non_op, engine_addr, vault_addr, owner_addr,
            strategy_executor::make_deposit_intent(0, 100, 1),
        );

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

    #[test(vault_owner = @0x123, adapter = @0x300, user = @0x456, engine = @0x400, framework = @0x1)]
    public fun test_exit_intent_recalls_funds(
        vault_owner: &signer, adapter: &signer, user: &signer, engine: &signer, framework: signer,
    ) {
        let (vault_addr, owner_addr, burn_cap, mint_cap) =
            setup_with_engine(vault_owner, adapter, user, engine, &framework);
        let engine_addr = signer::address_of(engine);

        strategy_executor::execute_intent(
            engine, engine_addr, vault_addr, owner_addr,
            strategy_executor::make_deposit_intent(0, 400, 1),
        );

        assert!(yield_vault::get_allocation(vault_addr, 0) == 400, 0);

        strategy_executor::execute_intent(
            engine, engine_addr, vault_addr, owner_addr,
            strategy_executor::make_exit_intent(0, 400, 2),
        );

        assert!(yield_vault::get_allocation(vault_addr, 0) == 0, 1);
        assert!(yield_vault::get_deployed_assets(vault_addr) == 0, 2);

        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }
}
