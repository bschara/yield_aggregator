module YieldAggregator::vault_tests {
    use std::signer;
    use std::debug;
    use YieldAggregator::vault;
    use YieldAggregator::router;

    #[test(account = @0x1)]
    public fun test_vault_deposit() {
        let user_addr = @0x1;

        // Initialize vault
        vault::init(&signer::borrow_address(&user_addr));

        // Deposit 100 units via router
        router::deposit(&signer::borrow_address(&user_addr), 100);

        // Check shares
        let shares = vault::get_shares(user_addr);
        debug::print(&shares);
        assert!(shares == 100, 0);

        let (assets, total_shares) = vault::get_vault_state();
        assert!(assets == 100, 1);
        assert!(total_shares == 100, 2);
    }

    #[test(account = @0x2)]
    public fun test_multiple_deposits() {
        let user1 = @0x1;
        let user2 = @0x2;

        // Initialize vault for user1
        vault::init(&signer::borrow_address(&user1));

        // Deposit from both users
        router::deposit(&signer::borrow_address(&user1), 100);
        router::deposit(&signer::borrow_address(&user2), 100);

        let shares1 = vault::get_shares(user1);
        let shares2 = vault::get_shares(user2);

        debug::print(&shares1);
        debug::print(&shares2);

        assert!(shares1 == 100, 0);
        assert!(shares2 == 100, 1);

        let (assets, total_shares) = vault::get_vault_state();
        assert!(assets == 200, 2);
        assert!(total_shares == 200, 3);
    }

    #[test(account = @0x1)]
    public fun test_withdraw() {
        let user = @0x1;

        vault::init(&signer::borrow_address(&user));

        router::deposit(&signer::borrow_address(&user), 100);

        // Withdraw 50
        vault::withdraw(&signer::borrow_address(&user), 50);

        let shares = vault::get_shares(user);
        let (assets, total_shares) = vault::get_vault_state();

        debug::print(&shares);
        debug::print(&assets);
        debug::print(&total_shares);

        assert!(shares == 50, 0);
        assert!(assets == 50, 1);
        assert!(total_shares == 50, 2);
    }
}
