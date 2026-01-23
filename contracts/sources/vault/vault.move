module YieldAggregator::yield_vault{
    use std::error;
    use std::signer;
    use std::vector;
    use std::debug;
    use aptos_framework::object::{Self, Object, DeleteRef, ExtendRef, TransferRef};
    use aptos_framework::event::{Self};
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin;
    use aptos_framework::timestamp;
    use aptos_framework::account;   


    // const NOT_CONTRACT_OWNER: u8 = 1;
    

//implement for later only keep a section of deposits in hot storgae to handle withdrawals and move the rest to hard wallet / multi-sig wallet    
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Treasury has key {
            total_shares: u64,
            vault_balance: u64,
            // deployer_addr: address,
            eth_remote_balance: u64,
            // apt_tokens: coin::CoinStore<AptosCoin>,
            extendRef: ExtendRef,
        } 

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct DepositShares has key {
        deposit_amount: u64,
        deposit_time: u64,
        shares: u64,
        transferRef: TransferRef,
        deleteRef: DeleteRef, 
        creator: address,
    }

    public entry fun init(account: &signer) {

        let name: vector<u8> = b"CrossPlatfromYieldAggregatorVault";
        let constr_ref = object::create_named_object(account, name);
        let extenRef = object::generate_extend_ref(&constr_ref);

        move_to(account, Treasury {
            total_shares: 0,
            vault_balance: 0,
            eth_remote_balance: 0,
            extendRef: extenRef,
        });
    }


    public entry fun deposit(account: &signer, deposit_amount: u64, vault_addr: address) acquires Treasury {
        let creator_addr = signer::address_of(account);

        let coins = coin::withdraw<aptos_coin::AptosCoin>(account, deposit_amount);
        assert!(coin::value(&coins) == deposit_amount, 1); 

        coin::deposit<aptos_coin::AptosCoin>(vault_addr, coins);

        let shares_to_mint = compute_shares(vault_addr, deposit_amount);

        let constructor_ref = object::create_object(creator_addr);
        let transferRef = object::generate_transfer_ref(&constructor_ref);
        let deleteRef = object::generate_delete_ref(&constructor_ref);            

        move_to(account, DepositShares {
            deposit_amount,
            deposit_time: timestamp::now_microseconds(),
            shares: shares_to_mint,
            transferRef,
            deleteRef,
            creator: creator_addr,
        });

        let vault_ref = borrow_global_mut<Treasury>(vault_addr);
        vault_ref.vault_balance = vault_ref.vault_balance + deposit_amount;
        vault_ref.total_shares = vault_ref.total_shares + shares_to_mint;
    }

    fun compute_shares(vault_addr: address, deposit_amount: u64): u64 acquires Treasury {
        let vault_ref = borrow_global<Treasury>(vault_addr);
        if (vault_ref.vault_balance == 0 || vault_ref.total_shares == 0) {
            deposit_amount
        } else {
            ((vault_ref.total_shares + vault_ref.eth_remote_balance) * deposit_amount) / vault_ref.vault_balance
        }
    }


    #[test(arg = @0x123, user = @0x5446, framework = @0x1)]
    public fun test_vault_deposit(arg: &signer, user: &signer, framework: signer) {
        timestamp::set_time_has_started_for_testing(&framework);
        
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework);

        let vault_addr = signer::address_of(arg);
        account::create_account_for_test(vault_addr);
        coin::register<aptos_coin::AptosCoin>(arg);
        
        let user_addr = signer::address_of(user);
        account::create_account_for_test(user_addr);
        coin::register<aptos_coin::AptosCoin>(user);


        let coins = coin::mint(10000, &mint_cap);
        coin::deposit(vault_addr, coins);

        let coins = coin::mint(1000, &mint_cap);
        coin::deposit(user_addr, coins);
        
        init(arg);
        
        deposit(user, 100, vault_addr);
        
        let user_balance = coin::balance<aptos_coin::AptosCoin>(user_addr);
        debug::print(&user_balance);
        assert!(user_balance < 901);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);
    }

}