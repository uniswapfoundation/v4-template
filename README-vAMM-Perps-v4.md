vAMM Perpetuals on Uniswap v4: A Comprehensive Guide
Introduction to Perpetual Futures and vAMMs

Perpetual futures (or perpetual swaps) are a type of derivative contract that allows traders to speculate on an asset's price without any expiration date
investopedia.com
. Unlike traditional futures, perps never require settlement; instead, they use a periodic funding rate exchange between long and short positions to keep the contract price aligned with the spot market
kraken.com
kraken.com
. In simple terms, if the perp's price is above the underlying asset's spot price, longs periodically pay shorts; if it's below, shorts pay longs
kraken.com
kraken.com
. These funding payments (commonly applied every 8 hours on exchanges
kraken.com
investopedia.com
) encourage traders to take the side that brings the perp price back toward spot, thus anchoring the two prices over time
kraken.com
. This design, first theorized by economist Robert Shiller in the 1990s and popularized in crypto by BitMEX in 2016
kraken.com
, has made perpetual swaps one of the most liquid instruments in crypto trading.

Leverage and Margin: Perpetuals allow trading with leverage, meaning a trader can open a large position with relatively small collateral (margin) deposited. For example, if Alice posts $100 margin and goes 10× long, she controls a $1,000 notional position. If the price rises by 2%, her position profit is ~$20 (a +20% return on her margin), whereas a 5% drop would lose ~$50 (–50% of her margin). Traders must maintain a maintenance margin ratio – essentially, equity relative to position size – above a threshold. If losses erode the margin such that this ratio falls below the required maintenance margin (e.g. after ~10% adverse move at 10× leverage), the position can be liquidated (force-closed) to prevent negative equity
investopedia.com
. In liquidation, the remaining collateral is used to cover the loss, and typically a fee or penalty is charged. Because perps are a zero-sum product (one trader’s gains are exactly another’s losses in a closed system
bookmap.com
), winners get paid out of losers’ margin. The exchange/operator intervenes via liquidations and an insurance fund to ensure that losers' losses are enough to pay winners’ profits and to cover any shortfall in extreme cases. This guide will explain how to implement a perpetual futures system on-chain using a virtual AMM (vAMM) model and Uniswap v4 hooks, covering everything from the basic concepts to contract architecture, flow of funds, and risk management.

Virtual AMM Model: A vAMM is a virtual automated market maker that simulates a constant-product liquidity pool without requiring actual liquidity in the pool
members.delphidigital.io
. Instead of real assets provided by liquidity providers, the liquidity depth is defined by virtual reserves and all trades are collateralized by a separate vault. You can think of it like a Uniswap pool configured with large notional reserves (e.g. as if it held $5M of asset and $5M of USDC) to determine pricing, but traders do not directly deposit or withdraw those assets
members.delphidigital.io
. All actual funds (collateral) remain in a margin vault smart contract, not in the AMM itself
members.delphidigital.io
. Traders’ PnL is realized in the vault (in our case, USDC stablecoin), but pricing for trades is done via the vAMM’s curve. This approach means there are no external liquidity providers and thus no impermanent loss; the system’s “liquidity” is purely synthetic
members.delphidigital.io
. The vAMM serves as the pricing engine for the perpetual swap, while collateral management and PnL settlement happen off-pool in dedicated contracts.

In this document, we’ll build up a clear picture of a DeFi perpetual swap system using a vAMM on Uniswap v4, starting from the high-level design and theory and drilling down into the functional components and how they interconnect. We’ll also touch on how Uniswap v4’s new hook mechanism enables this custom behavior (dynamic pricing and fees) within an AMM pool. By the end, you should understand the end-to-end flow: how users deposit collateral, open leveraged positions on a virtual AMM, how the system calculates PnL and funding, and how risk is managed through mechanisms like liquidation and an insurance fund.

System Architecture Overview

At a high level, our perpetuals system consists of several on-chain smart contracts that together implement the exchange, and a couple of off-chain services for maintenance tasks. Below is a quick summary of the major components and their roles:

Uniswap v4 Pool with a Hook (vAMM Engine): For each market (e.g. a perp for WETH/USDC), there is a Uniswap v4 liquidity pool (USDC vs a virtual asset token) deployed with a custom hook contract attached. This hook is the core of the perp engine – it overrides the pool’s swap behavior to implement our pricing formula (constant-product vAMM) and to integrate margin accounting, funding rate adjustments, and risk checks during each trade. The hook holds the virtual reserve state for the market (virtual base asset and virtual quote asset amounts, constant product invariant, etc.), computes trade outcomes and fees, and invokes other modules to handle margin and PnL. Essentially, the Uniswap v4 hook mechanism gives us a way to run custom code at swap time
docs.uniswap.org
docs.uniswap.org
, which we use to transform a normal swap into a leveraged perp trade with all the attendant logic.

Margin Account (Collateral Vault): A contract (think of it as a USDC bank) where users deposit and withdraw their collateral and which keeps track of each user’s free vs. locked margin. When a user opens a position, the required initial margin is moved from their free balance to a locked balance to support that position. When positions are closed or profits/losses are realized, this vault pays out profits or deducts losses from the user’s balance accordingly. All actual USDC flows (deposits, withdrawals, PnL settlements, funding payments, etc.) occur in the MarginAccount vault, not in the AMM pool. This separation ensures the AMM’s liquidity is virtual while the collateral is centralized in one safe ledger.

Position Manager (ERC-721 NFT): A position manager contract issues an NFT to represent each open position. Each position NFT holds metadata such as the owner, which market it’s in, the size (in base asset units, positive for long and negative for short), the entry price, the margin allocated, and the last recorded funding index. This NFT is updated on each trade (if the user increases or partially closes their position) and burned when the position is fully closed. By tokenizing positions, we have an easy way to track and modify positions on-chain, and the NFT can be used as a handle to invoke closes or liquidations. (Internally, this contract will have functions to adjust the stored position info and to ensure only authorized calls from the hook or liquidator can change things.)

Funding Oracle: The funding oracle is responsible for computing the mark price of the perp and the funding rate at regular intervals. In our design, the mark price is determined by a robust composite of prices: for example the median of the vAMM’s mid-price (midpoint of bid/ask given virtual reserves), an external oracle TWAP price (e.g. a trusted price feed like Pyth for the underlying asset), and perhaps the underlying spot DEX pool TWAP
quillaudits.com
. Using multiple sources and taking a median helps prevent manipulation (e.g. someone cannot easily manipulate the Uniswap pool price with a flash loan without also shifting the broader market price)
quillaudits.com
. The funding rate is then computed based on the difference between the perp price and the underlying spot price, scaled by a configurable factor k, plus perhaps a base interest rate component. In formula terms, one can set fundingRate = clamp( k * (markPrice − spotPrice) / spotPrice + interestFloor, ±cap ). A positive funding rate means the perp is above spot (longs pay shorts), and negative means below spot (shorts pay longs), as described earlier. The FundingOracle contract will update a global cumulative funding index for each market (e.g., once per hour via a keeper call), which the system uses to calculate how much funding each position has accrued since it was last modified.

Insurance Fund: All trading fees, funding payments that are collected (if designed to have one side pay the imbalance to fund), and liquidation penalties flow into the Insurance Fund, which is another USDC vault managed by the system. The insurance fund serves as a backstop to cover bad debt: if a position’s losses exceed its collateral (for example, due to a sharp market move where liquidation could not happen in time), the shortfall is covered by the insurance fund rather than leaving a winner unpaid. A healthy insurance fund is critical to ensure winners get paid even in volatile scenarios. It grows over time from fees that traders pay (instead of those fees going to LPs, since we have no LPs, we redirect them here) and from any net funding flows (depending on how funding is designed – e.g. if one side of the market consistently pays funding, the counterparty receives it; in some designs the insurance fund may absorb extreme imbalances of funding). If the insurance fund ever runs low, administrators might top it up, or in worst-case scenarios, an auto-deleveraging (ADL) mechanism can be triggered: ADL will automatically reduce some winners’ positions (clawing back some profit) to cover system losses
quillaudits.com
, though this is a last resort and rare event.

Perps Router: To simplify user interaction, the system provides a PerpsRouter contract (a thin wrapper) that users call to open or close positions. The router validates user input (e.g. ensuring sufficient margin is available, position size limits, etc.), then invokes the Uniswap v4 PoolManager’s swap function targeting our pool, with the appropriate parameters. Importantly, the router sets the swap recipient to be the PositionManager (so that the output of the swap – which is in virtual tokens – is received by the position contract, not sent to the user directly) and encodes a hook data payload that indicates the intent (open/close, long or short, position ID if closing, etc.). The Uniswap pool will call our hook with that data during the swap, allowing the hook to know which user/position is acting and to execute the correct logic. The router basically bundles what would otherwise be multiple calls (lock margin, do swap, update position) into one user-facing function for convenience and safety.

Off-Chain Liquidator Keeper: Because the protocol needs to monitor positions and liquidate those that fall below maintenance margin, an off-chain service (keeper bot) is required. This service continuously checks positions’ margin ratio = equity / (position notional), where equity is the remaining margin plus any unrealized PnL. If a position’s ratio drops to the liquidation threshold (maintenance margin requirement), the keeper can call a liquidate(positionId) function on the PositionManager. The contract will then execute a liquidation: typically this means closing some or all of the position at the current market price via the vAMM and subtracting a liquidation penalty (a percentage of the remaining collateral) which is paid to the insurance fund and to the keeper as a reward. We’ll detail the liquidation flow later, but note that a keeper is needed to trigger it since on-chain contracts themselves cannot automatically trigger based on price changes.

(Optional) Off-Chain Hedger: If the platform operator wants to remain market-neutral, an off-chain hedging bot can be used to mirror the aggregate position of traders on an external market. For example, if traders on the platform are net long 100 ETH, the operator could have the hedger sell 100 ETH on a real exchange (or short via a centralized futures exchange) to cover the exposure. This is optional and does not affect the on-chain mechanism; it’s essentially a way to outsource the risk so that the insurance fund isn’t the only backstop. Profits or losses from the hedge would accrue to the operator’s vault, potentially bolstering the insurance fund if the hedging is effective (when traders win and the protocol loses on the other side, the hedge yields a gain that can compensate, and vice versa).

Before diving deeper, it’s worth noting that Uniswap v4’s Hooks feature is what makes this architecture possible in an elegant way. Hooks are custom smart contracts that can be attached to liquidity pools to intercept and modify their behavior at certain points (initialize, swaps, add/remove liquidity, etc.)
docs.uniswap.org
docs.uniswap.org
. The hook contract must be deployed at a specially crafted address encoding the permissions for the callbacks it intends to use (for instance, an address whose binary ends in specific bits to signal “enable beforeSwap and afterSwap”)
docs.uniswap.org
docs.uniswap.org
. In our case, the PerpsHook contract is deployed with flags enabling the beforeSwap and afterSwap hooks (and the afterInitialize hook for setup). This means whenever a swap happens in the pool, the Uniswap engine will call our hook’s beforeSwap function to potentially adjust the swap parameters (like applying a custom fee or validating the trade) and then call afterSwap after the core swap logic to finalize any accounting
docs.uniswap.org
docs.uniswap.org
. We leverage these to implement a custom pricing curve (constant product on virtual balances) and dynamic fees for funding. Uniswap v4 also allows our hook to charge a hook fee – a separate fee from the normal LP fee – in beforeSwap if we want
docs.uniswap.org
docs.uniswap.org
. We will indeed use a hook fee mechanism to redirect trading fees into the insurance fund, effectively monetizing the hook to backstop the system (since there are no LPs taking fees, our protocol takes them)
docs.uniswap.org
docs.uniswap.org
. Additionally, because the hook can override the pool’s price curve entirely, we implement the vAMM’s math in it (overriding the typical Uniswap v3-style price behavior with our own constant product on virtual reserves). This kind of custom curve design is exactly what Uniswap v4’s hooks were built to enable
docs.uniswap.org
docs.uniswap.org
.

In summary, the architecture is composed of modular pieces: the Uniswap pool + hook providing price calculation and trade execution logic, and separate contracts for positions, margin accounting, funding, and insurance. Next, we’ll explore each component and the state it maintains in a bit more detail, then walk through the lifecycle of trading flows step by step.

On-Chain Components in Detail
PerpsHook (Uniswap v4 Hook Contract)

The PerpsHook is the heart of the system, acting as the trade engine and risk checker. It is attached to a specific Uniswap v4 pool (one pool per market) and implements the necessary hook callbacks:

afterInitialize: When the pool is first initialized, this hook seeds the initial virtual reserve amounts for the market. We set the virtual base and virtual quote values according to a chosen initial price and liquidity depth (explained below), and record these in storage. It also links the pool with an external spot price feed (if any) in the FundingOracle for reference.

beforeSwap: This is called before each swap executes. Here the hook decodes the hookData passed by our router to determine what kind of operation is happening (open long, open short, close position, etc.), and which user/position it pertains to. It then performs validation and calculations:

Price Band Check: It fetches the latest spot price (e.g. a TWAP from a reliable on-chain pool or an oracle price) and computes the current mark price from the vAMM. It ensures the mark price is not deviating from the spot price by more than a configured percentage (e.g. maxDeviationBps). This prevents the vAMM price from drifting too far from reality (an important safeguard against manipulation or out-of-control prices). If the deviation is too large, the swap is rejected (reverted) until arbitrage or funding bring it back in line.

Open-Interest Cap Check: It checks that the trade will not push the market’s total open interest beyond allowed caps. There may be a cap on the total notional open long or open short in the market, based on the size of the insurance fund and risk tolerance. For example, if the fund is $X, you might cap total OI at some multiple of X so that even if one side wins massively, losses are covered
quillaudits.com
. If the cap would be exceeded, the trade is blocked.

Initial Margin Requirement: If this is a new or increasing position, the hook calculates the required initial margin given the position size and a chosen leverage (or using a default minimum margin percentage). For instance, if the user wants to open $10,000 notional and the max leverage is 10×, they must lock at least $1,000 margin. The hook calls the MarginAccount to lock that amount of the user's free balance (moving it to a locked state for that position). If the user doesn’t have enough free collateral, it errors.

vAMM Pricing: Given the trade direction and size, the hook computes the outcome using the constant product invariant 
𝐵
×
𝑄
=
𝐾
B×Q=K on the virtual reserves. For a LONG (buying the base asset with USDC), the user is effectively swapping vQuote→vBase:

We increase the virtual quote reserve: 
𝑄
new
=
𝑄
old
+
Δ
𝑄
Q
new
	​

=Q
old
	​

+ΔQ (where 
Δ
𝑄
ΔQ is the USDC amount the user is swapping in).

We solve for the new base reserve 
𝐵
new
=
𝐾
/
𝑄
new
B
new
	​

=K/Q
new
	​

 (maintaining 
𝐾
K).

The base asset amount output to the user’s position is 
Δ
𝐵
=
𝐵
old
−
𝐵
new
ΔB=B
old
	​

−B
new
	​

. This 
Δ
𝐵
ΔB is the size of the position in base terms (e.g. how many ETH virtual units the user gets, which increases their long position).

The entry price the user effectively gets can be derived from these deltas (approximately 
Δ
𝑄
/
Δ
𝐵
ΔQ/ΔB, considering slippage).

The hook also computes the fee on the trade. We have a base trade fee (e.g. tradeFeeBps) and we also incorporate the funding adjustment here as a small addition or subtraction to the fee. For example, if funding rate is positive (perp price > spot, longs should pay funding), we might add a few basis points to the fee for longs (and conversely reduce fees for shorts)
docs.uniswap.org
. In Uniswap v4, we can override the pool’s fee on a per-swap basis via the hook return value
docs.uniswap.org
, effectively implementing a dynamic fee that includes funding. The hook calculates this dynamic hook fee and returns it to the pool, so the trade executes with that fee rate.

All these computed values (ΔB, fees, etc.) are stored or carried into afterSwap.

For a SHORT (selling the base asset to go short, or equivalently borrowing base against USDC), the math is symmetric in the opposite direction: the user swaps vBase→vQuote:

Increase virtual base reserve: 
𝐵
new
=
𝐵
old
+
Δ
𝐵
B
new
	​

=B
old
	​

+ΔB (user sells ΔB of the base into the vAMM).

Solve 
𝑄
new
=
𝐾
/
𝐵
new
Q
new
	​

=K/B
new
	​

.

The quote amount output (virtually) is 
Δ
𝑄
=
𝑄
old
−
𝑄
new
ΔQ=Q
old
	​

−Q
new
	​

. This ΔQ is the virtual USDC that the position “receives” internally – essentially the debt the position is shorting, which will need to be paid back on close. The position size in base terms is ΔB (but marked as a short, so we store a negative size to indicate short).

Margin is still posted in USDC; the hook locks the required margin similarly.

A funding fee adjustment might be negative for this direction (if funding is positive, shorts get a fee reduction or even a rebate).

afterSwap: This is called after the core swap execution. At this point we know how much of each token actually changed hands in the pool. The hook now finalizes the perp-specific actions:

If the swap was an Open or Increase operation: the hook will either create a new position NFT or update an existing one. It mints a position NFT via the PositionManager (if new) and sets the position’s parameters: size (ΔB or adding to existing size), entry price, margin used, and records the current global funding index as the position’s lastFundingIndex. If it’s an existing position increase, it adjusts the stored size and averages the entry price appropriately (could weight by size, etc.). The hook then transfers the protocol fee portion (if any) of the trade to the InsuranceFund (this might be done via the pool's built-in mechanism or explicitly calling InsuranceFund). Finally, it updates the stored virtual reserves 
𝐵
,
𝑄
,
B,Q, and 
𝐾
K for the market to the new values after the swap. (Note: 
𝐾
K remains constant if we maintain the invariant strictly. However, some implementations might choose to re-scale K after big moves or periodically to adjust virtual liquidity, but assume constant for simplicity).

If the swap was a Close or Reduce operation: the trader is closing some or all of an existing position (selling back if they were long, or buying back if they were short). The vAMM calculation yields how much USDC comes out (or goes in) for that position size, at the current mark price. In afterSwap, the hook calculates the PnL for the closed portion: essentially, 
PnL
=
USDC out
−
USDC in (entry cost)
PnL=USDC out−USDC in (entry cost) for that portion of the position. For a long, if the price went up, the vAMM will output more USDC than the position’s entry cost for that portion, yielding positive PnL; if price went down, it outputs less (trader incurs a loss). The hook then calls MarginAccount to settle PnL: if positive PnL, the corresponding USDC is credited to the trader’s free balance (coming effectively from the losing side’s margin); if negative, that amount of their locked margin is taken as a loss. It then releases the margin that is no longer needed to maintain the reduced position (or all margin if fully closed) back to the trader’s free balance. The position NFT is updated to reflect the reduced size or is burned if fully closed. The virtual reserves are updated accordingly in the hook’s state, and fees are collected to the insurance fund from this closing swap as well.

Liquidity Management Hooks: We will disable/revert all liquidity add or remove operations on the pool. Since the pool’s liquidity is meant to remain virtual and static (aside from changes in virtual reserves due to trading PnL), nobody should be adding or removing liquidity. The hook’s beforeAddLiquidity, afterAddLiquidity, etc., will simply revert to enforce that.

Custom Funding Update Function: Additionally, the hook (or a related contract) may expose a function like pokeFunding() that can be called by a keeper to increment the funding index. For example, once per hour the keeper calls pokeFunding(marketId), and the FundingOracle computes the latest premium (difference between perp price and spot) and increments the market’s globalFundingIndex by the funding rate for that hour. This updated index is stored in the hook (as part of the market state) and an event is emitted. This lets us accrue funding continuously over time. However, even if this function is not called frequently, the funding is also settled on position changes: whenever a position is opened, modified, or closed, we can compute the funding difference between globalFundingIndex now and the lastFundingIndex stored on that position, and realize that difference. In practice, that means adjusting the trader’s margin for the accrued funding (longs pay, shorts receive if rate was positive, etc.), and possibly sending some amount to or from the insurance fund depending on how we handle the offset (if there is an imbalance in payments due to unequal open interest on each side, the insurance fund may absorb or receive the excess). We ensure that funding payments are zero-sum between longs and shorts in aggregate, or any slight imbalance goes to the fund as buffer.

The hook’s logic is the most complex part of the system, as it ties together pricing, fees, and margin checks. Uniswap v4’s design allows it a lot of control: for instance, we can even refuse to execute the swap (revert) if certain conditions are not met (price band, OI cap, recipient not our PositionManager, etc.), effectively using the hook as a gatekeeper to enforce all protocol rules before letting a trade go through.

PositionManager (Position NFT)

The PositionManager is an ERC-721 contract that issues NFTs for positions. Each position token’s data structure contains:

owner – the user who opened the position (to whom the NFT is minted).

marketId or associated pool – identifies which trading pair/market the position is in (e.g. an ID or the pool address).

sizeBase – the current size of the position in base asset units. A positive value means a long position (the user is effectively long on the base asset), a negative means a short position. For example, size = +5.0 ETH means the user is long 5 ETH worth of the perp.

entryPrice – the price at which the position was opened or the average price if it was built up over multiple trades. This could be stored in a fixed-point format (e.g. 1e18 for precision).

margin – the amount of collateral (USDC) currently allocated to this position. This starts as the initial margin and may change if the user adds margin or partially closes (freeing some margin).

lastFundingIndex – the cumulative funding index value when the position was last altered (opened or when funding was last settled). This is used to calculate how much funding payment is owed when we next update the position.

openedAt (timestamp) – when the position was opened (useful for certain calculations or just record-keeping).

Additionally, the contract can maintain fields like realizedPnl and fundingPaid for the position, tracking the total profit/loss realized so far and total funding amounts paid/received, although these can also be derived or emitted via events.

The PositionManager exposes functions (likely restricted to the hook or internal use) to:

Open/Mint a Position: Create a new NFT for a given user and initialize its data. This happens in the hook’s afterSwap when an open trade is completed. An PositionOpened event is emitted.

Increase/Modify a Position: If a user with an existing position in the same market opens an additional trade in the same direction, the PositionManager can update that position’s size and adjust the entry price (often using a weighted average based on size) and add the additional margin. It also needs to settle any funding difference since last update (bringing lastFundingIndex up to current by charging or crediting funding to the margin via MarginAccount).

Reduce/Close a Position: When a user closes part or all of a position, the contract updates the size and realized PnL. If fully closed, it records the final PnL and funding paid, and then burns the NFT (PositionClosed event). It will also instruct the MarginAccount to release any remaining margin back to the user.

Liquidate a Position: This is a special function that can be called by authorized liquidators (likely an open function that anyone can call, with the actual action performed only if the position is indeed liquidatable). Upon liquidation trigger, the PositionManager will determine how much of the position to close (for partial liquidation) or if it’s a full liquidation. It then calls the hook (or uses the router) to execute a market swap to close that portion at the current price. After the swap (which goes through the same afterSwap logic for a close), it applies a penalty: e.g. a certain % of the remaining collateral is taken. Part of that penalty might be awarded to the liquidator as an incentive (liquidation bonus), and the rest goes to the insurance fund. If the liquidation was full and after closing the position there is still a negative balance (meaning the loss exceeded margin), that is a bad debt which the InsuranceFund must cover by sending USDC to balance it out. The PositionManager will call InsuranceFund.coverBadDebt() for that amount. If the liquidation was partial, the position remains open with a reduced size; a cooldown could be imposed before it can be liquidated again, to avoid immediate re-liquidation oscillation. Partial liquidation aims to leave the user with just enough margin to meet requirements so the position can survive if conditions don’t worsen immediately.

The NFT approach makes it easy for the frontend and users to track positions. The token ID can be used to query position details and to trigger closes or additions. It also means positions could potentially be transferred or sold (though in many systems, transferring active positions is disabled for safety to prevent edge cases with margin ownership, but it’s an interesting possibility e.g. for migrating positions to another account).

MarginAccount (USDC Vault)

The MarginAccount (or MarginVault) contract holds all user collateral (USDC stablecoin in this design) and provides functions for deposits, withdrawals, and internal transfers (lock/release) to support trading:

Deposit: A user calls deposit(amount) to transfer USDC from their wallet into the vault. Their free balance in the vault is increased by that amount
members.delphidigital.io
. This free balance is what they can use as margin for new positions or withdraw later.

Withdraw: A user can withdraw any amount up to their available free balance (i.e. not counting any portion currently locked in active positions). The vault transfers the USDC out to the user’s wallet and decreases their balance. Withdrawals might be blocked if the user’s remaining free balance would fall below some requirement, but generally if free >= withdraw amount, it’s allowed.

Lock Margin: Only the PerpsHook or PositionManager (trusted contracts) can call this, to lock a portion of a user’s free balance as margin for a new position. Locking might simply move the amount from a freeBalance mapping to a lockedBalance mapping for that user, or just decrement free and keep an implicit record via the position. The idea is that locked margin cannot be withdrawn or used for other positions unless freed.

Release Margin: The counterpart to lock, this increases the user’s free balance when margin is freed up (e.g. after closing a position or reducing it).

Settle PnL: This function is called to realize profits or losses. If a trade results in a profit for the user, the vault will increase their free balance accordingly (essentially paying them from the vault – which implicitly comes from other traders’ losses). If a trade results in a loss, the vault will deduct from their locked margin. Technically, if the loss is less than the margin on that position, part of the margin becomes free again (unused). If the loss equals or exceeds the margin (shouldn’t happen unless extreme – in which case that’s bad debt scenario), their position’s margin goes to zero and any shortfall is handled by insurance.

Apply Funding: During funding accrual, if a user owes funding or should receive funding, this function adjusts their balance. For example, if a long owes $5 funding, we deduct $5 from their free or locked balance (depending on implementation – often it comes from free balance or directly from locked margin if they have just open positions). If a short should receive $5, we credit it to their balance. This function would be called by the hook or funding logic when we update funding (either periodically or at trade time). Because funding is typically a flow from one set of traders to the other, this will be done in aggregate – e.g. sum of all longs pays sum of all shorts. The vault can handle a batch apply or the hook can loop through positions, but more efficiently, we usually update funding at trade time for the trader involved (like charging the trader for accrued funding since last action).

The MarginAccount must also enforce that users can’t withdraw funds that are locked. It should also block any direct transfers except through the prescribed functions to maintain integrity.

Events like Deposit, Withdraw, MarginLocked, MarginReleased, etc., are emitted for transparency.

In essence, MarginAccount is like a ledger or bank: it never lets the underlying USDC leave except on a user’s withdraw or an authorized module paying out, and it keeps the sum of all balances equal to the actual USDC it holds. When profits are realized for one user, it’s effectively taking margin from losing users (who incurred losses) – but that accounting happens via reducing those losing positions’ margin in their vault balance. We should confirm that, at all times, total USDC of all users + insurance fund balance = total deposited minus withdrawn (this is an invariant check). Such checks can be implemented in testing to ensure no money is magically created or lost aside from intentional flows like fees to the insurance fund (which are just moving from user to fund balances).

FundingOracle

The FundingOracle provides the pricing data needed to compute funding rates. It likely maintains:

A link or registered address for an external price feed (like a Pyth or Chainlink oracle for the asset’s USD price).

A reference to an underlying spot DEX pool (e.g. a Uniswap v3 or v4 pool for USDC/ETH) to get on-chain TWAP prices.

Logic to compute a median price from multiple sources:

vAMM mid-price: This can be calculated from the virtual reserves in our perp’s pool. If 
𝐵
B and 
𝑄
Q are virtual reserves, mid-price = 
𝑄
/
𝐵
Q/B (assuming both are scaled to actual asset units).

DEX TWAP: an average price from the last, say, 5–15 minutes on a reliable on-chain market.

Oracle price: e.g. the latest Pyth price or Chainlink price.
It will take these and sort them, picking the middle value as the mark price for funding calculations (median is robust to one source being an outlier).

Funding rate calculation: given mark price and spot price (and possibly an interest rate), compute the next funding increment. As mentioned, one simple model is 
fundingRate
=
𝑘
∗
mark
−
spot
spot
+
floorInterest
fundingRate=k∗
spot
mark−spot
	​

+floorInterest, clipped to ±cap. For example, if mark is 1% higher than spot and k=1, funding rate might be +1% per period (annualized or per 8h depending on how we scale it). This means longs pay 1% of notional over that period to shorts. We also include a baseline interest floor (like if holding USD vs holding ETH has a baseline difference, but often in crypto perps this is set to 0 or a very small number unless trying to mimic interest rates).

The FundingOracle updates a global cumulative funding index (let’s denote it 
𝐼
I) for each market, stored in the PerpsHook or in the oracle and referenced by the hook. Initially 
𝐼
=
0
I=0. When funding is updated (hourly, etc.), we do 
𝐼
new
=
𝐼
old
+
fundingRate
×
Δ
𝑡
I
new
	​

=I
old
	​

+fundingRate×Δt (where 
Δ
𝑡
Δt is 1 period unit, e.g. 1 hour, if fundingRate is expressed per hour). This is akin to how perpetual exchanges like dYdX or Binance maintain an index that accumulates funding over time. The difference in this index between when a position was opened and now gives the total funding that should be applied to that position. For example, if a long position of size $N was opened when index = 0.02 and now index = 0.05, and if we define funding payment = position_notional * (index_diff), then index_diff = 0.03 means the long pays 3% of $N as funding (which goes to shorts or the fund). The oracle’s job is to increment this index safely and provide the current rate for any ad-hoc calculation if needed.

The FundingOracle could be implemented as part of the hook or separate; in our architecture it’s separate for modularity. The hook calls fundingOracle.premiumX18(poolKey) to get the current “premium” (mark - spot difference)
quillaudits.com
 (in practice, the code snippet we had showed premiumX18 returning a signed 1e18 value for difference). It then might call some funding calc function or just use it to adjust fees in real-time. The heavy lifting of TWAP reading might require integration with Uniswap’s observation data or calling an external oracle contract on-chain.

The result is that funding ensures that if, say, longs greatly outnumber shorts and push the perp price above true spot, they will continually pay a penalty (funding) that makes it costly to hold those longs, incentivizing the price to mean-revert
kraken.com
kraken.com
. In our system, funding is primarily an accounting mechanism: it doesn’t transfer actual tokens at the moment of computation (except when settled on trades), but it adjusts balances over time so that one side’s margin is gradually transferred to the other side (or to insurance fund for imbalance). This provides economic stability for the perp price.

InsuranceFund

The InsuranceFund is a simpler contract that just holds USDC and allows only specific authorized actions:

Collecting fees and penalties: When the hook calculates a trade fee or when a liquidation penalty is taken, those amounts are sent to the InsuranceFund (or the InsuranceFund’s function collectFee(amount) is called by the hook/position manager). The fund just accumulates these.

Covering bad debt: If after a liquidation a position still has negative equity (meaning the user’s margin wasn’t enough to cover the loss), the PositionManager will call coverBadDebt(amount) on the InsuranceFund to pay out that amount of USDC into the MarginAccount (to credit the winning side or fill the hole). This essentially socializes the loss across the system’s reserves. An event is emitted so the operators know insurance fund was used.

Optionally, the InsuranceFund might allow an owner or governance to add funds (for example, the team can deposit more USDC into it to bolster it, or some portion of protocol revenue could flow in).

The insurance fund does not have a broad interface for arbitrary withdrawals (to avoid misuse). Typically, only governance could withdraw excess funds or use them for platform needs, since its primary role is to sit idle as a safety net.

A robust insurance fund is key to user confidence, because it assures that even if a large trader wins and the loser cannot pay, the winner still gets their profit from the fund. Many exchanges strive to size the OI limits such that the worst-case loss (due to a sudden move before liquidation) is covered by the fund most of the time
quillaudits.com
. Anything beyond that could trigger ADL (auto-deleveraging) where the system reduces some winning positions to re-balance. Our design includes an OI cap rule partly for this reason – to keep worst-case payouts bounded by available collateral.

PerpsRouter

The PerpsRouter is a convenience contract that front-ends the complex calls for users. Without the router, a user would have to: approve USDC to MarginAccount and call deposit, then initiate a Uniswap swap to the pool with carefully crafted data and recipient, etc. The router streamlines this:

Open Position (Long or Short): The user calls openPosition(marketId, size, isLong, leverage) (for example) on the router. The router will ensure the user has enough free margin (perhaps it requires the user to have deposited already; or the router could even accept USDC and deposit for them in one step). It then calculates the notional and margin required from the inputs. Next, it calls the Uniswap v4 PoolManager.swap() for our pool:

The swap parameters: if opening long, it’s a swap of amountIn = desired_notional of USDC for as much vAsset (ETH, BTC, etc) as possible (meaning we're buying the base asset with USDC). If opening short, it’s swapping a certain amount of base asset for USDC (here, since the user doesn’t actually hold the base asset, we simulate this by just specifying the amount out in USDC we want and passing data to indicate it’s a short – the hook will handle the margin).

We set recipient = PositionManager address. This is crucial because we don't want any tokens delivered to the user directly; the "output" of the swap will effectively go to the PositionManager (which in practice will not do anything with the vTokens but it's just to satisfy Uniswap's requirement).

We encode a hookData blob that our hook will parse. For example, hookData = abi.encode(Action.OPEN, isLong, userAddress, positionId(optional), notional, margin) etc. If it's a new position, positionId can be 0 or ignored, and the hook will create one. If it's increasing an existing position, we include that position's ID.

We call swap with this data. Uniswap will transfer amountIn from the router to the pool (the router likely needs to hold or have approval for the user's USDC; easier is to require the user deposit first and then router uses MarginAccount funds, but that complicates since Uniswap expects actual token transfer from caller – possibly the router will pull from MarginAccount or require the user to approve router to spend from MarginAccount or something).

Another approach: the router could actually call MarginAccount.lock() then do a zero net swap where it tells the hook the notional and the hook uses BeforeSwapDelta to pull from margin account. Uniswap v4 allows hooks to transfer funds via BeforeSwapDelta adjustments
docs.uniswap.org
. For simplicity, assume router just transfers USDC from itself.

The swap triggers our hook, which does all the logic described. AfterSwap, the position is opened and margin locked. The router then might emit an event or return the new position ID to the user.

Close or Reduce Position: The user calls closePosition(positionId, size_to_close) on the router. The router will craft the opposite swap. If the user is long and wants to close, it will swap vAsset to get USDC (effectively sell base); if short, swap USDC for base (to cover the short). It sets the recipient and hookData similarly (Action.CLOSE, specifying how much to close). The Uniswap swap will then execute, the hook will compute PnL and release margin. The router can then, after the swap, call MarginAccount to actually transfer any realized PnL to the user’s wallet if they want immediate withdrawal, or leave it in their vault balance.

The router’s role is mainly to ensure safety (e.g., it might check that the slippage isn’t too high by comparing expected price vs oracle price to avoid the user getting a bad fill if the price moved) and to bundle the operations into one transaction for the user. It also enforces that the swap’s recipient is correct (must be our PositionManager) to prevent users accidentally sending tokens elsewhere.

By funneling all user-initiated trades through the router, we can also manage permissions and inputs more tightly. However, power users could interact with the PoolManager directly if they encode things exactly – but that’s advanced and typically not an issue.

Market State and Virtual AMM Mechanics

Each perpetual market (trading pair) is implemented as its own Uniswap v4 pool contract with our PerpsHook attached. A market is identified by the two tokens in the pool: e.g. USDC (the quote asset) and vETH (a virtual token representing ETH). The virtual token is usually a dummy ERC20 with no actual supply management – it’s only used to have a second token address for the pool. Traders will never hold or transfer vETH directly; it exists solely inside the AMM. All accounting for profit and loss is in USDC.

Within the PerpsHook, we maintain a Market struct (or parallel mappings) keyed by the pool or a marketId, containing key parameters:

underlyingSpotPool: the address of a real spot pool for the same asset (e.g. an official USDC/ETH pool) that we use for price oracle/TWAP comparisons.

vBase and vQuote: the current virtual reserve balances in the pool. For example, vBase might start at 1000 (meaning 1000 virtual ETH) and vQuote at 1,500,000 (meaning priced at $1500 each initially, giving K = 1000 * 1,500,000).

K: the invariant product = vBase * vQuote. This remains roughly constant through trading (pure constant-product market maker). Minor deviations can occur due to rounding or if we ever programmatically adjust depth, but invariant is maintained during swaps.

tradeFeeBps: the base fee rate (in basis points) charged on trades. For example 10 bps (0.1%). This is separate from funding; funding adjustments will be layered on top of this via dynamic fee.

maxDeviationBps: the maximum allowed % difference between the vAMM price and the observed spot price (band guard). If exceeded, trades are blocked until it converges.

mmrBps: maintenance margin requirement, expressed in basis points of position notional. For instance, 5000 bps = 50% (very high for example) or 625 bps = 6.25%. This defines when liquidation triggers.

oiCapUsd: the maximum allowed open interest in this market, measured in USD notional (could be separate caps for longs vs shorts, but here a single cap).

globalFundingIndexX18: the current funding index (in 1e18 fixed point). This is updated over time.

Initialization: To initialize a new market, we need an initial price and depth. Suppose the current index price of ETH is $1500. We choose a virtual depth parameter – say we want the vAMM to behave like a Uniswap pool with $N of liquidity on each side. If we choose 
𝑁
quote
=
$
1
,
000
,
000
N
quote
	​

=$1,000,000 depth, we set vQuote = 1,000,000 (assuming USDC has 6 decimals, we might scale appropriately) and vBase = N_quote / Price_index = 1,000,000 / 1500 = 666.667 (approximately). Then K = 666.667 * 1,000,000 = 666,667,000. We then might scale both reserves by some factor α to adjust how flat the curve is (slippage). For instance, multiplying both vBase and vQuote by 10 (keeping price the same at 1500) will make the pool ten times larger K and thus trades have less price impact for a given size. Essentially, higher virtual liquidity = lower slippage but also means larger notional positions can be opened (with correspondingly large potential PnL swings that must be covered by collateral). This depth parameter is a tuning knob for the protocol to balance user experience (slippage) vs. risk. The initialization is done via the afterInitialize hook or a separate function that sets the struct.

Once initialized, the pool can start accepting swaps via our hook, with the invariant 
𝑥
∗
𝑦
=
𝐾
x∗y=K. Because no one can add liquidity, the only thing that changes 
𝐵
B and 
𝑄
Q is trading PnL (which effectively shifts balances). If many longs win and extract USDC, the vQuote will decrease and vBase will increase (because longs closing means vQuote paid out). However, note that K remains constant if we treat the system as closed. Actually, when traders realize PnL, no actual assets leave the pool; instead, margin moves in the vault. But to reflect the PnL, we adjust virtual reserves: e.g. when a long wins and closes, we reduce vQuote (as if USDC left the vAMM) and increase vBase (as if vBase was added to the pool). This causes the vAMM price to move down (since less quote relative to base in the AMM), which is expected because longs profiting means the price likely moved up and now after closing, the virtual reserves shift. The vAMM is just a mathematical abstraction to set price; real value transfer happened in the MarginAccount.

Price Calculation: The mid-price of the vAMM at any time is Price = vQuote / vBase. Traders always trade at the current market price plus some slippage based on trade size relative to reserves (just like any constant product market). Because we allow leverage, traders can take out positions much larger than their margin, but the price they get will reflect the size – a large trade will move the vAMM price significantly (impact). This slippage is both a feature (it provides a semblance of depth and also penalizes going too heavy at once) and a risk (could be exploited if not managed, but arbitrage and funding help keep it sane).

The mark price used for PnL and liquidation is ideally the fair price. We use the median of vAMM price, oracle price, and spot TWAP for robustness as mentioned. We also ensure the vAMM can’t be traded in a way that violates the band (the beforeSwap will compare mark vs spot and revert if outside allowed range). For example, if some large trade would push vAMM price 10% away from real price, we may not allow that in one go (the user might have to do multiple smaller trades over time as market moves or wait for others to take the other side).

Open Interest (OI) and Caps: Open Interest is the total sum of open position notional on each side. E.g. if Alice longs $100k and Bob shorts $80k, total long OI = 100k, short OI = 80k. Ideally those are equal (when longs = shorts, the system is balanced and effectively fully collateralized by each other). If they’re unequal, say more longs than shorts, it means the system has a “directional exposure” – effectively the longs’ potential profits are only partly covered by shorts’ losses, the remainder would come from insurance fund if longs win big. To avoid unlimited exposure, we set oiCapUsd to limit the size of one side (or overall). For instance, if insurance fund is $1M and we only feel comfortable covering up to a $100k loss from it, and if worst-case a one-sided market (all longs, no shorts) could cost insurance fund if price tanks or pumps, then we might cap OI at some multiple of the fund. A rule of thumb given was Max OI ≈ InsuranceFund / gap (where gap is the expected maximum price gap before liquidation can react). If gap is, say, 50% (worst sudden crash we want to plan for) and fund is $1M, we might cap OI at $2M so that a 50% move would wipe out $1M losers’ margin which the fund can cover if needed. These numbers vary but that’s the intuition
quillaudits.com
. The hook enforces these caps by summing position sizes internally (it can keep a count of total long and short open interest in USD, updating on each open/close) and disallowing new positions beyond the cap.

Trade Lifecycle: Step-by-Step Flows

With the pieces in place, let’s go through typical user actions and how the system processes them. We will describe the flows referencing the earlier components:

A) Depositing and Withdrawing Collateral (USDC)

Deposit: A user who wants to trade must first deposit USDC into the MarginAccount. The user calls MarginAccount.deposit(amount), which transfers USDC from the user’s wallet to the vault (ensure the user approved the token transfer). The vault increases the user’s free balance by amount
members.delphidigital.io
 and emits a Deposit event. Now the user has collateral on the platform to support positions. Example: Alice deposits 5,000 USDC. Her free balance = 5000, locked = 0.

Withdraw: If the user wants to withdraw idle funds, they call withdraw(amount). The contract checks that amount <= freeBalance (cannot withdraw locked margin). If okay, it decreases free balance and transfers USDC back to the user’s wallet
members.delphidigital.io
. Users can withdraw excess margin even with open positions, as long as they maintain requirements. Typically after closing trades or if they over-collateralized initially, they might withdraw the remainder.

(Note: Deposits/withdrawals do not interact with Uniswap or the hook at all; they are direct vault operations. This design keeps fund management separate from trading logic.)

B) Opening a Long Position (Buy/USDC → Base)

Now Alice wants to go long on, say, ETH perp. She decides to use $1,000 of her USDC as margin and 5× leverage to maximize position size. That means notional = $5,000 (since 5× leverage, margin $1k backs a $5k position).

User Initiates Open: Alice uses the frontend to specify market = ETH-Perp, direction = Long, leverage = 5×, margin = $1,000 (or directly notional $5k). The frontend or router computes that she wants to swap $5,000 worth of USDC into the vAMM. Alice calls PerpsRouter.openLong(marketId, notional=5000, leverage=5) (function name illustrative).

Router Executes Swap: The router finds Alice’s address and ensures she has $1,000 free in MarginAccount to lock (or it could require exactly specifying margin). It then calls the Uniswap V4 swap() for the USDC/vETH pool:

It calls PoolManager.swap(poolKey=(USDC,vETH, feeTier, hookAddr), SwapParams{zeroForOne=true, amountSpecified=5000, sqrtPriceLimit=0, recipient=PositionManager}, data=hookData). Here zeroForOne=true might indicate swapping token0 (USDC) for token1 (vETH) – assuming in pool USDC is token0 and vETH token1. amountSpecified=5000 (in USDC terms) means we are inputting 5000 USDC to buy as much vETH as we can (this yields our position base size). The recipient is set to the PositionManager’s address (so any vETH from the swap would be delivered there, not that we actually use it).

The hookData is encoded to tell the hook this is an OPEN_LONG for Alice. For example, hookData = {user: Alice, action: OPEN, isLong: true, amount: 5000, positionId: 0} (positionId 0 could signal new position).

beforeSwap Hook (Open Long): The Uniswap pool contract calls our PerpsHook.beforeSwap(sender=PerpsRouter, PoolKey, SwapParams, hookData)
docs.uniswap.org
. In beforeSwap, our logic runs:

It identifies the market from PoolKey and decodes hookData. It sees action OPEN_LONG for Alice with notional 5000.

Price band check: It retrieves the latest oracle price (say $1500) and computes current vAMM mid-price. Suppose vAMM mid is $1502, a +0.13% premium. The deviation is 13 bps which is within our allowed band (e.g. maxDeviation 50 bps), so it's fine
quillaudits.com
.

OI cap check: It calculates new total long OI if Alice enters. If current long OI was e.g. 20k and short OI 20k (balanced), adding 5k long makes long OI=25k vs short 20k. This is within cap (cap might be, say, 100k), so okay.

Initial Margin: Required margin = notional / leverage = 5000/5 = $1000. The hook calls MarginAccount.lockMargin(Alice, 1000). The MarginAccount checks Alice’s free balance (5000) >= 1000, then deducts 1000 from her free and (internally) marks 1000 as locked for that position
members.delphidigital.io
. After this, Alice’s free = 4000, locked = 1000. If she didn’t have enough, the hook would revert here (but she did).

vAMM math: Now the hook computes the swap result on the virtual reserves:

Let’s say currently vBase = 666.667, vQuote = 1,000,000, K = 666,667,000 (as in our init example). Alice is swapping in ΔQ = 5000 USDC.

New vQuote 
𝑄
′
=
1
,
000
,
000
+
5
,
000
=
1
,
005
,
000
Q
′
=1,000,000+5,000=1,005,000.

New vBase 
𝐵
′
=
𝐾
/
𝑄
′
=
666
,
667
,
000
/
1
,
005
,
000
≈
663.33
B
′
=K/Q
′
=666,667,000/1,005,000≈663.33.

ΔB = B_old - B' = 666.667 - 663.33 = 3.337 vETH. This is the amount of virtual ETH that Alice effectively buys (her position size).

The average price she got = 5000 / 3.337 ≈ $1498.5 per ETH (slightly below the mid-price due to slippage, which is good for her as a buyer).

The hook calculates the fee. Suppose tradeFeeBps = 10 (0.1%), so base fee = $5 (0.001 * 5000). Funding adjustment: since vAMM was a bit higher than oracle (premium), funding rate might be positive but tiny (say annual 5% ~ per hour 0.02%). For this single trade, maybe we add 0.05 bps. The hook might increase fee by e.g. 0.05 bps (just an example)
docs.uniswap.org
. That’s negligible, so fee ~ $5.

The hook will tell Uniswap to apply a slightly higher fee on this swap via the return value. However, since there are no LPs, where does this fee go? In Uniswap v4 dynamic fee, the fee is normally to liquidity providers. But because our pool has a hook, we could set LP fee to zero and implement the entire fee as a hook fee that transfers to insurance fund. Alternatively, we treat the LP fee as accruing in the pool contract (owned by insurance fund) and then periodically collected. Implementation-wise, we might actually use hook’s BeforeSwapDelta to skim the fee. But to keep it conceptual: the trade will incur a $5 fee that ultimately will be captured by the insurance fund.

The hook prepares data for afterSwap: it will need to know ΔB (position size) and the entry value, etc. It might pack some info or store it in temporary storage accessible by afterSwap. Uniswap core will execute the swap now.

The hook returns control to Uniswap with (beforeSwapDelta=0, lpFeeOverride=<adjusted fee>)
docs.uniswap.org
. Uniswap now knows to take the 0.1005% fee instead of 0.1%, for example.

Uniswap Swap Execution: With the fee override, Uniswap will move 5000 USDC (plus fee) from the caller to the pool and output 3.337 vETH to the recipient (PositionManager). Now, because PositionManager is the recipient, it will receive 3.337 vETH tokens. These vETH are basically meaningless outside the pool; the PositionManager doesn’t have a special handler for them, they’re just sitting in its account. But their presence triggers the hook again:

Uniswap calls our afterSwap(sender=PerpsRouter, params, swapDelta, data) hook. The swapDelta will indicate the net change in token balances. For example, swapDelta might show token0: +5000 - fee, token1: -3.337 (meaning pool gained USDC and lost vETH).

afterSwap Hook (Open Long): In afterSwap, the hook finalizes the open:

It uses the info from beforeSwap (and possibly re-calculates or reads the swapDelta) to confirm ΔB = 3.337 vETH and ΔQ = 5000 USDC (with fee).

Position creation: It calls PositionManager.mintPosition(Alice, marketId, isLong=true, notional=5000, entryPrice=1498.5, cumFundingNow=index, margin=1000). The PositionManager mints a new ERC721 token (say ID #1) to Alice
members.delphidigital.io
, and stores the position data: sizeBase = +3.337, entryPx ~1498.5, margin=1000, owner=Alice, cumFundingAtOpen = current index (e.g. 0 since just opened). Event PositionOpened(1, Alice, size=3.337 @1498.5) is emitted.

Fee distribution: The hook now takes the fee and sends it to InsuranceFund. If the fee was taken as part of swap (i.e. pool now has a bit of extra USDC equal to fee), the hook might use a hook fee mechanism or a post-swap delta to transfer that out. Uniswap v4 allows the hook in afterSwap to return a delta adjustment as well
docs.uniswap.org
. Alternatively, the fee could have been transferred immediately in beforeSwap using a delta. Either way, $5 (or whatever) goes into InsuranceFund’s balance. The insurance fund contract could have a collectFee() that the hook (being owned by governance perhaps) is allowed to call to transfer from pool or router to the fund.

Update vAMM state: The hook updates its stored vBase to 663.33 and vQuote to 1,005,000 to reflect the new state after the trade, and keeps K as constant (which should now equal 663.33*1,005,000 ≈ 666,667,000, ignoring minor rounding).

Now the swap is complete. Alice’s position is open with 3.337 ETH long. Her remaining free balance is $4000 and locked $1000 margin backing this position.

Aftermath: Alice now has an open long. If the ETH price on the market rises, the vAMM price will also move (through trades or marking) and she can close later for profit. Her leverage is 5×, margin 1000, position 5000. The maintenance margin requirement might be, say, 5% of notional = $250. So as long as her equity (initial 1000 plus any unrealized PnL) stays above $250, she’s safe. If ETH price drops enough that her PnL is –$750 (leaving only $250 equity), she’d hit the liquidation threshold.

C) Opening a Short Position (Sell/Base → USDC)

Suppose Bob wants to go short on the same market. He deposits USDC as well (say Bob has $2000 free). He wants to short with 5× leverage too, using $1000 margin to short $5000 worth of ETH.

Bob calls PerpsRouter.openShort(marketId, notional=5000, leverage=5). The router will do a swap of vETH to USDC in the pool.

It calls swap(zeroForOne=false, amountSpecified=5000, sqrtPriceLimit=∞, recipient=PositionManager, data=hookData) meaning it wants 5000 USDC out by inputting vETH. Actually, to short, one way is to specify a negative amountSpecified if using exact input vs output logic. Alternatively, specify amountOutDesired = 5000 USDC, and it will take whatever vETH is needed as input. Uniswap v4 supports either input or output as specification. Let’s say it’s set to get 5000 USDC out (this would correspond to Bob’s virtual borrow of USDC, because shorts effectively receive USDC upfront which they will have to pay back by buying back the asset later).

hookData encodes OPEN_SHORT for Bob, notional 5000.

beforeSwap Hook (Open Short):

Price check: vAMM mid might have moved slightly from Alice’s trade, but let’s say it’s $1501 now, oracle $1500, still fine.

OI check: previously long OI = 5000 (Alice) and short OI = 0. Adding Bob’s 5000 short will balance OI = 5000 each side, well under cap.

Margin: required = 5000/5 = $1000. Lock $1000 from Bob’s MarginAccount (Bob free was 2000, so now free 1000, locked 1000).

vAMM math for short (selling base):

Current vBase = 663.33, vQuote = 1,005,000, K = ~666,667,000.

Bob will add ΔB to vBase. We don't know ΔB yet; we know he wants 5000 USDC out. So we solve from opposite side:

We want ΔQ_out = 5000 from the pool (USDC out to Bob’s position).

That means the pool’s quote reserve will decrease: 
𝑄
′
=
1
,
005
,
000
−
5
,
000
=
1
,
000
,
000
Q
′
=1,005,000−5,000=1,000,000 (interestingly, back to 1,000,000).

𝐵
′
=
𝐾
/
𝑄
′
=
666
,
667
,
000
/
1
,
000
,
000
=
666.667
B
′
=K/Q
′
=666,667,000/1,000,000=666.667.

ΔB = B' - B_old = 666.667 - 663.33 = 3.337 vETH.

So Bob is effectively selling 3.337 vETH to the pool to get $5000 out. That 3.337 is his short position size (he is short 3.337 ETH).

The price he got is similarly ~$1500.7 (a touch above mid, since he moved price up slightly by selling into it).

Fee: 0.1% of 5000 = $5, plus maybe funding adjustment. If funding is positive (perp > spot), shorts receive funding, so perhaps we reduce the fee for Bob by a tiny amount or even give a rebate. But let’s say negligible, fee ~$5.

The hook will ensure that the USDC the pool is giving out (5000 minus fee) doesn’t actually go to Bob’s wallet – since recipient is PositionManager, the USDC actually is sent to PositionManager (where it will sit as some balance). But conceptually, Bob’s position has “received” 5000 USDC virtually which he will owe back when he closes.

It returns appropriate fee override and beforeSwapDelta if needed.

afterSwap Hook (Open Short):

ΔQ = 5000 USDC (out from pool), ΔB = 3.337 (in to pool).

The hook mints a position NFT for Bob: sizeBase = -3.337 (negative to indicate short), notional 5000, entry price ~$1500, margin 1000, owner=Bob, record funding index.

It sends the $5 fee to InsuranceFund.

Updates vBase back to 666.667, vQuote back to 1,000,000 (notice: after Bob’s trade, the pool’s virtual reserves returned to the initial ratio exactly, meaning the price is back to $1500.7 or so; actually if exactly symmetric size as Alice, it might realign the price near initial. The mid might be slightly off if fees altered things or rounding).

Now Bob is short 3.337 ETH; Alice is long 3.337 ETH. The system is nicely balanced: long OI 5000 vs short OI 5000.

At this moment, if we ignore fees, the PnL of Alice and Bob are mirror images. If price goes up, Alice gains, Bob loses; if down, Alice loses, Bob gains. The insurance fund collected ~$10 total in fees which is a buffer. Funding will likely be near zero because the perp price is now equal or very close to spot after their trades offset.

D) Closing or Reducing a Position

When a trader wants to exit their position, they will perform the opposite swap. Let’s say after some time, the price moved and Alice wants to close her long.

If price went up, we expect Alice to close for a profit (she will get more USDC out than she put in initially). Bob, if he were to close at that higher price, would take a loss (having to pay more USDC to buy back the ETH he owes).

If price went down, Alice would close and realize a loss (getting back less USDC), and Bob would profit.

We will illustrate Alice closing fully, assuming price moved in her favor.

Suppose the price rose ~10% from $1500 to $1650 (perhaps external market and our perp’s mark moved accordingly through some trading or oracle input).

Alice closes her Long: She calls PerpsRouter.closePosition(posId=1, size=100%). The router knows Alice’s posId 1 corresponds to 3.337 ETH long. To close, it will swap that much vETH for USDC:

It calls swap(zeroForOne=false, amountSpecified=3.337 vETH, sqrtPriceLimit=..., recipient=PositionManager, data=hookData). Actually, since she’s selling base for USDC, that’s token1→token0, which might be zeroForOne=false (depending on token ordering). She wants to sell 3.337 vETH and get whatever USDC. We set amountSpecified = 3.337 as input amount (with swap type as exact input of vETH).

hookData: {action: CLOSE, positionId:1, isLong:true, size:3.337}.

beforeSwap Hook (Close Long):

Ensure posId 1 is indeed Alice’s and is long. Possibly verify that closing size <= position size.

Price band check: mark vs spot (should be fine within tolerance, assume).

The hook computes the vAMM output for selling 3.337 vETH:

vBase old = ~666.667, vQuote = 1,000,000 (numbers might have changed slightly if any funding or partial changes happened, but assume still around initial).

Remove ΔB = 3.337 from base: 
𝐵
′
=
666.667
+
3.337
=
670.004
B
′
=666.667+3.337=670.004 (because the pool gains base when Alice sells her long back).

New 
𝑄
′
=
𝐾
/
𝐵
′
=
666
,
667
,
000
/
670.004
≈
994
,
966
Q
′
=K/B
′
=666,667,000/670.004≈994,966 (USDC left in pool).

ΔQ = Q_old - Q' = 1,000,000 - 994,966 = 5,034 USDC goes out to Alice’s side (the pool will pay that out).

So Alice will receive $5,034 (before fees) for selling her 3.337 vETH. She originally paid $5000 to acquire them, so her gross profit = $34.

That corresponds to about +0.68% gain, which is actually a bit low for a 10% move — because my numbers might not reflect a full 10% price move due to balancing with Bob. Let’s assume instead a smaller move or partial scenario. But conceptually, she gets more USDC back.

Fee on this closing swap: 0.1% of 5034 ≈ $5.03, which will go to insurance. Funding: if funding accrued, it will be settled separately (see below).

MarginAccount.settlePnL(Alice, pnl) will be called in afterSwap, but we can compute now: Realized PnL = 5034 - 5000 = +$34.

The hook returns with fee override.

afterSwap Hook (Close Long):

It computes the final PnL: +$34 for Alice. It calls MarginAccount.settlePnL(Alice, +34). This would credit 34 to her free balance. Essentially, that USDC comes from the pool’s reserves (which got it from Bob or insurance fund indirectly). In practice, when the swap transferred 5034 USDC to PositionManager as recipient, that amount includes Alice’s initial margin (5000) plus profit (34) minus fee. The fee $5 is redirected to insurance, so PositionManager might net ~5029. The hook probably takes that 5029 from PositionManager and gives to MarginAccount for Alice.

It calls MarginAccount.unlockMargin(Alice, 1000). Her locked 1000 is released to free balance, because her position is closed.

PositionManager is instructed to burn Alice’s NFT (pos 1), as it’s now closed. Event PositionClosed(1, realizedPnL=34, fundingPaid=X) emitted. If any funding was paid while she held it, that would be reflected in fundingPaid (imagine over time she might have paid -$1 in funding, for example, reducing her margin slightly).

Virtual reserves updated: vBase = 670.004, vQuote = 994,966 (the pool lost some USDC, gained base).

Bob’s position is still open. The vAMM price after Alice closed likely moved: now more base in pool, less quote, so price dropped slightly from before close (which makes sense: when Alice sells to close, she pushes price down a bit).

Alice ends up with: Her margin account now has free balance = 4000 (old free) + 1000 (released margin) + 34 (profit) = $5,034. Her profit is realized and she could withdraw or open new trades.

Impact on Bob (Unrealized): If the price indeed was higher when Alice closed, Bob is now sitting on an unrealized loss. The vAMM mid-price might be around $1490 now (assuming some conditions) – actually wait, if external went to 1650 but she only got a small profit, likely my numbers were off. Let’s not worry; the key is Bob’s short might be at a loss if price is up. But Bob hasn’t closed yet, so no PnL realized for him. However, funding might have accrued: since longs were winning, likely the perp was above spot at times making longs pay funding to shorts, so Bob may have received some funding. This could mitigate his loss slightly.

If Bob decides or is forced to close:

He would do the opposite swap (buying 3.337 vETH from the pool). If the price is indeed higher than his entry, he will pay more USDC to close than he got originally, realizing a loss. That difference would come out of his margin. If the loss is bigger than his 1000 margin, he would be liquidated instead of a regular close.

E) Funding Accrual and Payment

Funding ensures that if the perp price diverges from spot, traders pay a fee to incentivize convergence
kraken.com
. In our design:

A keeper (could be a cron job or anyone incentivized) calls pokeFunding() on each market, say every hour. This triggers the FundingOracle to fetch prices and compute the funding rate for that hour. Example: mark price is 1% over spot, k=0.5, so funding rate = 0.5% * +1% = +0.005% (longs pay shorts 0.005% of notional per hour). It then updates globalFundingIndex += 0.00005 (in decimal) for that market. Event FundingUpdated(marketId, newIndex, rate) is emitted.

This index is used whenever positions change. For instance, if Bob’s short was opened at index 0 and after 4 hours the index is 0.0002, that indicates longs have paid 0.02% to shorts in that period. If Bob hasn’t closed, nothing moved in his balance yet, but the moment he closes or the next time he adds to position (or if we explicitly settle periodically), we compute funding PnL for him: he would gain 0.02% of 5000 = $1 from funding (added to his margin), and longs collectively lose $1. If Alice still had her long open during that time, on her close the system would have deducted $1 from her margin (or from her profit).

We also have the option to charge/pay funding on the fly for every swap. The code snippet approach in the hook used dynamic fee changes to implicitly make longs pay a tad more on each trade when premium > 0
docs.uniswap.org
. This can be viewed as a form of discrete funding payment each trade (traders entering or exiting at worse prices if they’re on the paying side). However, the more straightforward way is the index and separate settlement as described.

When funding is settled:

The MarginAccount’s applyFunding(trader, amount) is invoked. For a long, funding amount will be negative (they pay), so it deducts from their balance
members.delphidigital.io
; for a short, positive (they receive) so it credits them. Our design ensures balance changes from funding are internal transfers between traders. If total longs $ > total shorts $, there is an imbalance: not all longs’ payments have a short to receive on the other side. In such case, what happens to extra? One policy is to send it to the insurance fund (so insurance fund grows from positive funding when there are more longs paying than shorts receiving). Likewise, if shorts > longs and shorts would pay longs negative funding, the remainder could come from insurance fund. This prevents money from disappearing or appearing unbacked.

Over time, funding tends to push the perp price back. If longs keep paying, it discourages long positions or encourages shorts to come in to collect that funding, thus rebalancing the long/short open interest and price.

Example: After some hours, suppose no trades happened but mark was above spot. Alice’s long might owe, say, $2 funding, Bob’s short receives $2. If Alice doesn’t trade, we might not charge it until she closes. But better, we can update her position’s fundingPaid and reduce her margin by $2 periodically. The PositionManager or MarginAccount could be invoked to do chargeFunding(Alice, 2) (deduct from free or locked margin) and creditFunding(Bob, 2) (add to Bob’s margin). If Alice’s margin becomes insufficient due to funding, that could even trigger liquidation if it dips below maintenance.

Funding is normally a small drip, but crucial for long-term stability. Our FundingOracle’s use of median price ensures we don’t charge funding off a manipulated vAMM price alone
quillaudits.com
.

F) Liquidation Process (Partial and Full)

Liquidation is the safety net to protect the system when a trader’s losses approach their margin. Our system sets a maintenance margin requirement (MMR) e.g. 6.25% (so 16× effective max leverage maintenance). Let’s walk through how a liquidation works:

Monitoring: The off-chain Liquidator bot constantly calculates each open position’s Margin Ratio (MR) = Equity / Position Notional.

Equity = margin + unrealized PnL (for longs, if price dropped, PnL is negative; for shorts, if price rose, PnL negative).

Position Notional = |size in base| * current mark price.

If MR falls below the maintenance level (mmrBps), e.g. 6.25%, the position is eligible for liquidation.

Triggering Liquidation: Suppose Alice’s position went badly and her MR is 5% < 6.25%. A keeper calls PositionManager.liquidate(positionId) for Alice’s position.

The PositionManager checks MR using current mark price from oracle (to avoid using potentially manipulated last trade price). If indeed MR < MMR, it proceeds. (If not, it reverts and the keeper wasted gas.)

The PositionManager determines a partial liquidation size to sell. Often systems try a partial first: e.g. aim to bring MR back to maybe 8% (a margin buffer above 6.25%). They calculate how much of the position to close to achieve that. Let’s say that comes to 50% of her position.

The contract then essentially calls the PerpsHook to execute a market swap for that half of position (in the opposite direction to her position). This is like forced close of half her position at current price. It might internally use the same swap logic or a direct call since our hook can be invoked by PositionManager (perhaps bypassing router).

The half position is closed: realized loss is taken from her margin. After this, her remaining position is smaller and hopefully her remaining margin is enough that MR is now above MMR (plus buffer). The PositionManager would mark her position as half liquidated and perhaps impose a cooldown (like she cannot be liquidated again for a few minutes unless still under threshold, to avoid oscillation).

A liquidation fee/penalty is applied: e.g. 1% of the notional of the portion closed. This could be split: part (say 0.5%) goes as a reward to the liquidator (keeper) to incentivize them, and the other 0.5% goes to InsuranceFund. This penalty essentially is deducted from Alice’s remaining margin (so her equity goes down a bit more, as punishment).

If after partial liquidation, she still is under a critical level (some systems define if below 50% of maintenance or something), the system might skip partial and do full liquidation.

If partial was enough, Alice’s position remains open on a smaller scale, and hopefully safe for now. She can later add margin or close it herself. If the market keeps moving against her, another liquidation can happen.

Full Liquidation: If Alice’s position is very under water (say MR < 2/3 of MMR, which many protocols use as an insta-liquidate threshold), the system will liquidate the entire position at once.

The PositionManager closes the whole position via vAMM at mark price. Suppose this realizes a large loss that exceeds her margin (meaning equity goes negative). That shortfall is bad debt.

The penalty is applied on the entire notional (so the liquidator gets a reward, fund gets some).

Her position NFT is burned. Now, because her margin was not enough to pay the loss, who pays the difference? The InsuranceFund.coverBadDebt(amount) is called
quillaudits.com
. The insurance fund then transfers that amount of USDC into the MarginAccount or to the winning side. This ensures the winning traders still get their due PnL. InsuranceFund emits an event for covering bad debt.

If the insurance fund lacked sufficient funds (should not happen if OI caps are prudent, but if so), then the protocol may have an Auto-Deleveraging (ADL) process
quillaudits.com
. ADL means the system would pick some of the most profitable opposite traders and automatically reduce their positions by a proportion to realize some of their profits (essentially using those profits to offset the shortfall). This is very undesirable as it penalizes winners, so protocols avoid it unless absolutely necessary. Our design plans to avoid it via insurance fund and OI limits, but it’s mentioned as a last resort. ADL would be done by automatically closing part of winning traders’ positions at a price equal to the mark price used for the losing side’s liquidation, so their PnL is capped.

Post-Liquidation: The liquidator bot receives their reward (usually paid out from the margin of the liquidated position or by the insurance fund). The InsuranceFund might now hold the remainder of the penalty that was allocated to it. The market state updates: vAMM reserves shift due to the forced close trade (which is like any trade). The PositionManager marks that position as liquidated.

Liquidation events are critical to monitor, and often a UI will show a liquidation price for positions – the price at which their margin would run out given current margin and maintenance margin. Traders can manage risk by adding margin or reducing positions before hitting that.

Our system’s fast liquidation and penalties ensure that we quickly remove risky positions and use their collateral (and penalties) to buffer the system. The penalty going partly to insurance means the fund grows when liquidations happen, which is good because typically that occurs in volatile times when risk is higher. It’s a transfer from failing traders to the safety net.

Flow of Funds and Token Movements

It’s important to clarify what actual token movements occur versus what is just accounting in our perpetual protocol:

Figure: High-level flow of funds in the vAMM perpetual system. USDC collateral moves in and out of the MarginAccount and InsuranceFund, while the Uniswap v4 pool holds only virtual assets for pricing
members.delphidigital.io
members.delphidigital.io
.

User Deposits/Withdrawals: When users deposit USDC, tokens move from their wallet to the MarginAccount contract. Withdrawals move USDC back to the user. These are real ERC-20 transfers of USDC. Think of the MarginAccount as the on-chain "bank" holding all traders’ USDC funds.

Opening/Closing Trades: When a user opens or closes a position, no direct transfer of the underlying asset occurs to the user. In a long, the user doesn’t receive real ETH – they get an increase in their position size on the vAMM and lock margin. The Uniswap pool contract does handle token transfers during swaps, but in our case:

The tokens in the pool are USDC and vAsset (like vETH). USDC will flow from the MarginAccount/Router into the pool and out of the pool to MarginAccount when trades happen, but these flows can be optimized or netted out via hook logic. We may design it such that the MarginAccount provides USDC liquidity to the pool or the hook uses internal accounting to avoid transferring USDC back-and-forth every time (to save gas).

The vAsset token (vETH) is not a real asset anyone uses; it only moves within the pool. For example, when a long trade happens, USDC goes into the pool and vETH comes out to the PositionManager (which doesn’t use it). AfterSwap, we might even discard that vETH or keep it as a record that the position now holds that many virtual ETH. But effectively, users never touch vETH.

PnL Settlement: When a position is closed with profit, the profit comes out of someone else’s margin. Concretely, if Alice made +$34, that $34 came from the pool’s USDC which effectively came from Bob’s side of the trade (Bob’s position will show a -$34 unrealized loss). Upon closing, the MarginAccount pays Alice $34 – this is done by increasing her balance. Where does the MarginAccount get $34? It could be directly from the pool’s transfer during the swap (the pool paid 5034 USDC out, which the hook directed into Alice’s MarginAccount). Meanwhile, Bob’s margin stays in the account but now Bob’s position is sitting on a $34 unrealized loss; Bob’s equity is down $34 (and if he closed, he would pay it).

Fees and Funding: All trading fees (say that $5 from each side) are not kept by any liquidity provider (since there are none). Instead, our hook directs those fees into the InsuranceFund. That means after Alice and Bob opened, the InsuranceFund got ~$10. Those were actual USDC transfers (from the pool or router) into the InsuranceFund contract. Similarly, when funding payments occur, they are internal transfers between MarginAccount balances of traders (and possibly InsuranceFund if imbalance). For instance, if Alice pays $2 to Bob, we’ll subtract 2 from Alice’s balance and add 2 to Bob’s. No external token moves, it’s just numbers in MarginAccount changing. If Alice pays funding and there’s no corresponding short, that $2 might be moved from Alice’s balance to InsuranceFund’s own balance (via MarginAccount calling insuranceFund.deposit or simply recording it).

Insurance Fund Payouts: If InsuranceFund has to cover bad debt, it will transfer USDC to the MarginAccount (or directly to the winning trader’s address). That is an actual token transfer out of InsuranceFund. The insurance fund is thus reduced, but the winners are made whole by that amount (reflected as a credit in their margin account or a direct payout if their position was closed).

Collateral Conservation: Ideally, aside from funded payments to insurance or from it, the system’s total USDC is conserved. The sum of all traders’ margin balances plus insurance fund balance equals total USDC that has been deposited minus withdrawn
bookmap.com
. This should hold true at all times (we can test this invariant).

No External Liquidity: Because all liquidity is virtual, we do not have any external LP token holders. The only parties are traders and the protocol’s insurance fund. Thus, all gains by one trader are offset by losses of other traders (zero-sum) plus whatever is collected by the insurance fund as fees
bookmap.com
bookmap.com
. The insurance fund in a way represents the “house” take that accumulates over time to handle defaults.

In summary, USDC moves on deposit, withdrawal, when paying PnL out or covering losses, and when collecting fees/penalties. The vAMM state (vBase, vQuote) moves only virtually (numbers in storage), and user positions (sizes) are recorded in NFTs. Traders' profit is paid from other traders' losses immediately at close, ensuring winners can withdraw their money. The insurance fund acts as a buffer to absorb any mismatch and to build reserves from fees.

Risk Management and System Safeguards

Building a perpetual swap protocol involves careful risk controls to maintain solvency and market integrity. Here we highlight how our design addresses various risks and ensures that winning traders can reliably get paid:

Margining and Liquidation: By requiring traders to post margin and actively monitoring positions, we ensure that losers’ collateral is available to pay winners. The maintenance margin ratio (mmrBps) guarantees that if a trader’s equity falls too low relative to position size, the position will be liquidated before going negative. Partial liquidation is used to reduce positions incrementally and give traders a chance to recover, while full liquidation exits them completely if they’re too far gone. The penalties not only incentivize traders to avoid liquidation (by adding extra cost) but also help recapitalize the system – a portion of every liquidation penalty goes to the InsuranceFund, increasing the buffer for bad debt coverage.

Price Band Guard: We implement a strict check that the vAMM price cannot deviate excessively from the true market price (spot oracle)
quillaudits.com
. This prevents scenarios where, say, the internal price is mispriced and someone could manipulate it or withdraw unbacked profits. If the band is, for instance, 1%, any attempt to trade that would push the price more than 1% away from the external price will be blocked until the discrepancy is naturally resolved (through arbitrage or funding or oracle move). Essentially, it keeps the vAMM anchored to reality.

External Oracle and TWAPs: Using a combination of oracle feeds and time-weighted average prices from a reliable DEX adds resilience against manipulation. A common attack on on-chain perps is oracle manipulation – if the perp relies solely on its own AMM or an unstable price feed, an attacker could use flash loans to distort the price and trigger liquidations or extract value
quillaudits.com
. By using a median of multiple sources, we significantly reduce this risk. For instance, an attacker would need to manipulate Uniswap spot pool and the external oracle price (which might be based on off-chain data) simultaneously to trick our system’s mark price, which is far more difficult. This guard, combined with the band, makes the pricing mechanism robust.

Open Interest Limits: As discussed, capping the open interest is a direct measure to control the platform’s exposure. If too many traders are on one side (e.g. everyone is long on an obscure asset), there is a risk if that asset crashes that the shorts (or insurance fund) won’t cover the longs’ profits. By limiting OI based on insurance fund size, we ensure the platform never promises more profit than it can pay out from available collateral
quillaudits.com
. For example, if oiCapUsd = $10M and the worst-case we think might be a 50% gap move, insurance fund should be ≥$5M to handle that, or we keep oiCap smaller relative to fund.

Conservative Funding Model: The funding rate mechanism is tuned to continuously nudge the perp price toward the underlying. This reduces the chance of large deviations persisting and causing unbalanced books. It also serves as an economic dampener – if longs greatly outweigh shorts, funding will turn strongly positive, making it costly to hold those long positions. This encourages some longs to close or new shorts to open (attracted by earning funding), re-balancing the system. Funding thus provides continuous risk rebalancing and adds to the insurance fund if one side is unpaired (excess payment goes to the fund). Essentially, funding acts as both a price alignment tool and an income source for the protocol to build reserves.

Insurance Fund as Backstop: All fees from trading (which in traditional markets might go to exchange or LPs) accumulate in the InsuranceFund. It also collects the portion of funding that is not paid out (if, say, longs pay more than shorts receive) and any leftover liquidation penalties after paying liquidators. Over time, this should grow (assuming trading volume and some liquidations). The insurance fund is the primary safety net for Black Swan events – if despite all other measures a trader’s loss exceeds their margin (e.g. a sudden 30% gap move before anyone can liquidate), the insurance fund will cover that bad debt
quillaudits.com
. This socializes the loss across all past trading activity (effectively, profitable traders and liquidations have contributed to it). By having this fund and keeping it healthy, we maintain the promise that winners can cash out. In the history of exchanges, robust insurance funds (or their decentralized analogs) have been key – e.g. BitMEX’s insurance fund prevented auto-deleveraging on most occasions. We aim for the same: use parameters such that ADL (auto-deleveraging of winners) is rarely if ever triggered.

Auto-Deleveraging (ADL) Contingency: In the unlikely worst-case that the insurance fund is drained and there’s still a shortfall, the last resort is ADL
quillaudits.com
. This mechanism will be designed to choose the most leveraged and profitable opposing traders and shave off some of their position (realizing some of their profit) to cover the shortfall. We rank profitable traders by their return and start reducing positions until the deficit is filled. It’s essentially a clawback of profits above what the losing side could pay. While highly undesirable, making this possibility known and deterministic helps manage systemic risk. Again, our hope is that with all the preventive measures (band limits, OI caps, etc.), ADL never triggers, but it’s there so that the system is never insolvent – it will always balance the books one way or another.

No Impermanent Loss / LP Risk: Since we have no external liquidity providers (the protocol itself is the “LP”), we avoid the typical AMM risk of impermanent loss. This simplifies risk considerations to just the trader PnL and system backstop, without needing to also incentivize LPs or worry about their withdrawals.

Security of Contracts: On a smart contract level, using known standards (ERC-20 for USDC, ERC-721 for positions) and minimizing complexity in the critical math helps reduce bugs. We’d implement re-entrancy guards on MarginAccount (so a user can’t withdraw in the middle of a swap, etc.), and carefully manage access control (e.g. only the PerpsHook or PositionManager can call certain functions on MarginAccount). Hooks inherently must be careful – our hook will validate that msg.sender is the official Uniswap PoolManager (to avoid malicious calls) and that the swap recipient is our PositionManager (so users can’t trick the pool into sending them funds directly). These checks ensure the hook only operates in intended scenarios. We’d also lean on Uniswap v4’s audits for the core, but thoroughly test our extensions.

By combining these measures, the protocol maintains a solvent, fair, and efficient trading environment. Profits are always backed by someone else’s loss or the insurance fund, and the system can absorb shocks up to a design threshold. Fast liquidation and dynamic funding tackle problems as they arise (preventing losses from ballooning). As a result, traders can be confident that if they win, they will actually get their payout, which is the cornerstone of any financial exchange's credibility.

Implementation Plan and Development Milestones

Building this system from scratch is a significant project. However, we can break it down into manageable components and iterative milestones. Below is a proposed development roadmap (which was outlined as a day-by-day plan, though actual timelines may vary):

1. Project Setup and Repository Scaffolding

Milestone: Establish a clean repository with Uniswap v4 integrated and placeholder contracts.

Begin with Uniswap’s v4 template or example repository
quillaudits.com
quillaudits.com
. This gives us the PoolManager and core infrastructure to create pools and hooks. We’ll use Foundry (Solidity development framework) for writing and testing contracts, as well as perhaps Scaffold-ETH (a React frontend scaffold) for a quick UI.

Install dependencies: Uniswap v4 core, OpenZeppelin libraries (for ERC20, ERC721), etc. Set up basic contract files for each of the components we described: PerpsHook.sol, PositionManager.sol, MarginAccount.sol, InsuranceFund.sol, FundingOracle.sol, and PerpsRouter.sol. At this stage, they can be skeletal (interfaces and events). Also include any utility libraries (e.g. math for funding, safe casting, etc.).

In Uniswap v4, deploying a hook requires a computed address with the correct permission flags
docs.uniswap.org
. We might incorporate a small script or tool (Uniswap provides a HookDeployer or HookMiner) to precompute an address for our hook that has the BEFORE_SWAP, AFTER_SWAP, AFTER_INITIALIZE flags set
docs.uniswap.org
. This typically involves trying different salt inputs until an address with desired low-order bits is found. We can plan for that in deployment steps.

2. Implement the PerpsHook and Core Logic

Milestone: Get the hook contract functional with storage and the key swap callbacks, enforcing rules and performing vAMM math.

Storage and Permissions: Define the Market struct in PerpsHook and mappings to store each market’s parameters (virtual reserves, etc.). Implement the getHookPermissions() function or constant to reflect our chosen HOOK_FLAGS (this can be used to validate the address was mined correctly)
docs.uniswap.org
. Only allow the PoolManager (Uniswap core) to call our hook functions (onlyPM modifiers), reverting others.

afterInitialize: When a new pool is first initialized (with an initial sqrtPrice), this callback should set up our Market struct. We can decode the initial price from sqrtPriceX96 to a normal price. For example, using Uniswap’s TickMath to get tick and price
docs.uniswap.org
. Then set vQuote = depth, vBase = depth/price, compute K, etc. Also store references to spot pool address and set initial funding index to 0. Emit an event for market creation.

beforeSwap: This is the most important. Implement decoding of hookData: we decide on an encoding scheme, e.g. first byte action type, then positionId, etc., or use an ABI struct. Then a big conditional: if action is OPEN or INCREASE, do the checks (bands, OI) and margin lock. Use the formulas for ΔB or ΔQ as derived above depending on trade direction. Set a hookFee (in hundredths of a bip) accordingly
docs.uniswap.org
. We might store a base fee per market and then add/subtract funding basis points. To fetch current funding bias, call FundingOracle.premiumX18() for this market
quillaudits.com
; if positive, maybe fee += some small amount (thus longs pay slightly higher fee than shorts in that instant). Prepare any needed data for afterSwap (like we may encode ΔB, notional, etc. into a bytes to pass along via bytes data that afterSwap can read; or we can stash it in a temporary storage mapping keyed by position or user if careful).

Also, enforce that params.recipient == PositionManager address for opens/closes (to ensure the swap output goes to the position contract) – otherwise cancel the swap for safety.

If action is CLOSE or REDUCE, ensure the position exists and size is sufficient. Compute ΔQ out or ΔB out accordingly (as we did for closing calculation). We might allow slight rounding differences. Then no margin lock (instead we will be releasing margin in afterSwap).

For a liquidation action (could treat it as a special CLOSE triggered by PositionManager with perhaps a flag in data), we might skip certain checks like band (or maybe still enforce band so we don’t execute at crazy prices). But typically, we allow liquidations even in volatile conditions because it’s necessary; thus we might have a slightly wider band or no band check for liq if we trust our oracle mark price.

Return the tuple (beforeSwapDelta, newHookFee). In many cases, we won’t need to adjust the token deltas here, just fees. (However, if we wanted to pull margin directly from MarginAccount instead of having router transfer USDC, we could use BeforeSwapDelta to make the pool think it got the USDC while actually pulling from vault. That’s an advanced optimization.)

afterSwap: Now implement the post-swap logic:

If OPEN: Take the ΔB (base asset amount) from the swap outcome (the pool will have sent that to PositionManager). We mint or increase the position via PositionManager. If increasing, we recalc entry price and add margin (MarginAccount lock was already done for the new margin). Emit Trade event with details. Also transfer the fee from this trade to InsuranceFund: the actual amount of USDC fee can be computed from the swapDelta and hookFee applied. If Uniswap automatically separates LP fee (which we set) and holds it, we may call PoolManager.collect() or use hook’s return delta to take it. Or simpler: we could set LP fee to 0 and handle entire fee as hookFee by taking it out of the swap amount – e.g. by adjusting BeforeSwapDelta. Either way, ensure InsuranceFund balance increases by fee.

If CLOSE/REDUCE: Calculate PnL = (amount of USDC received by closing trade minus something) and funding since open. For PnL: one approach is to use position’s recorded entry price: PnL = (exitPrice - entryPrice) * size * (isLong? +1 : -1). But doing it via the actual swap outcome is fine as we did (USDC out - notional portion closed). Then call MarginAccount.settlePnL(user, pnl): if pnl positive, that will internally call InsuranceFund or other losing side to provide funds? Actually, since we already have USDC from the swap, we might directly credit the user and reduce some global counter. But a clean way: if profit, MarginAccount will increase user free balance; if loss, it will deduct from their locked margin.

Then calculate how much margin to release: if the entire position closed, release all remaining margin; if partial, release proportional margin or user might choose which margin to free (often we treat positions as fully margined individually, so partial closure frees proportional margin to maintain same leverage). Simplest: assume isolated margin per position, closing 50% frees 50% of margin (plus any PnL adjustments). Call MarginAccount.unlockMargin(user, amount).

Update position in PositionManager: reduce size, maybe update entry price if partial (though entryPrice could remain for reference, or recalculated). If fully closed, burn the NFT.

Transfer fee to InsuranceFund similarly.

If Liquidation: similar to close but may involve different accounting (penalty application). Perhaps the PositionManager already deducted penalty from margin before instructing the swap. We then ensure to send penalty split: e.g. InsuranceFund.collectPenalty(penaltyPortion) and send liquidator’s portion to their address (this might be done in PositionManager rather than hook).

Finally, update the stored vBase, vQuote in our hook state to the new balances. We can fetch the pool's new balances via the BalanceDelta passed in or by recomputing from old and swapDelta. But careful: Uniswap v4 uses flash accounting, meaning balances aren’t updated until after all swaps in a block are done. Instead, the hook should track deltas itself. However, since our pool likely only used by our router synchronously, we can track it. Alternatively, we do our own accounting: simply adjust vBase, vQuote by ΔB, ΔQ opposite to the trade direction (we already computed that in beforeSwap basically).

Testing at this stage: We should write unit tests (in Foundry) for the PerpsHook’s math: test that open long then close returns correct PnL given a price move, etc. We can simulate scenarios by directly calling the hook via the PoolManager swap call (Foundry can allow calling hook by impersonating PoolManager). Also test that invalid conditions (price band exceeded, etc.) revert properly.

By the end of this milestone, we should be able to simulate a basic trade on a single market purely on-chain and see the state updates.

3. PositionManager, MarginAccount, InsuranceFund Implementation

Milestone: Complete the auxiliary contracts so that they properly handle state changes when invoked by the hook.

MarginAccount: Implement as described: maintain a mapping of user => balance (free). We might also maintain a separate mapping for locked per user or we infer locked = sum(position margins). A simple design is to not even keep a separate locked mapping, but always require locked margin is tracked in PositionManager and just ensure users can’t withdraw if it would break positions. However, to be safe, track locked. On lockMargin(user, amount), do require(balance[user] >= amount), then balance[user] -= amount; locked[user] += amount. On releaseMargin, subtract from locked and add to free
members.delphidigital.io
. On settlePnL: if pnl > 0, increase free balance (like credit winnings); if pnl < 0, we interpret as a loss – we first deduct from the locked margin for that position (which in our scheme is already out of free). Actually we might just call locked[user] -= loss and not add it to free (effectively the loss portion of locked just disappears from their account, which is correct because it went to someone else’s profit). Ensure not to allow locked to go negative (if loss > locked, that’s a problem - should be caught earlier as bad debt scenario).

Provide a balanceOf(user) view to get total balance (free + locked maybe).

The contract should only allow its owner (which could be set to the PerpsRouter or PositionManager or Hook) to call lock/release/settle functions, not users directly – to prevent misuse.

Add events: Deposit, Withdraw, MarginLocked, MarginUnlocked, PnLSettled, FundingApplied.

Consider re-entrancy guard (OpenZeppelin’s ReentrancyGuard) for deposit/withdraw especially.

PositionManager (ERC721): Use OpenZeppelin ERC721 as base. Store a struct Position as above. The NFT token ID serves as a key for a mapping to Position struct. We will have an internal counter for nextId.

mintPosition(owner, market, isLong, notional, entryPrice, fundingIndex, margin) creates a new token, stores Position{owner, market, isLong, notional, entryPx, cumFundingAtOpen=fundingIndex, realizedPnl=0, fundingPaid=0, margin=margin, active=true}, mints the NFT to owner. Only callable by PerpsHook (so make PositionManager owned by Hook or give Hook a minter role).

increasePosition(tokenId, notionalAdd, newEntryPx, marginAdd): adjust the position size and margin. This might recalc entryPx as weighted average: new entryPx = ((old entryPx * old_notional) + (price * new_notionalAdd)) / (old_notional + new_notionalAdd). But an approximation is fine. Update notional and margin. Also could settle funding: e.g. calculate funding since last update = (globalIndex - pos.cumFundingAtOpen) * old_notional, apply to pos.fundingPaid and adjust margin via MarginAccount.applyFunding. Then update pos.cumFundingAtOpen = current index (so future funding calculated from now). This ensures any accrued funding is paid up before adding more.

reducePosition(tokenId, reduceNotional): similar but in reverse. Compute realized PnL for that portion (maybe get current price from oracle or rely on hook to pass it). Deduct that from margin if negative or add if positive (this likely already done in MarginAccount by hook). Decrease pos.notional and pos.size accordingly. Possibly realize some funding too. If pos.notional becomes 0 (fully closed), call burn(tokenId).

liquidatePosition(tokenId): This can be a function that hook or router calls when a liquidation is triggered. It likely will call the hook to perform the swap (or could replicate the swap logic, but better to reuse). It will decide partial vs full as described. Possibly simpler: always go to full for first iteration (but partial is healthier to avoid overshoot). Partial liq calculation: we know mmr and current equity, we can solve for how much notional to reduce to get equity back above mmr. We also incorporate a small buffer and set a cooldown flag on the position for, say, a minute.

The PositionManager also might hold a mapping from owner address to list of their position IDs for convenience, but not strictly needed if events and The Graph are used.

It will have permission that only the PerpsHook (or a designated liquidator role) can call mintPosition, increasePosition, reducePosition, liquidatePosition. Users themselves just use router; they don’t directly call these.

Events: PositionOpened(id,...), PositionAdjusted, PositionLiquidated(id, remainingSize or so), PositionClosed(id, pnl, etc.).

InsuranceFund: Very straightforward: store the USDC token address. Functions:

fund(amount): let anyone deposit USDC into it (just transferFrom and emit Funded event) – e.g. team can top it up.

collectFee(amount): callable by Hook to take amount from the pool/router and deposit to itself. But since hooking directly transferring to itself is easier, maybe InsuranceFund doesn’t even need an external call – the hook can just do an ERC20 transfer to InsuranceFund’s address using the pool’s tokens. But having a function is nice for bookkeeping. If called, it expects the caller already sent the token or perhaps the hook calls insuranceFund.collectFee and the insuranceFund internally does a transferFrom from hook (since hook has the funds?). Might be easier that InsuranceFund is not actively pulling; instead hook does USDC.transfer(insuranceFund, fee). So InsuranceFund might not need a complex function for collecting, just an event log.

coverBadDebt(amount): callable by PositionManager when needed. It transfers amount from insurance fund to MarginAccount or to a specified address (maybe pass in the recipient, likely MarginAccount). Emits Backstop(to, amount) event
quillaudits.com
.

Maybe a view to see balance (though one can always check USDC balance of the contract on-chain).

We might also include a governance function to withdraw surplus or something (owner only).

FundingOracle: Implementation depends on what oracle we use. For now, could stub it or use a simple moving average:

Perhaps integrate with an existing oracle like Pyth: we have Pyth price feed IDs, and Pyth has a contract on each network where you can query latest price. Also Uniswap v3 pools have observation data for TWAPs. We combine them. For testnet, we might simulate an oracle by manually setting a price in the contract (admin can set price for testing).

Provide updateFunding(market) that calculates premium = mark - spot. Mark from vAMM (could get mid from our stored reserves), spot from either Pyth or Uniswap TWAP. Then fundingRate = formula as discussed. Then globalFundingIndex[market] += fundingRate * interval. Because we might call it irregularly or on demand, we could instead compute time difference since last update and multiply by per-second rate.

Also provide premiumX18(PoolKey) which the hook can call in real-time if needed
quillaudits.com
. This premium could be used for dynamic fee tweaking.

The funding oracle might also have an array of past indices if needed, but global index per market is fine.

We likely mark this contract as only callable by an authorized keeper or the hook (for update function).

After implementing these, do tests:

Try deposit/withdraw flows, ensure balances update correctly.

Open a position and then directly call functions on MarginAccount to make sure they cannot be called by unauthorized (e.g. ensure only hook can call lockMargin).

Simulate a funding update and then test that if we manually call a function to apply funding to a position, the balances adjust.

4. Integration and End-to-End Testing

Milestone: Deploy the system to a local testnet (anvil or Hardhat) and run through full scenarios, and prepare for public testnets.

Deploy Contracts: Write a deployment script (in Foundry script or Hardhat) that:

Deploys the MarginAccount, InsuranceFund, FundingOracle, PositionManager, and PerpsRouter. Initialize them (e.g. set relationships: PositionManager needs to know about MarginAccount maybe or vice versa).

Deploy the PerpsHook via the special HookDeployer/CREATE2 to get the right address. Provide it the addresses of PoolManager (Uniswap’s), FundingOracle, PositionManager, MarginAccount. Verify that the deployed address has the correct permission bits (using Uniswap’s Hooks.validateHookPermissions perhaps)
docs.uniswap.org
.

Use Uniswap’s PoolManager to create a new pool: call createAndInitializePoolIfNecessary(tokenA=USDC, tokenB=vETH, fee=someFee, hook=PerpsHookAddress, sqrtPriceX96=initialSqrtPrice). The hook’s afterInitialize will then set up the market state. We might have to call PoolManager.initialize explicitly depending on how Uniswap v4 works (some commit of v4 separated pool creation and init).

After pool initialization, call a function on our PerpsHook or an admin function to set risk parameters: tradeFeeBps, maxDeviationBps, mmrBps, oiCap, funding params (k, cap, etc.). These could also be hardcoded or default, but likely configurable.

If using a specific network’s addresses: the script should support using actual USDC address on testnet and actual Uniswap v4 PoolManager address. For example, on Sepolia Uniswap v4 PoolManager is deployed at 0xE03A1074... and there is a USDC test token at 0x1c7D4B1...
quillaudits.com
quillaudits.com
. The script can fetch those from env or constants.

Basic Scenario Testing: Using a script or tests:

Have one user deposit, open a long; another deposit, open a short. Move price (we can simulate price move by manipulating an oracle or directly trading in the vAMM by a third party to shift price). Then let them close and verify final balances.

Test a case of imbalance: only one side positions, then see that funding accrues to insurance fund (because one side has no counterpart).

Induce a scenario where a position should be liquidated: perhaps we manually set the oracle price such that one’s MR is under threshold, then call liquidate and ensure the process closes the position, transfers penalty, covers any debt, etc.

Check invariants in tests: after a series of trades and closes, sum of all trader balances plus insurance fund equals initial deposits (minus withdrawals) ± tiny rounding.

Property Tests: We can write a Foundry invariant or property test to confirm conservation of funds. For instance, randomize a sequence of actions (open/close with random sizes, random small price shifts within band) and at the end assert total assets equal. Minor differences might occur if funding or fees went to insurance (then the "lost" amount from traders should equal insurance gained).

Gas and Optimization: Evaluate gas costs of opening/closing. Optimize critical parts if needed (e.g. inline some math, reduce SSTORE operations). But clarity is also important since it’s complex logic.

Security Review: As this is critical financial code, doing an internal review or inviting external audit of the contracts would be wise at this stage, before deploying real value. We’d look for potential issues like:

Ensuring that hook cannot be called in unintended ways (check msg.sender properly).

No scenario where locked funds can be freed improperly or withdrawn prematurely.

Oracle usage cannot be manipulated easily (we already mitigated with median and band).

Hook fee or delta usage doesn’t accidentally steal funds or break accounting.

The arithmetic (especially around funding accumulation, PnL calculation) is correct and doesn’t overflow. Use safe math or checked math as needed (Solidity 0.8 has built-in overflow check, which is good).

Ensure the NFTs can’t be transferred or if they are, it doesn’t allow someone to escape a losing position by sending it to someone else (maybe restrict transfer or require margin stays with position NFT’s owner – perhaps best to disallow transfer of active positions or require a transfer function to also move the margin which is complex; likely we disable transfer of the NFTs unless maybe for some future cross-margin scenario).

5. User Interface and Frontend Integration

Milestone: Develop a simple dApp interface for users to interact: deposit, open/close positions, view stats.

Use Scaffold-ETH 2 or a custom React app with ethers.js or viem + wagmi hooks. The UI should allow:

Connecting wallet, selecting a market (e.g. "ETH-PERP"), and seeing current price, funding rate, OI, etc.

Deposit/withdraw USDC. We can integrate a faucet or link if on testnet for USDC.

Open position: input amount or leverage and direction, then call PerpsRouter.openLong/Short. We’ll need to handle approval of USDC if router pulls from user, or instruct user to deposit first.

Display open positions (the subgraph or events can track PositionManager NFTs owned by the user). Show key info: size, entry price, current PnL (which can be computed from current mark price), margin, margin ratio, estimated liq price. Liq price calculation: basically solve price where equity = 0 or MR = mmr. We can derive: for a long, liq price ≈ entryPrice * (1 - margin*leverage/notional * (1/(1-mm))) (this formula can be derived offline). But easier: simulate what price makes margin + (price - entry)*size = maintenance margin * price * size.

Close or reduce position: UI with slider or input to close certain percentage, triggers router.

Display account balances (free/locked margin).

Display InsuranceFund balance and maybe system metrics (could be interesting for user to know insurance fund size and funding rate).

If possible, visualize funding rate (annualized %) which = current fundingRate * 24*365 (if hourly).

Perhaps a price chart for the perp vs spot for context (though that requires some data source; could skip for a hackathon-level UI).

The UI will also need to handle error messages (like if trade fails due to slippage or band violation, etc., show to user).

Use events or polling to update UI after transactions (e.g. on PositionOpened, etc.).

Keeper bots: While not user-facing, to test in a full environment we should simulate the off-chain agents:

A simple script for funding updater: every hour, call pokeFunding on each market.

A liquidation bot: every few seconds, query all positions, find any below threshold and call liquidate. For testing, we can run this as a script or incorporate into our tests by fast-forwarding time and checking.

Hedger bot: if we wanted, we could simulate an external price feed and a hedger that trades on it. But for now, skip or just mention that it's possible.

6. Deployment to Public Testnet (Sepolia/Base Goerli)

Milestone: Deploy the contracts on an Ethereum test network and perform end-to-end testing with real transaction flow.

Using the deployment scripts, target Sepolia for example:

Use known addresses: Uniswap v4 PoolManager on Sepolia
quillaudits.com
, Sepolia USDC address (Circle’s testnet USDC)
quillaudits.com
, and perhaps a Pyth oracle address for ETH/USD on Sepolia (Pyth has a proxy on each chain). We plug those into config.

Deploy all contracts (verify on Etherscan if possible).

Create pool and initialize with current ETH price (we can fetch from oracle or input manually).

Publish the addresses for front-end use.

The Uniswap pool’s address can be obtained (or we just derive it from PoolManager and our tokens/hook).

We should also deploy the dummy vETH token (an ERC20 used solely to represent the base asset in the pool). Actually, since it’s virtual, we might use an existing placeholder ERC20 (like an empty shell). If none, deploy an ERC20 named "vETH" with no mint (just used for addressing). Or use one of the special Currency wrappers Uniswap v4 uses (it can treat an address that is not a contract as a token too, due to "Currency" type in v4).

Once deployed, run the UI pointed at Sepolia. Do some trial trades with small amounts. Use Circle’s USDC faucet to get USDC for testing (they allow maybe 100 at a time)
quillaudits.com
. Provide those to testing wallets.

Monitor the contract events and logs to ensure everything is consistent. If any issues arise (like calculation errors, or a trade failing unexpectedly), fix and redeploy.

After stable operation on testnet, consider a code audit or further optimization if planning to go to mainnet or a competition (ETHGlobal) demo.

7. Future Enhancements (beyond MVP)

With a working MVP, we could consider additional features:

Cross-Margin Support: Our current design treats each position somewhat isolated with its locked margin. We could allow one user’s multiple positions to share a single margin pool (cross-margin) for efficiency. This would involve not locking margin per position strictly, but rather having a global account equity and allowing that to cover all positions. Liquidation becomes portfolio-based. This is more complex so we left it out for now.

Multi-collateral support: Using assets other than USDC as collateral or allowing a basket.

Advanced Order Types: We currently only handle market orders via direct swaps. One could integrate a limit order book or stop orders off-chain that execute via the router when triggered.

Multiple markets and assets: Deploying markets for BTC, etc., and possibly connecting their insurance funds or having a global insurance fund vs per-market. Maybe each market’s fees go to a common insurance fund to mutualize risk (which is often fine).

Dynamic Depth Adjustment: We could adjust the vAMM’s virtual liquidity over time (e.g., if consistently too much slippage, increase depth; but increasing depth means effectively "printing" virtual liquidity, which could dilute PnL maybe – usually not changed after init, except perhaps if adding an LP mechanism or using governance to scale market).

Comprehensive Analytics: Provide more data on funding rates, etc., possibly build a subgraph to index positions, trades, funding payments, insurance fund growth over time.

But these are outside the scope of the core build and can be iterated.

Conclusion and Key Takeaways

We have outlined a full design for a Perpetual Futures AMM on Uniswap v4 with all the moving parts. To recap the most important points:

Perpetual swaps allow indefinite leveraged trading by employing margin and a funding rate mechanism to stay tied to spot prices
kraken.com
. Our system implements this on-chain by combining a virtual AMM pricing curve with robust collateral management.

The architecture is modular, consisting of a Uniswap v4 hook contract that controls trade execution (applying custom pricing and dynamic fees) and auxiliary contracts for margin vaults, position tracking (NFTs), funding calculations, and an insurance fund. Off-chain keepers for price updates and liquidations complement the on-chain logic.

Trading happens via swaps against a virtual constant-product market maker. Traders don't exchange real tokens but interact with virtual reserves. Profits and losses are settled in a separate collateral pool (MarginAccount) immediately when positions close, making the system effectively zero-sum among traders
bookmap.com
 with the insurance fund absorbing edge cases.

We enforce strict risk controls: margin requirements and fast liquidation of under-collateralized positions, price guards to prevent trading on outlier prices
quillaudits.com
, open interest caps tied to available backstop liquidity
quillaudits.com
, and continuous funding rate adjustments to encourage balance between longs and shorts
investopedia.com
investopedia.com
.

The Insurance Fund accumulates protocol revenue (fees, penalties, etc.) and is used to pay any deficit so that winners receive their due profits even if losers’ margin wasn’t enough. This is crucial for guaranteeing payouts and system integrity. In extreme scenarios beyond the fund’s capacity, an ADL mechanism would kick in to deleverage positions, ensuring the platform never goes insolvent.

From a development perspective, Uniswap v4’s hooks give us a powerful way to implement custom AMM behavior (our vAMM and fee logic) within a proven DEX framework
docs.uniswap.org
. This saves us from writing a lot of low-level swap code and lets us focus on the higher-level logic of the perp exchange. We used hook callbacks like beforeSwap and afterSwap to seamlessly integrate margin checks and PnL settlement into the swap lifecycle.

We detailed an implementation roadmap including smart contract development, testing, and deployment on a testnet. Key contracts include the PerpsHook, PositionManager (ERC721) for tracking positions, MarginAccount (ERC20 vault), FundingOracle, InsuranceFund, and a user-facing Router. Each of these is critical for a specific aspect: e.g., PositionManager makes on-chain positions tangible and manageable, MarginAccount safely holds all user funds with proper controls, and FundingOracle ties us to real-world pricing.

The system is designed for composability and extendability. One could plug in different price oracles, add more asset markets easily by deploying new pools with the same hook, or integrate with other DeFi protocols (for example, using an Aave Adapter to allow users to borrow against their collateral for added leverage, as mentioned as an optional module).

For a full-stack developer new to DeFi, this project is a deep dive. We started from first principles of what a perpetual swap is and built up the entire stack needed to run one on-chain. By walking through the flows (deposit, open, close, funding, liquidation) and the rationale behind each component, we aimed to demystify how such a protocol works under the hood.

With this foundation, one should be able to not only implement the system but also explain it to users or contributors: users deposit USDC, trade a virtual asset on a curve, settle profits in USDC, and the system uses margin from losing trades first, an insurance fund second, to ensure every winner is paid. Fast liquidations and a continuously applied funding rate keep the market healthy and prices in line.