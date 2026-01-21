module YieldAggregator::cross_chain_message{


//implement cross chain messaging to pass strategy instructions to adapters on other chains

struct Intent {
    nonce: u64,
    strategy_id: u64,
    action: u8,
    asset: address,
    amount: u64,
    expiry: u64,
}


public fun verify(
    src_chain_id: u64,
    intent: &Intent,
    signature: vector<u8>
)
{}
}