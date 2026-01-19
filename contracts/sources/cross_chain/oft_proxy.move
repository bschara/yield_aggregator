module YieldAggregator::bridge {
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::signer;
    use std::vector;
    use std::table;
    use layerzero_apps::oft;

    struct Nonce has key {
        last_nonce: u64,
    }

    struct GlobalStore<phantom OFT> has key {
        proxy: bool,
        ld2sd_rate: u64, 
    }

    public entry fun init_proxy_oft<OFT>(admin: &signer, shared_decimals: u8) acquires GlobalStore {
        let lz_cap = oft::init_proxy_oft<OFT>(admin, shared_decimals);
        let decimals = coin::decimals<OFT>();
        move_to(admin, GlobalStore<OFT> {
            proxy: true,
            ld2sd_rate: pow(10, ((decimals - shared_decimals) as u64)),
        });
    }

    public entry fun init_oft<OFT>(
        admin: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        shared_decimals: u8
    ) acquires GlobalStore, oft::CoinCapabilities<OFT> {
        let lz_cap = oft::init_oft<OFT>(admin, name, symbol, decimals, shared_decimals);
        let ld2sd_rate = pow(10, ((decimals - shared_decimals) as u64));
        move_to(admin, GlobalStore<OFT> {
            proxy: false,
            ld2sd_rate,
        });
    }

    public entry fun send<OFT>(
        sender: &signer,
        dst_chain_id: u64,
        dst_receiver: vector<u8>,
        amount: u64,
        min_amount: u64,
        native_fee: u64
    ) acquires GlobalStore, oft::CoinStore<OFT>, oft::CoinCapabilities<OFT> {
        let oft_address = oft::type_address<OFT>();
        let store = borrow_global<GlobalStore<OFT>>(oft_address);

        let coin = coin::withdraw<OFT>(sender, amount);
        let native_coin = if (native_fee > 0) { coin::withdraw<AptosCoin>(sender, native_fee) } else { coin::zero<AptosCoin>() };

        if (store.proxy) {
            let coin_store = borrow_global_mut<oft::CoinStore<OFT>>(oft_address);
            coin::merge(&mut coin_store.locked_coin, coin);
        } else {
            let caps = borrow_global<oft::CoinCapabilities<OFT>>(oft_address);
            coin::burn(coin, &caps.burn_cap);
        };

        oft::send_coin_with_zro<OFT>(
            coin,
            min_amount,
            dst_chain_id,
            dst_receiver,
            native_coin,
            coin::zero<oft::ZRO>(),
            vector::empty<u8>(),
            vector::empty<u8>(),
        );
    }

    public entry fun receive_message<OFT>(
        msg: oft::CrossChainMessage
    ) acquires Nonce, GlobalStore, oft::CoinStore<OFT>, oft::CoinCapabilities<OFT> {
        let nonce_store = borrow_global_mut<Nonce>(msg.target_chain);
        assert!(msg.nonce > nonce_store.last_nonce, 1);
        nonce_store.last_nonce = msg.nonce;

        let oft_address = oft::type_address<OFT>();
        let store = borrow_global<GlobalStore<OFT>>(oft_address);

        let (receiver, amount_sd) = oft::decode_send_payload(&msg.payload);
        let amount = amount_sd * store.ld2sd_rate;

        if (store.proxy) {
            let coin_store = borrow_global_mut<oft::CoinStore<OFT>>(oft_address);
            let coin = coin::extract(&mut coin_store.locked_coin, amount);
            coin::deposit(receiver, coin);
        } else {
            let caps = borrow_global<oft::CoinCapabilities<OFT>>(oft_address);
            let coin = coin::mint<OFT>(amount, &caps.mint_cap);
            coin::deposit(receiver, coin);
        };
    }

    public entry fun init_nonce(chain_id: u64, admin: &signer) {
        move_to(admin, Nonce { last_nonce: 0 });
    }

    fun pow(base: u64, exp: u64): u64 {
        let mut result = 1;
        let mut i = 0;
        while (i < exp) {
            result = result * base;
            i = i + 1;
        };
        result
    }
}
