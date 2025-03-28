#[test_only]
module warpgate::test_utils {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::genesis;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::resource_account;
    use warpgate::swap::{Self, initialize};
    use warpgate::math;

    const MINIMUM_LIQUIDITY: u128 = 1000;

    public fun setup_test_with_genesis(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        // Initialize framework account first
        genesis::setup();
        setup_test(dev, admin, treasury, resource_account);
    }

    public fun setup_test(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        // Initialize required accounts if they don't exist
        account::create_account_for_test(signer::address_of(dev));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(treasury));
        account::create_account_for_test(@lpfee);
        account::create_account_for_test(@mmfee);
        resource_account::create_resource_account(dev, b"warpgate", x"");
        
        // Initialize DEX
        initialize(resource_account);
        
        // Set fee recipient
        swap::set_fee_to(admin, signer::address_of(treasury));
    }

    public fun get_token_reserves(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): (u64, u64) {
        let (reserve_x, reserve_y, _) = swap::token_reserves(token_x, token_y);
        (reserve_x, reserve_y)
    }

    public fun calc_output_using_input(
        input_x: u64,
        reserve_x: u64,
        reserve_y: u64
    ): u128 {
        ((input_x as u128) * 9975u128 * (reserve_y as u128)) / (((reserve_x as u128) * 10000u128) + ((input_x as u128) * 9975u128))
    }

    public fun calc_input_using_output(
        output_y: u64,
        reserve_x: u64,
        reserve_y: u64
    ): u128 {
        ((output_y as u128) * 10000u128 * (reserve_x as u128)) / (9975u128 * ((reserve_y as u128) - (output_y as u128))) + 1u128
    }

    public fun calc_fee_lp(
        total_lp_supply: u128,
        k: u128,
        k_last: u128,
    ): u128 {
        let root_k = math::sqrt(k);
        let root_k_last = math::sqrt(k_last);

        let numerator = total_lp_supply * (root_k - root_k_last) * 8u128;
        let denominator = root_k_last * 17u128 + (root_k * 8u128);
        let liquidity = numerator / denominator;
        liquidity
    }
}