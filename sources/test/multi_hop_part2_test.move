/*
#[test_only]
module warpgate::multi_part2_swap_test {
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

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, user1 = @0x12341, user2 = @0x12342, user3 = @0x12343, user4 = @0x12344, alice = @0x12345)]
    #[expected_failure(abort_code = 21, location = warpgate::swap)]
    fun test_swap_exact_input_triplehop_with_multi_liquidity(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(user3));
        account::create_account_for_test(signer::address_of(user4));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, user1, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, user2, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, user3, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, user4, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, user1, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, user2, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, user3, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, user4, 200 * pow(10, 8));
        test_coins::register_and_mint<TestUSDC>(&coin_owner, user1, 200 * pow(10, 8));
        test_coins::register_and_mint<TestUSDC>(&coin_owner, user2, 200 * pow(10, 8));
        test_coins::register_and_mint<TestUSDC>(&coin_owner, user3, 200 * pow(10, 8));
        test_coins::register_and_mint<TestUSDC>(&coin_owner, user4, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBNB>(&coin_owner, user1, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBNB>(&coin_owner, user2, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBNB>(&coin_owner, user3, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBNB>(&coin_owner, user4, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let user1_add_liquidity_xy_x = 5 * pow(10, 8);
        let user2_add_liquidity_xy_x = 20 * pow(10, 8);
        let user3_add_liquidity_xy_x = 55 * pow(10, 8);
        let user4_add_liquidity_xy_x = 90 * pow(10, 8);
        let user1_add_liquidity_xy_y = 10 * pow(10, 8);
        let user2_add_liquidity_xy_y = 40 * pow(10, 8);
        let user3_add_liquidity_xy_y = 110 * pow(10, 8);
        let user4_add_liquidity_xy_y = 180 * pow(10, 8);
        let user1_add_liquidity_yz_y = 5 * pow(10, 8);
        let user2_add_liquidity_yz_y = 60 * pow(10, 8);
        let user1_add_liquidity_yz_z = 10 * pow(10, 8);
        let user2_add_liquidity_yz_z = 120 * pow(10, 8);
        let user1_add_liquidity_za_z = 10 * pow(10, 8);
        let user2_add_liquidity_za_z = 20 * pow(10, 8);
        let user1_add_liquidity_za_a = 15 * pow(10, 8);
        let user2_add_liquidity_za_a = 30 * pow(10, 8);
        let input_x = 1 * pow(10, 8);

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        coin::register<TestUSDC>(&mm_fee_signer);

        coin::register<TestBNB>(&mm_fee_signer);

        coin::register<TestAPT>(&mm_fee_signer);

        // bob provider liquidity for 1:2 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(user1, user1_add_liquidity_xy_x, user1_add_liquidity_xy_y, 0, 0, 25);
        let user1_suppose_xy_lp_balance = math::sqrt(((user1_add_liquidity_xy_x as u128) * (user1_add_liquidity_xy_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_xy_total_supply = user1_suppose_xy_lp_balance + MINIMUM_LIQUIDITY;
        let suppose_reserve_xy_x = user1_add_liquidity_xy_x;
        let suppose_reserve_xy_y = user1_add_liquidity_xy_y;
        router::add_liquidity<TestWARP, TestBUSD>(user2, user2_add_liquidity_xy_x, user2_add_liquidity_xy_y, 0, 0, 25);
        let user2_suppose_xy_lp_balance = math::min((user2_add_liquidity_xy_x as u128) * suppose_xy_total_supply / (suppose_reserve_xy_x as u128), (user2_add_liquidity_xy_y as u128) * suppose_xy_total_supply / (suppose_reserve_xy_y as u128));
        suppose_xy_total_supply = suppose_xy_total_supply + user2_suppose_xy_lp_balance;
        suppose_reserve_xy_x = suppose_reserve_xy_x + user2_add_liquidity_xy_x;
        suppose_reserve_xy_y = suppose_reserve_xy_y + user2_add_liquidity_xy_y;
        router::add_liquidity<TestWARP, TestBUSD>(user3, user3_add_liquidity_xy_x, user3_add_liquidity_xy_y, 0, 0, 25);
        let user3_suppose_xy_lp_balance = math::min((user3_add_liquidity_xy_x as u128) * suppose_xy_total_supply / (suppose_reserve_xy_x as u128), (user3_add_liquidity_xy_y as u128) * suppose_xy_total_supply / (suppose_reserve_xy_y as u128));
        suppose_xy_total_supply = suppose_xy_total_supply + user3_suppose_xy_lp_balance;
        suppose_reserve_xy_x = suppose_reserve_xy_x + user3_add_liquidity_xy_x;
        suppose_reserve_xy_y = suppose_reserve_xy_y + user3_add_liquidity_xy_y;
        router::add_liquidity<TestWARP, TestBUSD>(user4, user4_add_liquidity_xy_x, user4_add_liquidity_xy_y, 0, 0, 25);
        let user4_suppose_xy_lp_balance = math::min((user4_add_liquidity_xy_x as u128) * suppose_xy_total_supply / (suppose_reserve_xy_x as u128), (user4_add_liquidity_xy_y as u128) * suppose_xy_total_supply / (suppose_reserve_xy_y as u128));
        suppose_xy_total_supply = suppose_xy_total_supply + user4_suppose_xy_lp_balance;
        suppose_reserve_xy_x = suppose_reserve_xy_x + user4_add_liquidity_xy_x;
        suppose_reserve_xy_y = suppose_reserve_xy_y + user4_add_liquidity_xy_y;
        // bob provider liquidity for 2:1 USDC-BUSD
        router::add_liquidity<TestBUSD, TestUSDC>(user1, user1_add_liquidity_yz_y, user1_add_liquidity_yz_z, 0, 0, 25);
        let suppose_reserve_yz_y = user1_add_liquidity_yz_y;
        let suppose_reserve_yz_z = user1_add_liquidity_yz_z;
        router::add_liquidity<TestBUSD, TestUSDC>(user2, user2_add_liquidity_yz_y, user2_add_liquidity_yz_z, 0, 0, 25);
        suppose_reserve_yz_y = suppose_reserve_yz_y + user2_add_liquidity_yz_y;
        suppose_reserve_yz_z = suppose_reserve_yz_z + user2_add_liquidity_yz_z;
        // bob provider liquidity for 2:3 USDC-TestBNB
        router::add_liquidity<TestUSDC, TestBNB>(user1, user1_add_liquidity_za_z, user1_add_liquidity_za_a, 0, 0, 25);
        let suppose_reserve_za_z = user1_add_liquidity_za_z;
        let suppose_reserve_za_a = user1_add_liquidity_za_a;
        router::add_liquidity<TestUSDC, TestBNB>(user2, user2_add_liquidity_za_z, user2_add_liquidity_za_a, 0, 0, 25);

        suppose_reserve_za_z = suppose_reserve_za_z + user2_add_liquidity_za_z;
        suppose_reserve_za_a = suppose_reserve_za_a + user2_add_liquidity_za_a;

        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));

        router::swap_exact_input_triplehop<TestWARP, TestBUSD, TestUSDC, TestBNB>(alice, input_x, 0);

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_a_after_balance = coin::balance<TestBNB>(signer::address_of(alice));
        // Calculate fee
        let fee_amount = (input_x as u128) * 25 / 10000;
        let amount_after_fee = input_x - (fee_amount as u64);
        let output_y = test_utils::calc_output_using_input(amount_after_fee, suppose_reserve_xy_x, suppose_reserve_xy_y);
        let output_z = test_utils::calc_output_using_input((output_y as u64), suppose_reserve_yz_y, suppose_reserve_yz_z);
        let output_a = test_utils::calc_output_using_input((output_z as u64), suppose_reserve_za_z, suppose_reserve_za_a);
        let first_swap_suppose_reserve_xy_x = suppose_reserve_xy_x + amount_after_fee;
        let first_swap_suppose_reserve_xy_y = suppose_reserve_xy_y - (output_y as u64);
        let first_swap_suppose_reserve_yz_y = suppose_reserve_yz_y + (output_y as u64);
        let first_swap_suppose_reserve_yz_z = suppose_reserve_yz_z - (output_z as u64);
        let first_swap_suppose_reserve_za_z = suppose_reserve_za_z + (output_z as u64);
        let first_swap_suppose_reserve_za_a = suppose_reserve_za_a - (output_a as u64);

        let (reserve_xy_y, reserve_xy_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        let (reserve_yz_y, reserve_yz_z, _) = swap::token_reserves<TestBUSD, TestUSDC>();
        let (reserve_za_a, reserve_za_z, _) = swap::token_reserves<TestBNB, TestUSDC>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == input_x, 99);
        assert!(alice_token_a_after_balance == (output_a as u64), 99);
        assert!(reserve_xy_x == first_swap_suppose_reserve_xy_x, 97);
        assert!(reserve_xy_y == first_swap_suppose_reserve_xy_y, 96);
        assert!(reserve_yz_y == first_swap_suppose_reserve_yz_y, 97);
        assert!(reserve_yz_z == first_swap_suppose_reserve_yz_z, 96);
        assert!(reserve_za_z == first_swap_suppose_reserve_za_z, 97);
        assert!(reserve_za_a == first_swap_suppose_reserve_za_a, 96);

        alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_a_before_balance = coin::balance<TestBNB>(signer::address_of(alice));

        router::swap_exact_input_triplehop<TestWARP, TestBUSD, TestUSDC, TestBNB>(alice, input_x, 0);

        alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        alice_token_a_after_balance = coin::balance<TestBNB>(signer::address_of(alice));
        
        let fee_amount1 = (input_x as u128) * 25 / 10000;
        let amount_after_fee1 = input_x - (fee_amount as u64);

        output_y = test_utils::calc_output_using_input(amount_after_fee1, first_swap_suppose_reserve_xy_x, first_swap_suppose_reserve_xy_y);
        output_z = test_utils::calc_output_using_input((output_y as u64), first_swap_suppose_reserve_yz_y, first_swap_suppose_reserve_yz_z);
        output_a = test_utils::calc_output_using_input((output_z as u64), first_swap_suppose_reserve_za_z, first_swap_suppose_reserve_za_a);
        let second_swap_suppose_reserve_xy_x = first_swap_suppose_reserve_xy_x + amount_after_fee1;
        let second_swap_suppose_reserve_xy_y = first_swap_suppose_reserve_xy_y - (output_y as u64);
        let second_swap_suppose_reserve_yz_y = first_swap_suppose_reserve_yz_y + (output_y as u64);
        let second_swap_suppose_reserve_yz_z = first_swap_suppose_reserve_yz_z - (output_z as u64);
        let second_swap_suppose_reserve_za_z = first_swap_suppose_reserve_za_z + (output_z as u64);
        let second_swap_suppose_reserve_za_a = first_swap_suppose_reserve_za_a - (output_a as u64);

        (reserve_xy_y, reserve_xy_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        (reserve_yz_y, reserve_yz_z, _) = swap::token_reserves<TestBUSD, TestUSDC>();
        (reserve_za_a, reserve_za_z, _) = swap::token_reserves<TestBNB, TestUSDC>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == input_x, 99);
        assert!((alice_token_a_after_balance - alice_token_a_before_balance) == (output_a as u64), 99);
        assert!(reserve_xy_x == second_swap_suppose_reserve_xy_x, 97);
        assert!(reserve_xy_y == second_swap_suppose_reserve_xy_y, 96);
        assert!(reserve_yz_y == second_swap_suppose_reserve_yz_y, 97);
        assert!(reserve_yz_z == second_swap_suppose_reserve_yz_z, 96);
        assert!(reserve_za_z == second_swap_suppose_reserve_za_z, 97);
        assert!(reserve_za_a == second_swap_suppose_reserve_za_a, 96);

        let user1_token_xy_x_before_balance = coin::balance<TestWARP>(signer::address_of(user1));
        let user1_token_xy_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user1));

        router::remove_liquidity<TestWARP, TestBUSD>(user1, (user1_suppose_xy_lp_balance as u64), 0, 0);

        let user1_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(user1));
        let user1_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user1));

        let suppose_xy_k_last = (suppose_reserve_xy_x as u128) * (suppose_reserve_xy_y as u128);
        let suppose_xy_k = (first_swap_suppose_reserve_xy_x as u128) * (first_swap_suppose_reserve_xy_y as u128);
        let first_swap_suppose_xy_fee_amount = test_utils::calc_fee_lp(suppose_xy_total_supply, suppose_xy_k, suppose_xy_k_last);
        suppose_xy_total_supply = suppose_xy_total_supply + first_swap_suppose_xy_fee_amount;
        suppose_xy_k_last = (first_swap_suppose_reserve_xy_x as u128) * (first_swap_suppose_reserve_xy_y as u128);
        suppose_xy_k = (second_swap_suppose_reserve_xy_x as u128) * (second_swap_suppose_reserve_xy_y as u128);
        let second_swap_suppose_xy_fee_amount = test_utils::calc_fee_lp(suppose_xy_total_supply, suppose_xy_k, suppose_xy_k_last);
        suppose_xy_total_supply = suppose_xy_total_supply + second_swap_suppose_xy_fee_amount;
        let user1_remove_liquidity_xy_x = ((second_swap_suppose_reserve_xy_x) as u128) * user1_suppose_xy_lp_balance / suppose_xy_total_supply;
        let user1_remove_liquidity_xy_y = ((second_swap_suppose_reserve_xy_y) as u128) * user1_suppose_xy_lp_balance / suppose_xy_total_supply;
        let new_reserve_xy_x = second_swap_suppose_reserve_xy_x - (user1_remove_liquidity_xy_x as u64);
        let new_reserve_xy_y = second_swap_suppose_reserve_xy_y - (user1_remove_liquidity_xy_y as u64);
        suppose_xy_total_supply = suppose_xy_total_supply - user1_suppose_xy_lp_balance;

        assert!((user1_token_xy_x_after_balance - user1_token_xy_x_before_balance) == (user1_remove_liquidity_xy_x as u64), 95);
        assert!((user1_token_xy_y_after_balance - user1_token_xy_y_before_balance) == (user1_remove_liquidity_xy_y as u64), 94);

        let user2_token_xy_x_before_balance = coin::balance<TestWARP>(signer::address_of(user2));
        let user2_token_xy_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user2));

        router::remove_liquidity<TestWARP, TestBUSD>(user2, (user2_suppose_xy_lp_balance as u64), 0, 0);

        let user2_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(user2));
        let user2_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user2));

        // the k is the same with no new fee
        let user2_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * user2_suppose_xy_lp_balance / suppose_xy_total_supply;
        let user2_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * user2_suppose_xy_lp_balance / suppose_xy_total_supply;
        new_reserve_xy_x = new_reserve_xy_x - (user2_remove_liquidity_xy_x as u64);
        new_reserve_xy_y = new_reserve_xy_y - (user2_remove_liquidity_xy_y as u64);
        suppose_xy_total_supply = suppose_xy_total_supply - user2_suppose_xy_lp_balance;

        assert!((user2_token_xy_x_after_balance - user2_token_xy_x_before_balance) == (user2_remove_liquidity_xy_x as u64), 95);
        assert!((user2_token_xy_y_after_balance - user2_token_xy_y_before_balance) == (user2_remove_liquidity_xy_y as u64), 94);

        let suppose_xy_fee_amount = first_swap_suppose_xy_fee_amount + second_swap_suppose_xy_fee_amount;

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
        let treasury_xy_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_xy_fee_amount as u64), 0, 0);

        let treasury_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;
        let treasury_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * suppose_xy_fee_amount / suppose_xy_total_supply;

        new_reserve_xy_x = new_reserve_xy_x - (treasury_remove_liquidity_xy_x as u64);
        new_reserve_xy_y = new_reserve_xy_y - (treasury_remove_liquidity_xy_y as u64);
        suppose_xy_total_supply = suppose_xy_total_supply - suppose_xy_fee_amount;

        assert!(treasury_xy_lp_after_balance == (suppose_xy_fee_amount as u64), 93);
        assert!(treasury_token_xy_x_after_balance == (treasury_remove_liquidity_xy_x as u64), 92);
        assert!(treasury_token_xy_y_after_balance == (treasury_remove_liquidity_xy_y as u64), 91);

        let user3_token_xy_x_before_balance = coin::balance<TestWARP>(signer::address_of(user3));
        let user3_token_xy_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user3));

        router::remove_liquidity<TestWARP, TestBUSD>(user3, (user3_suppose_xy_lp_balance as u64), 0, 0);

        let user3_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(user3));
        let user3_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user3));

        let user3_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * user3_suppose_xy_lp_balance / suppose_xy_total_supply;
        let user3_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * user3_suppose_xy_lp_balance / suppose_xy_total_supply;
        new_reserve_xy_x = new_reserve_xy_x - (user3_remove_liquidity_xy_x as u64);
        new_reserve_xy_y = new_reserve_xy_y - (user3_remove_liquidity_xy_y as u64);
        suppose_xy_total_supply = suppose_xy_total_supply - user3_suppose_xy_lp_balance;

        assert!((user3_token_xy_x_after_balance - user3_token_xy_x_before_balance) == (user3_remove_liquidity_xy_x as u64), 95);
        assert!((user3_token_xy_y_after_balance - user3_token_xy_y_before_balance) == (user3_remove_liquidity_xy_y as u64), 94);

        let user4_token_xy_x_before_balance = coin::balance<TestWARP>(signer::address_of(user4));
        let user4_token_xy_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user4));

        router::remove_liquidity<TestWARP, TestBUSD>(user4, (user4_suppose_xy_lp_balance as u64), 0, 0);

        let user4_token_xy_x_after_balance = coin::balance<TestWARP>(signer::address_of(user4));
        let user4_token_xy_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user4));

        let user4_remove_liquidity_xy_x = ((new_reserve_xy_x) as u128) * user4_suppose_xy_lp_balance / suppose_xy_total_supply;
        let user4_remove_liquidity_xy_y = ((new_reserve_xy_y) as u128) * user4_suppose_xy_lp_balance / suppose_xy_total_supply;

        assert!((user4_token_xy_x_after_balance - user4_token_xy_x_before_balance) == (user4_remove_liquidity_xy_x as u64), 95);
        assert!((user4_token_xy_y_after_balance - user4_token_xy_y_before_balance) == (user4_remove_liquidity_xy_y as u64), 94);

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_input_quadruplehop(
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
        test_coins::register_and_mint<TestAPT>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_xy_x = 5 * pow(10, 8);
        let initial_reserve_xy_y = 10 * pow(10, 8);
        let initial_reserve_yz_y = 5 * pow(10, 8);
        let initial_reserve_yz_z = 10 * pow(10, 8);
        let initial_reserve_za_z = 10 * pow(10, 8);
        let initial_reserve_za_a = 15 * pow(10, 8);
        let initial_reserve_ab_a = 10 * pow(10, 8);
        let initial_reserve_ab_b = 15 * pow(10, 8);
        let input_x = 1 * pow(10, 8);

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        coin::register<TestUSDC>(&mm_fee_signer);

        coin::register<TestBNB>(&mm_fee_signer);

        coin::register<TestAPT>(&mm_fee_signer);


        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_xy_x, initial_reserve_xy_y, 0, 0, 25);

        router::add_liquidity<TestBUSD, TestUSDC>(bob, initial_reserve_yz_y, initial_reserve_yz_z, 0, 0, 25);
    
        router::add_liquidity<TestUSDC, TestBNB>(bob, initial_reserve_za_z, initial_reserve_za_a, 0, 0, 25);
        
        router::add_liquidity<TestBNB, TestAPT>(bob, initial_reserve_ab_a, initial_reserve_ab_b, 0, 0, 25);

        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));

        router::swap_exact_input_quadruplehop<TestWARP, TestBUSD, TestUSDC, TestBNB, TestAPT>(alice, input_x, 0);

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_b_after_balance = coin::balance<TestAPT>(signer::address_of(alice));
        // Calculate fee
        let fee_amount = (input_x as u128) * 25 / 10000;
        let amount_after_fee = input_x - (fee_amount as u64);

        let output_y = swap_utils::get_amount_out(amount_after_fee, initial_reserve_xy_x, initial_reserve_xy_y, 25);
        let output_z = swap_utils::get_amount_out((output_y as u64), initial_reserve_yz_y, initial_reserve_yz_z, 25);
        let output_a = swap_utils::get_amount_out((output_z as u64), initial_reserve_za_z, initial_reserve_za_a, 25);
        let output_b = swap_utils::get_amount_out((output_a as u64), initial_reserve_ab_a, initial_reserve_ab_b, 25);

        let new_reserve_xy_x = initial_reserve_xy_x + amount_after_fee;
        let new_reserve_xy_y = initial_reserve_xy_y - (output_y as u64);
        let new_reserve_yz_y = initial_reserve_yz_y + (output_y as u64);
        let new_reserve_yz_z = initial_reserve_yz_z - (output_z as u64);
        let new_reserve_za_z = initial_reserve_za_z + (output_z as u64);
        let new_reserve_za_a = initial_reserve_za_a - (output_a as u64);
        let new_reserve_ab_a = initial_reserve_ab_a + (output_a as u64);
        let new_reserve_ab_b = initial_reserve_ab_b - (output_b as u64);

        let (reserve_xy_x, reserve_xy_y) = test_utils::get_token_reserves<TestWARP, TestBUSD>();
        let (reserve_yz_y, reserve_yz_z) = test_utils::get_token_reserves<TestBUSD, TestUSDC>();
        let (reserve_za_z, reserve_za_a) = test_utils::get_token_reserves<TestUSDC, TestBNB>();
        let (reserve_ab_a, reserve_ab_b) = test_utils::get_token_reserves<TestBNB, TestAPT>();

        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == input_x, 99);
        assert!(alice_token_b_after_balance == (output_b as u64), 98);
        assert!(reserve_xy_x == new_reserve_xy_x, 97);
        assert!(reserve_xy_y == new_reserve_xy_y, 96);
        assert!(reserve_yz_y == new_reserve_yz_y, 97);
        assert!(reserve_yz_z == new_reserve_yz_z, 96);
        assert!(reserve_za_z == new_reserve_za_z, 97);
        assert!(reserve_za_a == new_reserve_za_a, 96);
        assert!(reserve_ab_a == new_reserve_ab_a, 97);
        assert!(reserve_ab_b == new_reserve_ab_b, 96);

    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_output_quadruplehop(
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
        test_coins::register_and_mint<TestAPT>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_xy_x = 5 * pow(10, 8);
        let initial_reserve_xy_y = 10 * pow(10, 8);
        let initial_reserve_yz_y = 5 * pow(10, 8);
        let initial_reserve_yz_z = 10 * pow(10, 8);
        let initial_reserve_za_z = 5 * pow(10, 8);
        let initial_reserve_za_a = 10 * pow(10, 8);
        let initial_reserve_ab_a = 10 * pow(10, 8);
        let initial_reserve_ab_b = 15 * pow(10, 8);
        let output_b = 8888888;

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        coin::register<TestUSDC>(&mm_fee_signer);

        coin::register<TestBNB>(&mm_fee_signer);

        coin::register<TestAPT>(&mm_fee_signer);

        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_xy_x, initial_reserve_xy_y, 0, 0, 25);

        router::add_liquidity<TestBUSD, TestUSDC>(bob, initial_reserve_yz_y, initial_reserve_yz_z, 0, 0, 25);
    
        router::add_liquidity<TestUSDC, TestBNB>(bob, initial_reserve_za_z, initial_reserve_za_a, 0, 0, 25);
        
        router::add_liquidity<TestBNB, TestAPT>(bob, initial_reserve_ab_a, initial_reserve_ab_b, 0, 0, 25);

        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));

        router::swap_exact_output_quadruplehop<TestWARP, TestBUSD, TestUSDC, TestBNB, TestAPT>(alice, output_b, 100 * pow(10, 8));

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_b_after_balance = coin::balance<TestAPT>(signer::address_of(alice));

        let output_a = swap_utils::get_amount_in(output_b, initial_reserve_ab_a, initial_reserve_ab_b, 25);
        let output_z = swap_utils::get_amount_in((output_a as u64), initial_reserve_za_z, initial_reserve_za_a, 25);
        let output_y = swap_utils::get_amount_in((output_z as u64), initial_reserve_yz_y, initial_reserve_yz_z, 25);
        let input_x = swap_utils::get_amount_in((output_y as u64), initial_reserve_xy_x, initial_reserve_xy_y, 25);

        let new_reserve_xy_x = initial_reserve_xy_x + (input_x as u64);
        let new_reserve_xy_y = initial_reserve_xy_y - (output_y as u64);
        let new_reserve_yz_y = initial_reserve_yz_y + (output_y as u64);
        let new_reserve_yz_z = initial_reserve_yz_z - (output_z as u64);
        let new_reserve_za_z = initial_reserve_za_z + (output_z as u64);
        let new_reserve_za_a = initial_reserve_za_a - (output_a as u64);
        let new_reserve_ab_a = initial_reserve_ab_a + (output_a as u64);
        let new_reserve_ab_b = initial_reserve_ab_b - (output_b as u64);

        let (reserve_xy_x, reserve_xy_y) = test_utils::get_token_reserves<TestWARP, TestBUSD>();
        let (reserve_yz_y, reserve_yz_z) = test_utils::get_token_reserves<TestBUSD, TestUSDC>();
        let (reserve_za_z, reserve_za_a) = test_utils::get_token_reserves<TestUSDC, TestBNB>();
        let (reserve_ab_a, reserve_ab_b) = test_utils::get_token_reserves<TestBNB, TestAPT>();

        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == (input_x as u64), 99);
        assert!(alice_token_b_after_balance == output_b, 98);
        assert!(reserve_xy_x == new_reserve_xy_x, 97);
        assert!(reserve_xy_y == new_reserve_xy_y, 96);
        assert!(reserve_yz_y == new_reserve_yz_y, 97);
        assert!(reserve_yz_z == new_reserve_yz_z, 96);
        assert!(reserve_za_z == new_reserve_za_z, 97);
        assert!(reserve_za_a == new_reserve_za_a, 96);
        assert!(reserve_ab_a == new_reserve_ab_a, 97);
        assert!(reserve_ab_b == new_reserve_ab_b, 96);
    }

}
*/