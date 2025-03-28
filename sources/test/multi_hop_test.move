/*
#[test_only]
module warpgate::multi_swap_test {
    use std::signer;
    use test_coin::test_coins::{Self, TestWARP, TestBUSD, TestUSDC, TestBNB, TestAPT};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::genesis;
    use aptos_framework::resource_account;
    use warpgate::swap::{Self, LPToken, initialize};
    use warpgate::router;
    use warpgate::math;
    use aptos_std::math64::pow;
    use warpgate::swap_utils;
    use warpgate::test_utils;

    const MAX_U64: u64 = 18446744073709551615;
    const MINIMUM_LIQUIDITY: u128 = 1000;

    public fun setup_test_with_genesis(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        test_utils::setup_test_with_genesis(dev, admin, treasury, resource_account);
    }

    public fun setup_test(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        test_utils::setup_test(dev, admin, treasury, resource_account);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_input_doublehop(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestUSDC>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_xy_x = 5 * pow(10, 8);
        let initial_reserve_xy_y = 10 * pow(10, 8);
        let initial_reserve_yz_y = 5 * pow(10, 8);
        let initial_reserve_yz_z = 10 * pow(10, 8);
        let input_x = 1 * pow(10, 8);

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);
        coin::register<TestUSDC>(&mm_fee_signer);

        // bob provider liquidity for 1:2 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_xy_x, initial_reserve_xy_y, 0, 0, 25);
        let bob_suppose_xy_lp_balance = math::sqrt(((initial_reserve_xy_x as u128) * (initial_reserve_xy_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_xy_total_supply = bob_suppose_xy_lp_balance + MINIMUM_LIQUIDITY;
        // bob provider liquidity for 2:1 USDC-BUSD
        router::add_liquidity<TestUSDC, TestBUSD>(bob, initial_reserve_yz_z, initial_reserve_yz_y, 0, 0, 25);
        let bob_suppose_yz_lp_balance = math::sqrt(((initial_reserve_yz_y as u128) * (initial_reserve_yz_z as u128))) - MINIMUM_LIQUIDITY;
        let suppose_yz_total_supply = bob_suppose_yz_lp_balance + MINIMUM_LIQUIDITY;

        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));

        router::swap_exact_input_doublehop<TestWARP, TestBUSD, TestUSDC>(alice, input_x, 0);

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_z_after_balance = coin::balance<TestUSDC>(signer::address_of(alice));
        // Calculate fee
        let fee_amount = (input_x as u128) * 25 / 10000;
        let amount_after_fee = input_x - (fee_amount as u64);
        let output_y = test_utils::calc_output_using_input(amount_after_fee, initial_reserve_xy_x, initial_reserve_xy_y);
        let output_z = test_utils::calc_output_using_input((output_y as u64), initial_reserve_yz_y, initial_reserve_yz_z);
        let new_reserve_xy_x = initial_reserve_xy_x + amount_after_fee;
        let new_reserve_xy_y = initial_reserve_xy_y - (output_y as u64);
        let new_reserve_yz_y = initial_reserve_yz_y + (output_y as u64);
        let new_reserve_yz_z = initial_reserve_yz_z - (output_z as u64);

        let (reserve_xy_y, reserve_xy_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        let (reserve_yz_y, reserve_yz_z, _) = swap::token_reserves<TestBUSD, TestUSDC>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == input_x, 99);
        assert!(alice_token_z_after_balance == (output_z as u64), 98);
        assert!(reserve_xy_x == new_reserve_xy_x, 97);
        assert!(reserve_xy_y == new_reserve_xy_y, 96);
        assert!(reserve_yz_y == new_reserve_yz_y, 97);
        assert!(reserve_yz_z == new_reserve_yz_z, 96);

        let bob_token_xy_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_xy_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_xy_lp_balance as u64), 0, 0);

        let bob_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let suppose_xy_k_last = ((initial_reserve_xy_x * initial_reserve_xy_y) as u128);
        let suppose_xy_k = ((new_reserve_xy_x * new_reserve_xy_y) as u128);
        let suppose_xy_fee_amount = test_utils::calc_fee_lp(suppose_xy_total_supply, suppose_xy_k, suppose_xy_k_last);
        suppose_xy_total_supply = suppose_xy_total_supply + suppose_xy_fee_amount;

        let bob_token_yz_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_token_yz_z_before_balance = coin::balance<TestUSDC>(signer::address_of(bob));

        router::remove_liquidity<TestBUSD, TestUSDC>(bob, (bob_suppose_yz_lp_balance as u64), 0, 0);

        let bob_token_yz_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_token_yz_z_after_balance = coin::balance<TestUSDC>(signer::address_of(bob));

        let suppose_yz_k_last = ((initial_reserve_yz_y * initial_reserve_yz_z) as u128);
        let suppose_yz_k = ((new_reserve_yz_y * new_reserve_yz_z) as u128);
        let suppose_yz_fee_amount = test_utils::calc_fee_lp(suppose_yz_total_supply, suppose_yz_k, suppose_yz_k_last);
        suppose_yz_total_supply = suppose_yz_total_supply + suppose_yz_fee_amount;

        let bob_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * bob_suppose_xy_lp_balance / suppose_xy_total_supply;
        let bob_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * bob_suppose_xy_lp_balance / suppose_xy_total_supply;
        new_reserve_xy_x = new_reserve_xy_x - (bob_remove_liquidity_xy_x as u64);
        new_reserve_xy_y = new_reserve_xy_y - (bob_remove_liquidity_xy_y as u64);
        suppose_xy_total_supply = suppose_xy_total_supply - bob_suppose_xy_lp_balance;

        assert!((bob_token_xy_x_after_balance - bob_token_xy_x_before_balance) == (bob_remove_liquidity_xy_x as u64), 95);
        assert!((bob_token_xy_y_after_balance - bob_token_xy_y_before_balance) == (bob_remove_liquidity_xy_y as u64), 94);

        let bob_remove_liquidity_yz_y = ((new_reserve_yz_y) as u128) * bob_suppose_yz_lp_balance / suppose_yz_total_supply;
        let bob_remove_liquidity_yz_z = ((new_reserve_yz_z) as u128) * bob_suppose_yz_lp_balance / suppose_yz_total_supply;
        new_reserve_yz_y = new_reserve_yz_y - (bob_remove_liquidity_yz_y as u64);
        new_reserve_yz_z = new_reserve_yz_z - (bob_remove_liquidity_yz_z as u64);
        suppose_yz_total_supply = suppose_yz_total_supply - bob_suppose_yz_lp_balance;

        assert!((bob_token_yz_y_after_balance - bob_token_yz_y_before_balance) == (bob_remove_liquidity_yz_y as u64), 95);
        assert!((bob_token_yz_z_after_balance - bob_token_yz_z_before_balance) == (bob_remove_liquidity_yz_z as u64), 94);

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
        let treasury_xy_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_xy_fee_amount as u64), 0, 0);
        let treasury_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;
        let treasury_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;

        assert!(treasury_xy_lp_after_balance == (suppose_xy_fee_amount as u64), 93);
        assert!(treasury_token_xy_x_after_balance == (treasury_remove_liquidity_xy_x as u64), 92);
        assert!(treasury_token_xy_y_after_balance == (treasury_remove_liquidity_xy_y as u64), 91);

        swap::withdraw_fee<TestBUSD, TestUSDC>(treasury);
        let treasury_yz_lp_after_balance = coin::balance<LPToken<TestBUSD, TestUSDC>>(signer::address_of(treasury));
        router::remove_liquidity<TestBUSD, TestUSDC>(treasury, (suppose_yz_fee_amount as u64), 0, 0);
        let treasury_token_yz_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));
        let treasury_token_yz_z_after_balance = coin::balance<TestUSDC>(signer::address_of(treasury));

        let treasury_remove_liquidity_yz_y = ((new_reserve_yz_y) as u128) * suppose_yz_fee_amount / suppose_yz_total_supply;
        let treasury_remove_liquidity_yz_z = ((new_reserve_yz_z) as u128) * suppose_yz_fee_amount / suppose_yz_total_supply;

        assert!(treasury_yz_lp_after_balance == (suppose_yz_fee_amount as u64), 93);
        assert!((treasury_token_yz_y_after_balance - treasury_token_xy_y_after_balance) == (treasury_remove_liquidity_yz_y as u64), 92);
        assert!(treasury_token_yz_z_after_balance == (treasury_remove_liquidity_yz_z as u64), 91);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun swap_exact_output_doublehop(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestUSDC>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_xy_x = 5 * pow(10, 8);
        let initial_reserve_xy_y = 10 * pow(10, 8);
        let initial_reserve_yz_y = 5 * pow(10, 8);
        let initial_reserve_yz_z = 10 * pow(10, 8);
        let output_z = 249140454;

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);
        coin::register<TestUSDC>(&mm_fee_signer);
        

        // bob provider liquidity for 1:2 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_xy_x, initial_reserve_xy_y, 0, 0, 25);
        let bob_suppose_xy_lp_balance = math::sqrt(((initial_reserve_xy_x as u128) * (initial_reserve_xy_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_xy_total_supply = bob_suppose_xy_lp_balance + MINIMUM_LIQUIDITY;
        // bob provider liquidity for 2:1 USDC-BUSD
        router::add_liquidity<TestUSDC, TestBUSD>(bob, initial_reserve_yz_z, initial_reserve_yz_y, 0, 0, 25);
        let bob_suppose_yz_lp_balance = math::sqrt(((initial_reserve_yz_y as u128) * (initial_reserve_yz_z as u128))) - MINIMUM_LIQUIDITY;
        let suppose_yz_total_supply = bob_suppose_yz_lp_balance + MINIMUM_LIQUIDITY;

        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));

        router::swap_exact_output_doublehop<TestWARP, TestBUSD, TestUSDC>(alice, output_z, 1 * pow(10, 8));

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_z_after_balance = coin::balance<TestUSDC>(signer::address_of(alice));

        let output_y = test_utils::calc_input_using_output(output_z, initial_reserve_yz_y, initial_reserve_yz_z);
        let input_x = test_utils::calc_input_using_output((output_y as u64), initial_reserve_xy_x, initial_reserve_xy_y);
        let new_reserve_xy_x = initial_reserve_xy_x + (input_x as u64);
        let new_reserve_xy_y = initial_reserve_xy_y - (output_y as u64);
        let new_reserve_yz_y = initial_reserve_yz_y + (output_y as u64);
        let new_reserve_yz_z = initial_reserve_yz_z - (output_z as u64);

        let (reserve_xy_y, reserve_xy_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        let (reserve_yz_y, reserve_yz_z, _) = swap::token_reserves<TestBUSD, TestUSDC>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == (input_x as u64), 99);
        assert!(alice_token_z_after_balance == output_z, 98);
        assert!(reserve_xy_x == new_reserve_xy_x, 97);
        assert!(reserve_xy_y == new_reserve_xy_y, 96);
        assert!(reserve_yz_y == new_reserve_yz_y, 97);
        assert!(reserve_yz_z == new_reserve_yz_z, 96);

        let bob_token_xy_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_xy_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_xy_lp_balance as u64), 0, 0);

        let bob_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let suppose_xy_k_last = ((initial_reserve_xy_x * initial_reserve_xy_y) as u128);
        let suppose_xy_k = ((new_reserve_xy_x * new_reserve_xy_y) as u128);
        let suppose_xy_fee_amount = test_utils::calc_fee_lp(suppose_xy_total_supply, suppose_xy_k, suppose_xy_k_last);
        suppose_xy_total_supply = suppose_xy_total_supply + suppose_xy_fee_amount;

        let bob_token_yz_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_token_yz_z_before_balance = coin::balance<TestUSDC>(signer::address_of(bob));

        router::remove_liquidity<TestBUSD, TestUSDC>(bob, (bob_suppose_yz_lp_balance as u64), 0, 0);

        let bob_token_yz_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_token_yz_z_after_balance = coin::balance<TestUSDC>(signer::address_of(bob));

        let suppose_yz_k_last = ((initial_reserve_yz_y * initial_reserve_yz_z) as u128);
        let suppose_yz_k = ((new_reserve_yz_y * new_reserve_yz_z) as u128);
        let suppose_yz_fee_amount = test_utils::calc_fee_lp(suppose_yz_total_supply, suppose_yz_k, suppose_yz_k_last);
        suppose_yz_total_supply = suppose_yz_total_supply + suppose_yz_fee_amount;

        let bob_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * bob_suppose_xy_lp_balance / suppose_xy_total_supply;
        let bob_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * bob_suppose_xy_lp_balance / suppose_xy_total_supply;
        new_reserve_xy_x = new_reserve_xy_x - (bob_remove_liquidity_xy_x as u64);
        new_reserve_xy_y = new_reserve_xy_y - (bob_remove_liquidity_xy_y as u64);
        suppose_xy_total_supply = suppose_xy_total_supply - bob_suppose_xy_lp_balance;

        assert!((bob_token_xy_x_after_balance - bob_token_xy_x_before_balance) == (bob_remove_liquidity_xy_x as u64), 95);
        assert!((bob_token_xy_y_after_balance - bob_token_xy_y_before_balance) == (bob_remove_liquidity_xy_y as u64), 94);

        let bob_remove_liquidity_yz_y = ((new_reserve_yz_y) as u128) * bob_suppose_yz_lp_balance / suppose_yz_total_supply;
        let bob_remove_liquidity_yz_z = ((new_reserve_yz_z) as u128) * bob_suppose_yz_lp_balance / suppose_yz_total_supply;
        new_reserve_yz_y = new_reserve_yz_y - (bob_remove_liquidity_yz_y as u64);
        new_reserve_yz_z = new_reserve_yz_z - (bob_remove_liquidity_yz_z as u64);
        suppose_yz_total_supply = suppose_yz_total_supply - bob_suppose_yz_lp_balance;

        assert!((bob_token_yz_y_after_balance - bob_token_yz_y_before_balance) == (bob_remove_liquidity_yz_y as u64), 95);
        assert!((bob_token_yz_z_after_balance - bob_token_yz_z_before_balance) == (bob_remove_liquidity_yz_z as u64), 94);

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
        let treasury_xy_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_xy_fee_amount as u64), 0, 0);
        let treasury_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;
        let treasury_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;

        assert!(treasury_xy_lp_after_balance == (suppose_xy_fee_amount as u64), 93);
        assert!(treasury_token_xy_x_after_balance == (treasury_remove_liquidity_xy_x as u64), 92);
        assert!(treasury_token_xy_y_after_balance == (treasury_remove_liquidity_xy_y as u64), 91);

        swap::withdraw_fee<TestBUSD, TestUSDC>(treasury);
        let treasury_yz_lp_after_balance = coin::balance<LPToken<TestBUSD, TestUSDC>>(signer::address_of(treasury));
        router::remove_liquidity<TestBUSD, TestUSDC>(treasury, (suppose_yz_fee_amount as u64), 0, 0);
        let treasury_token_yz_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));
        let treasury_token_yz_z_after_balance = coin::balance<TestUSDC>(signer::address_of(treasury));

        let treasury_remove_liquidity_yz_y = ((new_reserve_yz_y) as u128) * suppose_yz_fee_amount / suppose_yz_total_supply;
        let treasury_remove_liquidity_yz_z = ((new_reserve_yz_z) as u128) * suppose_yz_fee_amount / suppose_yz_total_supply;

        assert!(treasury_yz_lp_after_balance == (suppose_yz_fee_amount as u64), 93);
        assert!((treasury_token_yz_y_after_balance - treasury_token_xy_y_after_balance) == (treasury_remove_liquidity_yz_y as u64), 92);
        assert!(treasury_token_yz_z_after_balance == (treasury_remove_liquidity_yz_z as u64), 91);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_input_triplehop(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestUSDC>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBNB>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_xy_x = 5 * pow(10, 8);
        let initial_reserve_xy_y = 10 * pow(10, 8);
        let initial_reserve_yz_y = 5 * pow(10, 8);
        let initial_reserve_yz_z = 10 * pow(10, 8);
        let initial_reserve_za_z = 10 * pow(10, 8);
        let initial_reserve_za_a = 15 * pow(10, 8);
        let input_x = 1 * pow(10, 8);

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);
        coin::register<TestUSDC>(&mm_fee_signer);
        coin::register<TestBNB>(&mm_fee_signer);


        // bob provider liquidity for 1:2 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_xy_x, initial_reserve_xy_y, 0, 0, 25);
        let bob_suppose_xy_lp_balance = math::sqrt(((initial_reserve_xy_x as u128) * (initial_reserve_xy_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_xy_total_supply = bob_suppose_xy_lp_balance + MINIMUM_LIQUIDITY;
        // bob provider liquidity for 2:1 USDC-BUSD
        router::add_liquidity<TestUSDC, TestBUSD>(bob, initial_reserve_yz_z, initial_reserve_yz_y, 0, 0, 25);
        let bob_suppose_yz_lp_balance = math::sqrt(((initial_reserve_yz_y as u128) * (initial_reserve_yz_z as u128))) - MINIMUM_LIQUIDITY;
        let suppose_yz_total_supply = bob_suppose_yz_lp_balance + MINIMUM_LIQUIDITY;
        // bob provider liquidity for 2:3 USDC-BUSD
        router::add_liquidity<TestUSDC, TestBNB>(bob, initial_reserve_za_z, initial_reserve_za_a, 0, 0, 25);
        let bob_suppose_za_lp_balance = math::sqrt(((initial_reserve_za_z as u128) * (initial_reserve_za_a as u128))) - MINIMUM_LIQUIDITY;
        let suppose_za_total_supply = bob_suppose_za_lp_balance + MINIMUM_LIQUIDITY;

        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));

        router::swap_exact_input_triplehop<TestWARP, TestBUSD, TestUSDC, TestBNB>(alice, input_x, 0);

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_a_after_balance = coin::balance<TestBNB>(signer::address_of(alice));
        // Calculate fee
        let fee_amount = (input_x as u128) * 25 / 10000;
        let amount_after_fee = input_x - (fee_amount as u64);
        let output_y = test_utils::calc_output_using_input(amount_after_fee, initial_reserve_xy_x, initial_reserve_xy_y);
        let output_z = test_utils::calc_output_using_input((output_y as u64), initial_reserve_yz_y, initial_reserve_yz_z);
        let output_a = test_utils::calc_output_using_input((output_z as u64), initial_reserve_za_z, initial_reserve_za_a);
        let new_reserve_xy_x = initial_reserve_xy_x + amount_after_fee;
        let new_reserve_xy_y = initial_reserve_xy_y - (output_y as u64);
        let new_reserve_yz_y = initial_reserve_yz_y + (output_y as u64);
        let new_reserve_yz_z = initial_reserve_yz_z - (output_z as u64);
        let new_reserve_za_z = initial_reserve_za_z + (output_z as u64);
        let new_reserve_za_a = initial_reserve_za_a - (output_a as u64);

        let (reserve_xy_y, reserve_xy_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        let (reserve_yz_y, reserve_yz_z, _) = swap::token_reserves<TestBUSD, TestUSDC>();
        let (reserve_za_a, reserve_za_z, _) = swap::token_reserves<TestBNB, TestUSDC>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == input_x, 99);
        assert!(alice_token_a_after_balance == (output_a as u64), 98);
        assert!(reserve_xy_x == new_reserve_xy_x, 97);
        assert!(reserve_xy_y == new_reserve_xy_y, 96);
        assert!(reserve_yz_y == new_reserve_yz_y, 97);
        assert!(reserve_yz_z == new_reserve_yz_z, 96);
        assert!(reserve_za_z == new_reserve_za_z, 97);
        assert!(reserve_za_a == new_reserve_za_a, 96);

        let bob_token_xy_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_xy_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_xy_lp_balance as u64), 0, 0);

        let bob_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let suppose_xy_k_last = ((initial_reserve_xy_x * initial_reserve_xy_y) as u128);
        let suppose_xy_k = ((new_reserve_xy_x * new_reserve_xy_y) as u128);
        let suppose_xy_fee_amount = test_utils::calc_fee_lp(suppose_xy_total_supply, suppose_xy_k, suppose_xy_k_last);
        suppose_xy_total_supply = suppose_xy_total_supply + suppose_xy_fee_amount;

        let bob_token_yz_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_token_yz_z_before_balance = coin::balance<TestUSDC>(signer::address_of(bob));

        router::remove_liquidity<TestBUSD, TestUSDC>(bob, (bob_suppose_yz_lp_balance as u64), 0, 0);

        let bob_token_yz_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_token_yz_z_after_balance = coin::balance<TestUSDC>(signer::address_of(bob));

        let suppose_yz_k_last = ((initial_reserve_yz_y * initial_reserve_yz_z) as u128);
        let suppose_yz_k = ((new_reserve_yz_y * new_reserve_yz_z) as u128);
        let suppose_yz_fee_amount = test_utils::calc_fee_lp(suppose_yz_total_supply, suppose_yz_k, suppose_yz_k_last);
        suppose_yz_total_supply = suppose_yz_total_supply + suppose_yz_fee_amount;

        let bob_token_za_z_before_balance = coin::balance<TestUSDC>(signer::address_of(bob));
        let bob_token_za_a_before_balance = coin::balance<TestBNB>(signer::address_of(bob));

        router::remove_liquidity<TestUSDC, TestBNB>(bob, (bob_suppose_za_lp_balance as u64), 0, 0);

        let bob_token_za_z_after_balance = coin::balance<TestUSDC>(signer::address_of(bob));
        let bob_token_za_a_after_balance = coin::balance<TestBNB>(signer::address_of(bob));

        let suppose_za_k_last = ((initial_reserve_za_z * initial_reserve_za_a) as u128);
        let suppose_za_k = ((new_reserve_za_z * new_reserve_za_a) as u128);
        let suppose_za_fee_amount = test_utils::calc_fee_lp(suppose_za_total_supply, suppose_za_k, suppose_za_k_last);
        suppose_za_total_supply = suppose_za_total_supply + suppose_za_fee_amount;

        let bob_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * bob_suppose_xy_lp_balance / suppose_xy_total_supply;
        let bob_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * bob_suppose_xy_lp_balance / suppose_xy_total_supply;
        new_reserve_xy_x = new_reserve_xy_x - (bob_remove_liquidity_xy_x as u64);
        new_reserve_xy_y = new_reserve_xy_y - (bob_remove_liquidity_xy_y as u64);
        suppose_xy_total_supply = suppose_xy_total_supply - bob_suppose_xy_lp_balance;

        assert!((bob_token_xy_x_after_balance - bob_token_xy_x_before_balance) == (bob_remove_liquidity_xy_x as u64), 95);
        assert!((bob_token_xy_y_after_balance - bob_token_xy_y_before_balance) == (bob_remove_liquidity_xy_y as u64), 94);

        let bob_remove_liquidity_yz_y = ((new_reserve_yz_y) as u128) * bob_suppose_yz_lp_balance / suppose_yz_total_supply;
        let bob_remove_liquidity_yz_z = ((new_reserve_yz_z) as u128) * bob_suppose_yz_lp_balance / suppose_yz_total_supply;
        new_reserve_yz_y = new_reserve_yz_y - (bob_remove_liquidity_yz_y as u64);
        new_reserve_yz_z = new_reserve_yz_z - (bob_remove_liquidity_yz_z as u64);
        suppose_yz_total_supply = suppose_yz_total_supply - bob_suppose_yz_lp_balance;

        assert!((bob_token_yz_y_after_balance - bob_token_yz_y_before_balance) == (bob_remove_liquidity_yz_y as u64), 95);
        assert!((bob_token_yz_z_after_balance - bob_token_yz_z_before_balance) == (bob_remove_liquidity_yz_z as u64), 94);

        let bob_remove_liquidity_za_z = ((new_reserve_za_z) as u128) * bob_suppose_za_lp_balance / suppose_za_total_supply;
        let bob_remove_liquidity_za_a = ((new_reserve_za_a) as u128) * bob_suppose_za_lp_balance / suppose_za_total_supply;
        new_reserve_za_z = new_reserve_za_z - (bob_remove_liquidity_za_z as u64);
        new_reserve_za_a = new_reserve_za_a - (bob_remove_liquidity_za_a as u64);
        suppose_za_total_supply = suppose_za_total_supply - bob_suppose_za_lp_balance;

        assert!((bob_token_za_z_after_balance - bob_token_za_z_before_balance) == (bob_remove_liquidity_za_z as u64), 95);
        assert!((bob_token_za_a_after_balance - bob_token_za_a_before_balance) == (bob_remove_liquidity_za_a as u64), 94);

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
        let treasury_xy_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_xy_fee_amount as u64), 0, 0);
        let treasury_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;
        let treasury_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;

        assert!(treasury_xy_lp_after_balance == (suppose_xy_fee_amount as u64), 93);
        assert!(treasury_token_xy_x_after_balance == (treasury_remove_liquidity_xy_x as u64), 92);
        assert!(treasury_token_xy_y_after_balance == (treasury_remove_liquidity_xy_y as u64), 91);

        swap::withdraw_fee<TestBUSD, TestUSDC>(treasury);
        let treasury_yz_lp_after_balance = coin::balance<LPToken<TestBUSD, TestUSDC>>(signer::address_of(treasury));
        router::remove_liquidity<TestBUSD, TestUSDC>(treasury, (suppose_yz_fee_amount as u64), 0, 0);
        let treasury_token_yz_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));
        let treasury_token_yz_z_after_balance = coin::balance<TestUSDC>(signer::address_of(treasury));

        let treasury_remove_liquidity_yz_y = ((new_reserve_yz_y) as u128) * suppose_yz_fee_amount / suppose_yz_total_supply;
        let treasury_remove_liquidity_yz_z = ((new_reserve_yz_z) as u128) * suppose_yz_fee_amount / suppose_yz_total_supply;

        assert!(treasury_yz_lp_after_balance == (suppose_yz_fee_amount as u64), 93);
        assert!((treasury_token_yz_y_after_balance - treasury_token_xy_y_after_balance) == (treasury_remove_liquidity_yz_y as u64), 92);
        assert!(treasury_token_yz_z_after_balance == (treasury_remove_liquidity_yz_z as u64), 91);

        swap::withdraw_fee<TestUSDC, TestBNB>(treasury);
        let treasury_za_lp_after_balance = coin::balance<LPToken<TestBNB, TestUSDC>>(signer::address_of(treasury));
        router::remove_liquidity<TestBNB, TestUSDC>(treasury, (suppose_za_fee_amount as u64), 0, 0);
        let treasury_token_za_z_after_balance = coin::balance<TestUSDC>(signer::address_of(treasury));
        let treasury_token_za_a_after_balance = coin::balance<TestBNB>(signer::address_of(treasury));

        let treasury_remove_liquidity_za_z = ((new_reserve_za_z) as u128) * suppose_za_fee_amount / suppose_za_total_supply;
        let treasury_remove_liquidity_za_a = ((new_reserve_za_a) as u128) * suppose_za_fee_amount / suppose_za_total_supply;

        assert!(treasury_za_lp_after_balance == (suppose_za_fee_amount as u64), 93);
        assert!((treasury_token_za_z_after_balance - treasury_token_yz_z_after_balance) == (treasury_remove_liquidity_za_z as u64), 92);
        assert!(treasury_token_za_a_after_balance == (treasury_remove_liquidity_za_a as u64), 91);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_output_triplehop(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestUSDC>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBNB>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_xy_x = 5 * pow(10, 8);
        let initial_reserve_xy_y = 10 * pow(10, 8);
        let initial_reserve_yz_y = 5 * pow(10, 8);
        let initial_reserve_yz_z = 10 * pow(10, 8);
        let initial_reserve_za_z = 5 * pow(10, 8);
        let initial_reserve_za_a = 10 * pow(10, 8);
        let output_a = 298575210;
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        coin::register<TestUSDC>(&mm_fee_signer);

        coin::register<TestBNB>(&mm_fee_signer);

        // bob provider liquidity for 1:2 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_xy_x, initial_reserve_xy_y, 0, 0, 25);
        let bob_suppose_xy_lp_balance = math::sqrt(((initial_reserve_xy_x as u128) * (initial_reserve_xy_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_xy_total_supply = bob_suppose_xy_lp_balance + MINIMUM_LIQUIDITY;
        // bob provider liquidity for 2:1 USDC-BUSD
        router::add_liquidity<TestUSDC, TestBUSD>(bob, initial_reserve_yz_z, initial_reserve_yz_y, 0, 0, 25);
        let bob_suppose_yz_lp_balance = math::sqrt(((initial_reserve_yz_y as u128) * (initial_reserve_yz_z as u128))) - MINIMUM_LIQUIDITY;
        let suppose_yz_total_supply = bob_suppose_yz_lp_balance + MINIMUM_LIQUIDITY;
        // bob provider liquidity for 2:3 USDC-BUSD
        router::add_liquidity<TestUSDC, TestBNB>(bob, initial_reserve_za_z, initial_reserve_za_a, 0, 0, 25);
        let bob_suppose_za_lp_balance = math::sqrt(((initial_reserve_za_z as u128) * (initial_reserve_za_a as u128))) - MINIMUM_LIQUIDITY;
        let suppose_za_total_supply = bob_suppose_za_lp_balance + MINIMUM_LIQUIDITY;

        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));

        router::swap_exact_output_triplehop<TestWARP, TestBUSD, TestUSDC, TestBNB>(alice, output_a, 1 * pow(10, 8));

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_a_after_balance = coin::balance<TestBNB>(signer::address_of(alice));

        let output_z = test_utils::calc_input_using_output(output_a, initial_reserve_za_z, initial_reserve_za_a);
        let output_y = test_utils::calc_input_using_output((output_z as u64), initial_reserve_yz_y, initial_reserve_yz_z);
        let input_x = test_utils::calc_input_using_output((output_y as u64), initial_reserve_xy_x, initial_reserve_xy_y);
        let new_reserve_xy_x = initial_reserve_xy_x + (input_x as u64);
        let new_reserve_xy_y = initial_reserve_xy_y - (output_y as u64);
        let new_reserve_yz_y = initial_reserve_yz_y + (output_y as u64);
        let new_reserve_yz_z = initial_reserve_yz_z - (output_z as u64);
        let new_reserve_za_z = initial_reserve_za_z + (output_z as u64);
        let new_reserve_za_a = initial_reserve_za_a - (output_a as u64);

        let (reserve_xy_y, reserve_xy_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        let (reserve_yz_y, reserve_yz_z, _) = swap::token_reserves<TestBUSD, TestUSDC>();
        let (reserve_za_a, reserve_za_z, _) = swap::token_reserves<TestBNB, TestUSDC>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == (input_x as u64), 99);
        assert!(alice_token_a_after_balance == output_a, 98);
        assert!(reserve_xy_x == new_reserve_xy_x, 97);
        assert!(reserve_xy_y == new_reserve_xy_y, 96);
        assert!(reserve_yz_y == new_reserve_yz_y, 97);
        assert!(reserve_yz_z == new_reserve_yz_z, 96);
        assert!(reserve_za_z == new_reserve_za_z, 97);
        assert!(reserve_za_a == new_reserve_za_a, 96);

        let bob_token_xy_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_xy_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_xy_lp_balance as u64), 0, 0);

        let bob_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let suppose_xy_k_last = ((initial_reserve_xy_x * initial_reserve_xy_y) as u128);
        let suppose_xy_k = ((new_reserve_xy_x * new_reserve_xy_y) as u128);
        let suppose_xy_fee_amount = test_utils::calc_fee_lp(suppose_xy_total_supply, suppose_xy_k, suppose_xy_k_last);
        suppose_xy_total_supply = suppose_xy_total_supply + suppose_xy_fee_amount;

        let bob_token_yz_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_token_yz_z_before_balance = coin::balance<TestUSDC>(signer::address_of(bob));

        router::remove_liquidity<TestBUSD, TestUSDC>(bob, (bob_suppose_yz_lp_balance as u64), 0, 0);

        let bob_token_yz_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_token_yz_z_after_balance = coin::balance<TestUSDC>(signer::address_of(bob));

        let suppose_yz_k_last = ((initial_reserve_yz_y * initial_reserve_yz_z) as u128);
        let suppose_yz_k = ((new_reserve_yz_y * new_reserve_yz_z) as u128);
        let suppose_yz_fee_amount = test_utils::calc_fee_lp(suppose_yz_total_supply, suppose_yz_k, suppose_yz_k_last);
        suppose_yz_total_supply = suppose_yz_total_supply + suppose_yz_fee_amount;

        let bob_token_za_z_before_balance = coin::balance<TestUSDC>(signer::address_of(bob));
        let bob_token_za_a_before_balance = coin::balance<TestBNB>(signer::address_of(bob));

        router::remove_liquidity<TestUSDC, TestBNB>(bob, (bob_suppose_za_lp_balance as u64), 0, 0);

        let bob_token_za_z_after_balance = coin::balance<TestUSDC>(signer::address_of(bob));
        let bob_token_za_a_after_balance = coin::balance<TestBNB>(signer::address_of(bob));

        let suppose_za_k_last = ((initial_reserve_za_z * initial_reserve_za_a) as u128);
        let suppose_za_k = ((new_reserve_za_z * new_reserve_za_a) as u128);
        let suppose_za_fee_amount = test_utils::calc_fee_lp(suppose_za_total_supply, suppose_za_k, suppose_za_k_last);
        suppose_za_total_supply = suppose_za_total_supply + suppose_za_fee_amount;

        let bob_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * bob_suppose_xy_lp_balance / suppose_xy_total_supply;
        let bob_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * bob_suppose_xy_lp_balance / suppose_xy_total_supply;
        new_reserve_xy_x = new_reserve_xy_x - (bob_remove_liquidity_xy_x as u64);
        new_reserve_xy_y = new_reserve_xy_y - (bob_remove_liquidity_xy_y as u64);
        suppose_xy_total_supply = suppose_xy_total_supply - bob_suppose_xy_lp_balance;

        assert!((bob_token_xy_x_after_balance - bob_token_xy_x_before_balance) == (bob_remove_liquidity_xy_x as u64), 95);
        assert!((bob_token_xy_y_after_balance - bob_token_xy_y_before_balance) == (bob_remove_liquidity_xy_y as u64), 94);

        let bob_remove_liquidity_yz_y = ((new_reserve_yz_y) as u128) * bob_suppose_yz_lp_balance / suppose_yz_total_supply;
        let bob_remove_liquidity_yz_z = ((new_reserve_yz_z) as u128) * bob_suppose_yz_lp_balance / suppose_yz_total_supply;
        new_reserve_yz_y = new_reserve_yz_y - (bob_remove_liquidity_yz_y as u64);
        new_reserve_yz_z = new_reserve_yz_z - (bob_remove_liquidity_yz_z as u64);
        suppose_yz_total_supply = suppose_yz_total_supply - bob_suppose_yz_lp_balance;

        assert!((bob_token_yz_y_after_balance - bob_token_yz_y_before_balance) == (bob_remove_liquidity_yz_y as u64), 95);
        assert!((bob_token_yz_z_after_balance - bob_token_yz_z_before_balance) == (bob_remove_liquidity_yz_z as u64), 94);

        let bob_remove_liquidity_za_z = ((new_reserve_za_z) as u128) * bob_suppose_za_lp_balance / suppose_za_total_supply;
        let bob_remove_liquidity_za_a = ((new_reserve_za_a) as u128) * bob_suppose_za_lp_balance / suppose_za_total_supply;
        new_reserve_za_z = new_reserve_za_z - (bob_remove_liquidity_za_z as u64);
        new_reserve_za_a = new_reserve_za_a - (bob_remove_liquidity_za_a as u64);
        suppose_za_total_supply = suppose_za_total_supply - bob_suppose_za_lp_balance;

        assert!((bob_token_za_z_after_balance - bob_token_za_z_before_balance) == (bob_remove_liquidity_za_z as u64), 95);
        assert!((bob_token_za_a_after_balance - bob_token_za_a_before_balance) == (bob_remove_liquidity_za_a as u64), 94);

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
        let treasury_xy_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_xy_fee_amount as u64), 0, 0);
        let treasury_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;
        let treasury_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;

        assert!(treasury_xy_lp_after_balance == (suppose_xy_fee_amount as u64), 93);
        assert!(treasury_token_xy_x_after_balance == (treasury_remove_liquidity_xy_x as u64), 92);
        assert!(treasury_token_xy_y_after_balance == (treasury_remove_liquidity_xy_y as u64), 91);

        swap::withdraw_fee<TestBUSD, TestUSDC>(treasury);
        let treasury_yz_lp_after_balance = coin::balance<LPToken<TestBUSD, TestUSDC>>(signer::address_of(treasury));
        router::remove_liquidity<TestBUSD, TestUSDC>(treasury, (suppose_yz_fee_amount as u64), 0, 0);
        let treasury_token_yz_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));
        let treasury_token_yz_z_after_balance = coin::balance<TestUSDC>(signer::address_of(treasury));

        let treasury_remove_liquidity_yz_y = ((new_reserve_yz_y) as u128) * suppose_yz_fee_amount / suppose_yz_total_supply;
        let treasury_remove_liquidity_yz_z = ((new_reserve_yz_z) as u128) * suppose_yz_fee_amount / suppose_yz_total_supply;

        assert!(treasury_yz_lp_after_balance == (suppose_yz_fee_amount as u64), 93);
        assert!((treasury_token_yz_y_after_balance - treasury_token_xy_y_after_balance) == (treasury_remove_liquidity_yz_y as u64), 92);
        assert!(treasury_token_yz_z_after_balance == (treasury_remove_liquidity_yz_z as u64), 91);

        swap::withdraw_fee<TestUSDC, TestBNB>(treasury);
        let treasury_za_lp_after_balance = coin::balance<LPToken<TestBNB, TestUSDC>>(signer::address_of(treasury));
        router::remove_liquidity<TestBNB, TestUSDC>(treasury, (suppose_za_fee_amount as u64), 0, 0);
        let treasury_token_za_z_after_balance = coin::balance<TestUSDC>(signer::address_of(treasury));
        let treasury_token_za_a_after_balance = coin::balance<TestBNB>(signer::address_of(treasury));

        let treasury_remove_liquidity_za_z = ((new_reserve_za_z) as u128) * suppose_za_fee_amount / suppose_za_total_supply;
        let treasury_remove_liquidity_za_a = ((new_reserve_za_a) as u128) * suppose_za_fee_amount / suppose_za_total_supply;

        assert!(treasury_za_lp_after_balance == (suppose_za_fee_amount as u64), 93);
        assert!((treasury_token_za_z_after_balance - treasury_token_yz_z_after_balance) == (treasury_remove_liquidity_za_z as u64), 92);
        assert!(treasury_token_za_a_after_balance == (treasury_remove_liquidity_za_a as u64), 91);
    }

}
*/
