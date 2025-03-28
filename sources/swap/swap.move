module warpgate::swap {
    use std::signer;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::error;
    use std::vector;
    use std::bcs;
    use aptos_framework::event;
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset, FungibleStore, MintRef, TransferRef, BurnRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::resource_account;
    use warpgate::math;
    use warpgate::swap_utils;
    use std::debug;
    
    // Constants
    const ZERO_ACCOUNT: address = @zero;
    const LP_ACCOUNT: address = @lpfee;
    const DEFAULT_ADMIN: address = @default_admin;
    const RESOURCE_ACCOUNT: address = @warpgate;
    const MM_FEE_TO: address = @mmfee;
    const DEV: address = @dev;
    
    const MINIMUM_LIQUIDITY: u128 = 1000;
    const MAX_COIN_NAME_LENGTH: u64 = 32;
    const MARKET_MAKER_FEE: u128 = 25; // 0.25% participation fee
    const FEE_DENOMINATOR: u128 = 10000;

    /// Max `u128` value.
    const MAX_U128: u128 = 340282366920938463463374607431768211455;
    
    // Error constants
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_ALREADY_INITIALIZED: u64 = 1;
    const ERROR_NOT_CREATOR: u64 = 2;
    const ERROR_INSUFFICIENT_LIQUIDITY_MINTED: u64 = 4;
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 6;
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 7;
    const ERROR_INVALID_AMOUNT: u64 = 8;
    const ERROR_TOKENS_NOT_SORTED: u64 = 9;
    const ERROR_INSUFFICIENT_LIQUIDITY_BURNED: u64 = 10;
    const ERROR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 13;
    const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 14;
    const ERROR_K: u64 = 15;
    const ERROR_X_NOT_REGISTERED: u64 = 16;
    const ERROR_Y_NOT_REGISTERED: u64 = 16;
    const ERROR_NOT_ADMIN: u64 = 17;
    const ERROR_NOT_FEE_TO: u64 = 18;
    const ERROR_NOT_EQUAL_EXACT_AMOUNT: u64 = 19;
    const ERROR_NOT_RESOURCE_ACCOUNT: u64 = 20;
    const ERROR_NO_FEE_WITHDRAW: u64 = 21;
    const ERROR_FEE_TO_NOT_REGISTERED: u64 = 22;
    const ERROR_INVALID_FEE: u64 = 23;
    const ERROR_TOKEN_NOT_FOUND: u64 = 24;
    const ERROR_PAIR_NOT_FOUND: u64 = 25;

    
    const MAX_FEE: u128 = 100; // 1% max fee
    const PRECISION: u64 = 10000;

    
    // Token pair metadata
    struct TokenPairMetadata has key {
        creator: address,
        fee_amount: u128,
        k_last: u128,
        token_store_x: Object<FungibleStore>,
        token_store_y: Object<FungibleStore>,
        // LP Token capabilities
        mint_cap: MintRef,
        burn_cap: BurnRef,
        freeze_cap: TransferRef,
        // The two tokens in the pair
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        // Swap fee in basis points
        swap_fee: u128,
        // LP token metadata object
        lp_token: Object<Metadata>
    }
    
    // Token pair reserves
    struct TokenPairReserve has key {
        reserve_x: u64,
        reserve_y: u64,
        block_timestamp_last: u64
    }
    
    // Global swap info
    struct SwapInfo has key {
        signer_cap: account::SignerCapability,
        fee_to: address,
        admin: address,
        mm_fee: u128,
        mm_fee_to: address,
        // Event handles
        pair_created: event::EventHandle<PairCreatedEvent>,
        market_maker_fees: event::EventHandle<MarketMakerFeeEvent>,
    }
    
    // Events
    struct PairCreatedEvent has drop, store {
        user: address,
        token_x: String,
        token_y: String,
        token_x_addr: address,
        token_y_addr: address,
        pool: address,
        lp_token: address
    }
    

    #[event]
    struct AddLiquidityEvent has drop, store {
        user: address,
        token_x: address,
        token_y: address,
        amount_x: u64,
        amount_y: u64,
        liquidity: u64,
        fee_amount: u64,
        reserve_x: u64,
        reserve_y: u64,
        lp_supply: u64
    }
    #[event]
    struct RemoveLiquidityEvent has drop, store {
        user: address,
        token_x: address,
        token_y: address,
        liquidity: u64,
        amount_x: u64,
        amount_y: u64,
        fee_amount: u64,
        reserve_x: u64,
        reserve_y: u64,
        lp_supply: u64
    }
    #[event]
    struct SwapEvent has drop, store {
        user: address,
        token_x: address,
        token_y: address,
        amount_x_in: u64,
        amount_y_in: u64,
        amount_x_out: u64,
        amount_y_out: u64,
        reserve_x: u64,
        reserve_y: u64
    }
    
    struct MarketMakerFeeEvent has drop, store {
        user: address,
        token: String,
        fee_amount: u64,
    }
    
    // Initialize module
    fun init_module(sender: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEV);
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        
        move_to(&resource_signer, SwapInfo {
            signer_cap,
            fee_to: LP_ACCOUNT,
            admin: DEFAULT_ADMIN,
            mm_fee: MARKET_MAKER_FEE,
            mm_fee_to: MM_FEE_TO,
            pair_created: account::new_event_handle<PairCreatedEvent>(&resource_signer),
            market_maker_fees: account::new_event_handle<MarketMakerFeeEvent>(&resource_signer),
        });
    }
    
    // Create a new pair
    public fun create_pair(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        swap_fee: u128
    ) acquires SwapInfo {
       
        // Sort tokens to ensure consistent ordering
        let (sorted_x, sorted_y, _) = swap_utils::sort_tokens(token_x, token_y);
        
        // Check if the pair already exists
        assert!(!is_pair_created(sorted_x, sorted_y), ERROR_ALREADY_INITIALIZED);
        assert!(swap_fee <= MAX_FEE, ERROR_INVALID_FEE);
        
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        
        // Get resource signer to create objects
        let resource_signer = account::create_signer_with_capability(&swap_info.signer_cap);
        
        // Create LP token
        let lp_name = create_lp_token_name(sorted_x, sorted_y);
        let lp_symbol = string::utf8(b"WARP-LP");
        
        // Create LP token constructor
        let token_seed = get_lp_seed(sorted_x, sorted_y);
        let constructor_ref = &object::create_named_object(&resource_signer, token_seed);
        
        // Initialize the LP token with FA standard
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(), 
            lp_name,
            lp_symbol,
            8, 
            string::utf8(b""),
            string::utf8(b"")
        );
        
        // Generate LP token capabilities
        let mint_cap = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_cap = fungible_asset::generate_burn_ref(constructor_ref);
        let freeze_cap = fungible_asset::generate_transfer_ref(constructor_ref);
        
        // Create pool object
        let pool_seed = get_pool_seed(sorted_x, sorted_y);
        let pool_ref = &object::create_named_object(&resource_signer, pool_seed);
        let pool_signer = object::generate_signer(pool_ref);
        //let pool_obj = object::object_from_constructor_ref<TokenPairMetadata>(pool_ref);
        let pool_addr = signer::address_of(&pool_signer);
        // Create token stores for the pool
        let token_store_x = create_token_store(&resource_signer, sorted_x);
        let token_store_y = create_token_store(&resource_signer, sorted_y);
        // Get the LP token metadata object
        let lp_token = object::object_from_constructor_ref<Metadata>(constructor_ref);
    
        // Create metadata resource
        move_to(&pool_signer, TokenPairMetadata {
            creator: sender_addr,
            fee_amount: 0,
            k_last: 0,
            token_store_x,
            token_store_y,
            mint_cap,
            burn_cap,
            freeze_cap,
            token_x: sorted_x,
            token_y: sorted_y,
            swap_fee,
            lp_token
        });
        
        // Create reserves resource
        move_to(&pool_signer, TokenPairReserve {
            reserve_x: 0,
            reserve_y: 0,
            block_timestamp_last: 0
        });
        
       
        // After adding the TokenPairMetadata to the object, we can create an Object<TokenPairMetadata>
        // We need to use a different approach here - not object_from_constructor_ref
        let pool_addr = object::address_from_constructor_ref(pool_ref);
        let pool_obj = object::address_to_object<TokenPairMetadata>(pool_addr);

        // Register LP token for the resource account
        primary_fungible_store::ensure_primary_store_exists(object::object_address(&pool_obj), lp_token);
        
        // Emit event
        event::emit_event(
            &mut swap_info.pair_created,
            PairCreatedEvent {
                user: sender_addr,
                token_x: fungible_asset::name(sorted_x),
                token_y: fungible_asset::name(sorted_y),
                token_x_addr: object::object_address(&sorted_x),
                token_y_addr: object::object_address(&sorted_y),
                pool: object::object_address(&pool_obj),
                lp_token: object::object_address(&lp_token)
            }
        );
    }
   
    #[view]
    // Get tokens in a pool
    public fun pool_tokens(
        pool: Object<TokenPairMetadata>
    ): (Object<Metadata>, Object<Metadata>) acquires TokenPairMetadata {
        let pool_addr = object::object_address(&pool);
        let metadata = borrow_global<TokenPairMetadata>(pool_addr);
        (metadata.token_x, metadata.token_y)
    }
    #[view]
    // Get token reserves
    public fun token_reserves(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): (u64, u64, u64) acquires TokenPairReserve {
        // Sort tokens first
        let (sorted_x, sorted_y, swapped) = swap_utils::sort_tokens(token_x, token_y);
        
        let pool = find_pool(sorted_x, sorted_y);
        let pool_addr = object::object_address(&pool);
        let reserve = borrow_global<TokenPairReserve>(pool_addr);
        
        if (swapped) {
            (reserve.reserve_y, reserve.reserve_x, reserve.block_timestamp_last)
        } else {
            (reserve.reserve_x, reserve.reserve_y, reserve.block_timestamp_last)
        }
    }
    // Swap info
    #[view]
    public fun get_swap_info(): (address, address, u128, address) acquires SwapInfo {
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        (
            swap_info.fee_to,
            swap_info.admin,
            swap_info.mm_fee,
            swap_info.mm_fee_to
        )
    }

    // TokenPairMetadata
    #[view]
    public fun get_pair_metadata(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): (address, u128, u128, Object<FungibleStore>, Object<FungibleStore>, Object<Metadata>, Object<Metadata>, u128, Object<Metadata>) acquires TokenPairMetadata {
        let (sorted_x, sorted_y, _) = swap_utils::sort_tokens(token_x, token_y);
        let pool = find_pool(sorted_x, sorted_y);
        let pool_addr = object::object_address(&pool);
        
        let metadata = borrow_global<TokenPairMetadata>(pool_addr);
        (
            metadata.creator,
            metadata.fee_amount,
            metadata.k_last,
            metadata.token_store_x,
            metadata.token_store_y,
            metadata.token_x,
            metadata.token_y,
            metadata.swap_fee,
            metadata.lp_token
        )
    }

    
    #[view]
    // Get pair fee
    public fun get_pair_fee(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): u128 acquires  TokenPairMetadata {
        let pool = find_pool(token_x, token_y);
        let pool_addr = object::object_address(&pool);
        let metadata = borrow_global<TokenPairMetadata>(pool_addr);
        metadata.swap_fee
    }
    #[view]
    // Get LP token
    public fun get_lp_token(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): Object<Metadata> acquires  TokenPairMetadata {
        let pool = find_pool(token_x, token_y);
        let pool_addr = object::object_address(&pool);
        let metadata = borrow_global<TokenPairMetadata>(pool_addr);
        metadata.lp_token
    }
    #[view]
    // Get LP token supply
    public fun total_lp_supply(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): u128 acquires  TokenPairMetadata {
        let lp_token = get_lp_token(token_x, token_y);
        option::get_with_default(&fungible_asset::supply(lp_token), 0u128)
    }
    
    // Register for LP token
    public fun register_lp(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ) acquires  TokenPairMetadata {
        let lp_token = get_lp_token(token_x, token_y);
        primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender), lp_token);
    }
    
    // Add liquidity
    public fun add_liquidity(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        amount_x_desired: u64,
        amount_y_desired: u64
    ): (u64, u64, u64) acquires SwapInfo, TokenPairMetadata, TokenPairReserve  {
        // Verify MM fee recipient is registered for market maker fees
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);

        // Sort tokens and get the pool
        let (sorted_x, sorted_y, swapped) = swap_utils::sort_tokens(token_x, token_y);
        let (sorted_amount_x_desired, sorted_amount_y_desired) = if (swapped) {
            (amount_y_desired, amount_x_desired)
        } else {
            (amount_x_desired, amount_y_desired)
        }; 


        let pool = find_pool(sorted_x, sorted_y);
        let pool_addr = object::object_address(&pool);
        // Get reserves and calculate optimal amounts
        let (reserve_x, reserve_y, _) = token_reserves(sorted_x, sorted_y);
        
        let (amount_x, amount_y) = if (reserve_x == 0 && reserve_y == 0) {
            (sorted_amount_x_desired, sorted_amount_y_desired)
        } else {
            let amount_y_optimal = swap_utils::quote(sorted_amount_x_desired, reserve_x, reserve_y);
            if (amount_y_optimal <= sorted_amount_y_desired) {
                (sorted_amount_x_desired, amount_y_optimal)
            } else {
                let amount_x_optimal = swap_utils::quote(sorted_amount_y_desired, reserve_y, reserve_x);
                assert!(amount_x_optimal <= sorted_amount_x_desired, ERROR_INVALID_AMOUNT);
                (amount_x_optimal, sorted_amount_y_desired)
            }
        };
       
        
        // Withdraw tokens from sender
        let token_x_fa = primary_fungible_store::withdraw(sender, sorted_x, amount_x);
        let token_y_fa = primary_fungible_store::withdraw(sender, sorted_y, amount_y);
        
        // Add to pool
        let metadata = borrow_global_mut<TokenPairMetadata>(pool_addr);
        
        fungible_asset::deposit(metadata.token_store_x, token_x_fa);
        fungible_asset::deposit(metadata.token_store_y, token_y_fa);
        let store_x_addr = object::object_address(&metadata.token_store_x);
        let store_y_addr = object::object_address(&metadata.token_store_y);
        
        // Calculate liquidity amount
        let total_supply = option::get_with_default(&fungible_asset::supply(metadata.lp_token), 0u128);
        
        let liquidity = if (total_supply == 0) {
            // Initial liquidity
            let sqrt_amount = math::sqrt((amount_x as u128) * (amount_y as u128));
            assert!(sqrt_amount > MINIMUM_LIQUIDITY, ERROR_INSUFFICIENT_LIQUIDITY_MINTED);
            
            // Permanently lock MINIMUM_LIQUIDITY
            let total_liquidity = sqrt_amount;
            mint_lp_to(pool_addr, RESOURCE_ACCOUNT, (MINIMUM_LIQUIDITY as u64));
            
            // Remaining for sender
            (total_liquidity - MINIMUM_LIQUIDITY as u64)
        } else {
            // Existing liquidity - take smaller ratio
            let liquidity_x = ((amount_x as u128) * total_supply) / (reserve_x as u128);
            let liquidity_y = ((amount_y as u128) * total_supply) / (reserve_y as u128);
            
            let final_liquidity = if (liquidity_x < liquidity_y) liquidity_x else liquidity_y;
            assert!(final_liquidity > 0, ERROR_INSUFFICIENT_LIQUIDITY_MINTED);
            
            (final_liquidity as u64)
        };
        
        // Calculate fee amount
        let fee_amount = mint_fee(pool_addr);
        
        // Mint LP tokens to sender
        mint_lp_to(pool_addr, signer::address_of(sender), liquidity);
        
        // Update reserves
        update_reserves(pool_addr, false);
        let (reserve_x, reserve_y, _) = token_reserves(token_x, token_y);
        
        // Emit event
       event::emit(
            AddLiquidityEvent {
                user: signer::address_of(sender),
                token_x: object::object_address(&sorted_x),
                token_y: object::object_address(&sorted_y),
                amount_x: amount_x,
                amount_y: amount_y,
                liquidity: liquidity,
                fee_amount: (fee_amount as u64),
                reserve_x: reserve_x,
                reserve_y: reserve_y,
                lp_supply: (total_supply as u64)
            }
        );
        
        
        // Return actual amounts and liquidity
        if (swapped) {
            (amount_y, amount_x, liquidity)
        } else {
            (amount_x, amount_y, liquidity)
        }
    }
    
    // Remove liquidity
    public fun remove_liquidity(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        liquidity: u64
    ): (u64, u64) acquires SwapInfo, TokenPairMetadata, TokenPairReserve {
        // Sort tokens and get the pool
        let (sorted_x, sorted_y, swapped) = swap_utils::sort_tokens(token_x, token_y);
        let pool = find_pool(sorted_x, sorted_y);
        let pool_addr = object::object_address(&pool);
        let fee_amount = mint_fee(pool_addr);
        
        // Burn LP tokens from sender
        let metadata = borrow_global_mut<TokenPairMetadata>(pool_addr);
        let lp_token = metadata.lp_token;
        let total_supply = option::get_with_default(&fungible_asset::supply(lp_token), 0u128);
        
        let lp_tokens = primary_fungible_store::withdraw(sender, lp_token, liquidity);
        fungible_asset::burn(&metadata.burn_cap, lp_tokens);
        
        // Calculate proportional amounts
        let (store_x, store_y) = if (swapped){
            (metadata.token_store_y, metadata.token_store_x)
        }else{
            (metadata.token_store_x, metadata.token_store_y)
        };
        
        let amount_x = (((fungible_asset::balance(store_x) as u128) * (liquidity as u128) / total_supply as u128) as u64);
        let amount_y = (((fungible_asset::balance(store_y) as u128) * (liquidity as u128) / total_supply as u128) as u64);
        
        assert!(amount_x > 0 && amount_y > 0, ERROR_INSUFFICIENT_LIQUIDITY_BURNED);
        
        // Calculate fee amount
       
        // Withdraw tokens from pool and deposit to sender
        let resource_signer = account::create_signer_with_capability(&borrow_global<SwapInfo>(RESOURCE_ACCOUNT).signer_cap);
        
        let fa_x = fungible_asset::withdraw(&resource_signer, store_x, (amount_x as u64));

        let fa_y = fungible_asset::withdraw(&resource_signer, store_y, (amount_y as u64));
        
        // Update reserves
        update_reserves(pool_addr, false);
        let (reserve_x, reserve_y, _) = token_reserves(token_x, token_y);
        
        // Emit event
        event::emit(
            RemoveLiquidityEvent {
                user: signer::address_of(sender),
                token_x: object::object_address(&sorted_x),
                token_y: object::object_address(&sorted_y),
                liquidity,
                amount_x: (amount_x as u64),
                amount_y: (amount_y as u64),
                fee_amount: (fee_amount as u64),
                reserve_x: reserve_x,
                reserve_y: reserve_y,
                lp_supply: (total_supply as u64)
            }
        );
        
        // Return tokens to sender in the original order
       
            primary_fungible_store::deposit(signer::address_of(sender), fa_x);
            primary_fungible_store::deposit(signer::address_of(sender), fa_y);
            ((amount_x as u64), (amount_y as u64))
    }
    
    // Swap exact X to Y
    public fun swap_exact_x_to_y(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        amount_in: u64,
        to: address
    ): u64 acquires SwapInfo, TokenPairMetadata, TokenPairReserve {
        // Deduct market maker fee
        let (fa_in, amount_after_fee) = deduct_market_maker_fee(sender, token_x, amount_in);
       
        // Sort tokens and get the pool
        let (sorted_x, sorted_y, swapped) = swap_utils::sort_tokens(token_x, token_y);
        let pool = find_pool(sorted_x, sorted_y);
        let pool_addr = object::object_address(&pool);
        let reserve = borrow_global<TokenPairReserve>(pool_addr);
        
        // Get reserves and calculate output amount
        let (reserve_x, reserve_y) = if (swapped) {
            (reserve.reserve_y, reserve.reserve_x)
        } else {
            (reserve.reserve_x, reserve.reserve_y)
        };
        
        let metadata = borrow_global<TokenPairMetadata>(pool_addr);
        let amount_out = swap_utils::get_amount_out(
            amount_after_fee,
            reserve_x,
            reserve_y,
            metadata.swap_fee
        );

        
        // Deposit input token to pool
        let store_in = if (swapped) metadata.token_store_y else metadata.token_store_x;
        fungible_asset::deposit(store_in, fa_in);
        
        // Withdraw output token from pool
        let store_out = if (swapped) metadata.token_store_x else metadata.token_store_y;
        let resource_signer = account::create_signer_with_capability(&borrow_global<SwapInfo>(RESOURCE_ACCOUNT).signer_cap);
        let fa_out = fungible_asset::withdraw(&resource_signer, store_out, amount_out);
        // Verify k invariant
    
        if(swapped) {
            check_k(pool_addr, amount_out, 0);
        }else{
            check_k(pool_addr,0,amount_out);
        };
        
        
        // Update reserves
        update_reserves(pool_addr, true);
        let (reserve_x, reserve_y, _) = token_reserves(token_x, token_y);
        
        // Deposit output token to recipient
        primary_fungible_store::deposit(to, fa_out);
        
        // Emit event
        event::emit(
            SwapEvent {
                user: signer::address_of(sender),
                token_x: object::object_address(&sorted_x),
                token_y: object::object_address(&sorted_y),
                amount_x_in: if (swapped) 0 else amount_in,
                amount_y_in: if (swapped) amount_in else 0,
                amount_x_out: if (swapped) amount_out else 0,
                amount_y_out: if (swapped) 0 else amount_out,
                reserve_x: reserve_x,
                reserve_y: reserve_y,
            }
        );
        
        
        amount_out
    }
    
    // Swap exact Y to X
    public fun swap_exact_y_to_x(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        amount_in: u64,
        to: address
    ): u64 acquires SwapInfo, TokenPairMetadata, TokenPairReserve {
        // Deduct market maker fee
        let (fa_in, amount_after_fee) = deduct_market_maker_fee(sender, token_y, amount_in);
        
        // Call the direct function to perform the swap
        let fa_out = swap_exact_y_to_x_direct(token_x, token_y, fa_in);
        let amount_out = fungible_asset::amount(&fa_out);
        
        // Deposit output token to recipient
        primary_fungible_store::ensure_primary_store_exists(to, token_x);
        primary_fungible_store::deposit(to, fa_out);
        
        amount_out
    }
     // Swap exact Y to X direct implementation
    fun swap_exact_y_to_x_direct(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        fa_in: FungibleAsset
    ): FungibleAsset acquires SwapInfo, TokenPairMetadata, TokenPairReserve {
        let amount_after_fee = fungible_asset::amount(&fa_in);
        
        // Sort tokens and get the pool
        let (sorted_x, sorted_y, swapped) = swap_utils::sort_tokens(token_x, token_y);
        let pool = find_pool(sorted_x, sorted_y);
        let pool_addr = object::object_address(&pool);
        let reserve = borrow_global<TokenPairReserve>(pool_addr);
        
        // Get reserves and calculate output amount
        let (reserve_x, reserve_y) = if (swapped) {
            (reserve.reserve_y, reserve.reserve_x)
        } else {
            (reserve.reserve_x, reserve.reserve_y)
        };
        
        let metadata = borrow_global<TokenPairMetadata>(pool_addr);
        let amount_out = swap_utils::get_amount_out(
            amount_after_fee,
            reserve_y,
            reserve_x,
            metadata.swap_fee
        );

        // Deposit input token to pool
        let store_in = if (swapped) metadata.token_store_x else metadata.token_store_y;
        fungible_asset::deposit(store_in, fa_in);
        
        // Withdraw output token from pool
        let store_out = if (swapped) metadata.token_store_y else metadata.token_store_x;
        let resource_signer = account::create_signer_with_capability(&borrow_global<SwapInfo>(RESOURCE_ACCOUNT).signer_cap);
        let fa_out = fungible_asset::withdraw(&resource_signer, store_out, amount_out);
        
        // Verify k invariant
        if(swapped){
            check_k(pool_addr, 0, amount_out);
        }else{
            check_k(pool_addr, amount_out, 0);
        };
        
        // Update reserves
        update_reserves(pool_addr, true);
        
        fa_out
    }
    
    // Swap X to exact Y
    public fun swap_x_to_exact_y(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        amount_out: u64,
        to: address
    ): u64 acquires SwapInfo, TokenPairMetadata, TokenPairReserve {
        // Sort tokens and get the pool
        let (sorted_x, sorted_y, swapped) = swap_utils::sort_tokens(token_x, token_y);
        let pool = find_pool(sorted_x, sorted_y);
        let pool_addr = object::object_address(&pool);
        
        // Get reserves and calculate input amount
        let (reserve_x, reserve_y) = if (swapped) {
            let reserve = borrow_global<TokenPairReserve>(pool_addr);
            (reserve.reserve_y, reserve.reserve_x)
        } else {
            let reserve = borrow_global<TokenPairReserve>(pool_addr);
            (reserve.reserve_x, reserve.reserve_y)
        };
        
        let metadata = borrow_global<TokenPairMetadata>(pool_addr);
        let amount_in = swap_utils::get_amount_in(
            amount_out,
            reserve_x,
            reserve_y,
            metadata.swap_fee
        );
        
        // Handle market maker fee directly
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        let mm_fee_amount = (((amount_in as u128) * swap_info.mm_fee / FEE_DENOMINATOR) as u64);
        
        // Withdraw tokens from sender
        let mm_fee_fa = primary_fungible_store::withdraw(sender, token_x, mm_fee_amount);
        let swap_fa = primary_fungible_store::withdraw(sender, token_x, amount_in);
        
        // Deposit fee to market maker fee recipient
        primary_fungible_store::deposit(swap_info.mm_fee_to, mm_fee_fa);
        
        // Emit market maker fee event
        event::emit_event(
            &mut swap_info.market_maker_fees,
            MarketMakerFeeEvent {
                user: signer::address_of(sender),
                token: fungible_asset::name(token_x),
                fee_amount: mm_fee_amount,
            }
        );
        
        // Deposit input token to pool
        let store_in = if (swapped) metadata.token_store_y else metadata.token_store_x;
        fungible_asset::deposit(store_in, swap_fa);
        
        // Withdraw output token from pool
        let store_out = if (swapped) metadata.token_store_x else metadata.token_store_y;
        let resource_signer = account::create_signer_with_capability(&borrow_global<SwapInfo>(RESOURCE_ACCOUNT).signer_cap);
        let fa_out = fungible_asset::withdraw(&resource_signer, store_out, amount_out);
        
        // Verify k invariant
        if(swapped){
            check_k(pool_addr, amount_out, 0);
        }else{
            check_k(pool_addr, 0, amount_out);
        };
        
        // Update reserves
        update_reserves(pool_addr, true);
        let (reserve_x, reserve_y, _) = token_reserves(token_x, token_y);

        // Deposit output token to recipient
        primary_fungible_store::deposit(to, fa_out);
        
        // Emit event
        event::emit(
            SwapEvent {
                user: signer::address_of(sender),
                token_x: object::object_address(&sorted_x),
                token_y: object::object_address(&sorted_y),
                amount_x_in: if (swapped) 0 else amount_in,
                amount_y_in: if (swapped) amount_in else 0,
                amount_x_out: if (swapped) amount_out else 0,
                amount_y_out: if (swapped) 0 else amount_out,
                reserve_x: reserve_x,
                reserve_y: reserve_y
            }
        );
        
        
        amount_in 
    }
    
    // Swap Y to exact X
    public fun swap_y_to_exact_x(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        amount_out: u64,
        to: address
    ): u64 acquires SwapInfo, TokenPairMetadata, TokenPairReserve {
        // This is just the reverse of swap_x_to_exact_y
        swap_x_to_exact_y(sender, token_y, token_x, amount_out, to)
    }
    
    // Deduct market maker fee
    public fun deduct_market_maker_fee(
        sender: &signer,
        token: Object<Metadata>,
        amount_in: u64
    ): (FungibleAsset, u64) acquires SwapInfo {
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        let fee_amount = (((amount_in as u128) * swap_info.mm_fee / FEE_DENOMINATOR) as u64);
        let amount_after_fee = amount_in - fee_amount;
        
        // Withdraw tokens from sender
        let fee_fa = primary_fungible_store::withdraw(sender, token, fee_amount);
        let swap_fa = primary_fungible_store::withdraw(sender, token, amount_after_fee);
        
        // Deposit fee to market maker fee recipient
        primary_fungible_store::deposit(swap_info.mm_fee_to, fee_fa);
        
        // Emit market maker fee event
        event::emit_event(
            &mut swap_info.market_maker_fees,
            MarketMakerFeeEvent {
                user: signer::address_of(sender),
                token: fungible_asset::name(token),
                fee_amount,
            }
        );
        
        (swap_fa, amount_after_fee)
    }
    
    fun mint_fee(pool_addr: address): u64 acquires TokenPairMetadata, TokenPairReserve, SwapInfo {
    let metadata = borrow_global_mut<TokenPairMetadata>(pool_addr);
    let reserves = borrow_global<TokenPairReserve>(pool_addr);
    let fee = 0u64;
    if (metadata.k_last != 0) {
        let root_k = math::sqrt((reserves.reserve_x as u128) * (reserves.reserve_y as u128));
        let root_k_last = math::sqrt(metadata.k_last);
       
        if (root_k > root_k_last) {
           
            let lp_token = metadata.lp_token;
            let total_supply = option::get_with_default(&fungible_asset::supply(lp_token), 0u128);
            let numerator = total_supply * (root_k - root_k_last) * 8u128;
            let denominator = root_k_last * 17u128 + (root_k * 8u128);
            let liquidity = numerator / denominator;
           
            fee = (liquidity as u64);
           // Accumulate fee amount
            if (fee > 0) {
                let resource_signer = account::create_signer_with_capability(&borrow_global<SwapInfo>(RESOURCE_ACCOUNT).signer_cap);
                let resource_signer_addr = signer::address_of(&resource_signer);
                    
                // Ensure the resource signer has a store for the LP token
                primary_fungible_store::ensure_primary_store_exists(resource_signer_addr, lp_token);
                    
                // Mint the LP tokens to the resource signer
                let minted_tokens = fungible_asset::mint(&metadata.mint_cap, fee);
                primary_fungible_store::deposit(resource_signer_addr, minted_tokens);
                metadata.fee_amount = metadata.fee_amount + (fee as u128);
            }
        }
    };
    
    fee
}
    
    // Check K invariant
    fun check_k(pool_addr: address, amount_x_out: u64, amount_y_out: u64) acquires TokenPairMetadata, TokenPairReserve {
        let metadata = borrow_global<TokenPairMetadata>(pool_addr);
        let reserves = borrow_global<TokenPairReserve>(pool_addr);
        
        let balance_x = fungible_asset::balance(metadata.token_store_x);
        let balance_y = fungible_asset::balance(metadata.token_store_y);
        let amount_x_in = if (balance_x > reserves.reserve_x - amount_x_out) {
            balance_x - (reserves.reserve_x - amount_x_out)
        } else { 0 };
        let amount_y_in = if (balance_y > reserves.reserve_y - amount_y_out) {
            balance_y - (reserves.reserve_y - amount_y_out)
        } else { 0 };
        let prec = (PRECISION as u128);
        let fee = (metadata.swap_fee as u128);
        
        let balance_x_adjusted = (balance_x as u128) * prec - (amount_x_in as u128) * fee;
        let balance_y_adjusted = (balance_y as u128) * prec - (amount_y_in as u128) * fee;
        
        let reserve_x_adjusted = (reserves.reserve_x as u128) * prec;
        let reserve_y_adjusted = (reserves.reserve_y as u128) * prec;

        // Check K invariant
         let compare_result = if (balance_x_adjusted > 0 && reserve_x_adjusted > 0 && 
                               MAX_U128 / balance_x_adjusted > balance_y_adjusted && 
                               MAX_U128 / reserve_x_adjusted > reserve_y_adjusted) {
            balance_x_adjusted * balance_y_adjusted >= reserve_x_adjusted * reserve_y_adjusted
        } else {
            let p: u256 = (balance_x_adjusted as u256) * (balance_y_adjusted as u256);
            let k: u256 = (reserve_x_adjusted as u256) * (reserve_y_adjusted as u256);
            p >= k
        };
        
        assert!(compare_result, ERROR_K);
    }
    
    // Update reserves
    fun update_reserves(pool_addr: address, isSwap: bool) acquires TokenPairMetadata, TokenPairReserve {
        let metadata = borrow_global_mut<TokenPairMetadata>(pool_addr);
        let reserves = borrow_global_mut<TokenPairReserve>(pool_addr);
        
        // Use primary_fungible_store::balance_of to get the balance of the token in the store
       // Get the balance of tokens directly from the store objects
        let balance_x = fungible_asset::balance(metadata.token_store_x);
        let balance_y = fungible_asset::balance(metadata.token_store_y);
        
        reserves.reserve_x = balance_x;
        reserves.reserve_y = balance_y;
        reserves.block_timestamp_last = timestamp::now_seconds();
        if(!isSwap) {
            metadata.k_last = (balance_x as u128) * (balance_y as u128);
        }
    }
    
    // Create token store
    fun create_token_store(
        signer_ref: &signer,
        token: Object<Metadata>
    ): Object<FungibleStore> {
        let store_ref = &object::create_object_from_account(signer_ref);
        fungible_asset::create_store(store_ref, token)
    }
    
    // Mint LP tokens to an address
    fun mint_lp_to(
        pool_addr: address,
        recipient: address,
        amount: u64
    ) acquires TokenPairMetadata {
        if (amount == 0) return;
        
        let metadata = borrow_global<TokenPairMetadata>(pool_addr);
        let lp_tokens = fungible_asset::mint(&metadata.mint_cap, amount);
        
        // Ensure store exists
        primary_fungible_store::ensure_primary_store_exists(recipient, metadata.lp_token);
        primary_fungible_store::deposit(recipient, lp_tokens);
    }
    
    // Create LP token name
    fun create_lp_token_name(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): String {
        let lp_name = string::utf8(b"Warpgate-");
        let name_x = fungible_asset::symbol(token_x);
        let name_y = fungible_asset::symbol(token_y);
        
        string::append(&mut lp_name, name_x);
        string::append_utf8(&mut lp_name, b"-");
        string::append(&mut lp_name, name_y);
        string::append_utf8(&mut lp_name, b"-LP");
        
        if (string::length(&lp_name) > MAX_COIN_NAME_LENGTH) {
            string::utf8(b"Warpgate LPs")
        } else {
            lp_name
        }
    }
    
    // Generate token seed
    fun get_lp_seed(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): vector<u8> {
        let seed = vector::empty<u8>();
        vector::append(&mut seed, b"LP-");
        vector::append(&mut seed, bcs::to_bytes(&object::object_address(&token_x)));
        vector::append(&mut seed, b"-");
        vector::append(&mut seed, bcs::to_bytes(&object::object_address(&token_y)));
        seed
    }
    
    // Generate pool seed
    fun get_pool_seed(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): vector<u8> {
        let seed = vector::empty<u8>();
        vector::append(&mut seed, b"POOL-");
        vector::append(&mut seed, bcs::to_bytes(&object::object_address(&token_x)));
        vector::append(&mut seed, b"-");
        vector::append(&mut seed, bcs::to_bytes(&object::object_address(&token_y)));
        seed
    }
    
    // Admin functions
    
    public entry fun set_admin(sender: &signer, new_admin: address) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        swap_info.admin = new_admin;
    }
    
    public entry fun set_fee_to(sender: &signer, new_fee_to: address) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        swap_info.fee_to = new_fee_to;
    }
    
    public entry fun set_mm_fee_to(sender: &signer, new_mm_fee_to: address) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        swap_info.mm_fee_to = new_mm_fee_to;
    }
    
    public entry fun set_mm_fee(sender: &signer, new_mm_fee: u128) acquires SwapInfo {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global_mut<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        assert!(new_mm_fee <= MAX_FEE, ERROR_INVALID_FEE);
        swap_info.mm_fee = new_mm_fee;
    }
    
    public entry fun update_swap_fee(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        new_fee: u128
    ) acquires SwapInfo, TokenPairMetadata {
        let sender_addr = signer::address_of(sender);
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        assert!(sender_addr == swap_info.admin, ERROR_NOT_ADMIN);
        assert!(new_fee <= MAX_FEE, ERROR_INVALID_FEE);
        
        let pool = find_pool(token_x, token_y);
        let pool_addr = object::object_address(&pool);
        let metadata = borrow_global_mut<TokenPairMetadata>(pool_addr);
        metadata.swap_fee = new_fee;
    }
    
    public entry fun withdraw_fee(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ) acquires SwapInfo, TokenPairMetadata {
        let sender_addr = signer::address_of(sender);
    
        // First, verify the sender is the fee recipient
        let fee_to = borrow_global<SwapInfo>(RESOURCE_ACCOUNT).fee_to;
        assert!(sender_addr == fee_to, ERROR_NOT_FEE_TO);
        
        let (sorted_x, sorted_y, swapped) = swap_utils::sort_tokens(token_x, token_y);
        let pool = find_pool(sorted_x, sorted_y);
        let pool_addr = object::object_address(&pool);
        
        // Get the pool metadata
        let metadata = borrow_global_mut<TokenPairMetadata>(pool_addr);
        
        // Ensure there are fees to withdraw
        assert!(metadata.fee_amount > 0, ERROR_NO_FEE_WITHDRAW);
        
        // Get the resource signer capability from SwapInfo
        let resource_signer = account::create_signer_with_capability(
            &borrow_global<SwapInfo>(RESOURCE_ACCOUNT).signer_cap
        );
        let resource_signer_addr = signer::address_of(&resource_signer);
        // Withdraw the fee amount from the pool's token store
        let fee_amount = (metadata.fee_amount as u64);
        // Ensure the primary store exists for the recipient
        primary_fungible_store::ensure_primary_store_exists(sender_addr, metadata.lp_token);
        
        let fee_tokens = primary_fungible_store::withdraw(&resource_signer, metadata.lp_token, fee_amount);
        
        // Deposit to sender
        primary_fungible_store::deposit(sender_addr, fee_tokens);
        
        // Reset fee amount
        metadata.fee_amount = 0;
    }

// Get the deterministic pool address for a token pair
    public fun get_pool_address(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): address {
        // Sort tokens to ensure consistent ordering
        let (sorted_x, sorted_y, _) = swap_utils::sort_tokens(token_x, token_y);
        
        // Generate the pool seed
        let pool_seed = get_pool_seed(sorted_x, sorted_y);
        
        // Compute the deterministic address
        object::create_object_address(&RESOURCE_ACCOUNT, pool_seed)
    }

    // Check if a pair exists using deterministic address
    public fun is_pair_created(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): bool {
        // Get the deterministic pool address
        let pool_addr = get_pool_address(token_x, token_y);
        
        // Check if the TokenPairMetadata exists at this address
        exists<TokenPairMetadata>(pool_addr)
    }

    // Find pool by token pair using deterministic address
    public fun find_pool(
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): Object<TokenPairMetadata> {
        // Get the deterministic pool address
        let pool_addr = get_pool_address(token_x, token_y);
        
        // Verify the pool exists
        assert!(exists<TokenPairMetadata>(pool_addr), ERROR_PAIR_NOT_FOUND);
        
        // Return the pool object
        object::address_to_object<TokenPairMetadata>(pool_addr)
    }

    public fun fee_to(): address acquires SwapInfo {
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        swap_info.fee_to
    }
    public fun mm_fee_to(): address acquires SwapInfo {
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        swap_info.mm_fee_to
    }

    public fun get_mm_fee(): u128 acquires SwapInfo {
        let swap_info = borrow_global<SwapInfo>(RESOURCE_ACCOUNT);
        swap_info.mm_fee
    }
    
    // For testing only
    #[test_only]
    public fun initialize(sender: &signer) {
        timestamp::set_time_has_started_for_testing(sender);
        init_module(sender);
    }
}
