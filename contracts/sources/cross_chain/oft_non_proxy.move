module YieldAggregator::non_proxy_oft{

public entry fun init(admin: &signer)


public entry fun send_usdc(
    user: &signer,
    dst_chain_id: u64,
    dst_receiver: vector<u8>,
    amount: u64,
    min_amount: u64,
    native_fee: u64
)

}