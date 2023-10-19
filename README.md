# Relay

Introduced in Velodrome V2 is a new type of veNFT called a "managed NFT" (also known as "(m)veNFT").
A (m)veNFT aggregates veNFT voting power into a single NFT, with rewards accrued by the NFT going to
the owner of the (m)veNFT. The (m)veNFT votes for pools in the same way a normal veNFT votes, with
the exception that its' voting power is this aggregated voting power.

The challenge arises when a (m)veNFT has earned rewards from a voting period. Does the (m)veNFT
owner keep the rewards for themselves, distribute the rewards back to the veNFT depositors (either
as the reward token or as VELO), or do something else with these rewards? The Velodrome team
provides a working MVP to solve this.

## Challenge

Provide a trusted and automated solution to distribute rewards earned by a (m)veNFT back to its'
depositors.

## Solution

An automated contract to convert rewards earned by a (m)veNFT back into the intended token.
Autocompounder will convert it to VELO and then deposit into the (m)veNFT. Autoconverter will only
convert it to the Autoconverter token. The autocompounder's (m)veNFT voting power increases from
these VELO deposits, further increasing the rewards earned. When a normal veNFT holder who
previously deposited into this (m)veNFT withdraws their veNFT from the (m)veNFT back to their
wallet, they receive their initial deposit back, as well as their proportional share of all
compounded rewards.

## Features

There are two types of Relays with similar functionalities:

|                           | Autocompounder                      | Autoconverter                         |
| ------------------------- | ----------------------------------- | ------------------------------------- |
| Claim Rewards             | Yes                                 | Yes                                   |
| Swap                      | Yes (only to VELO)                  | Yes (only to the Autoconverter token) |
| Compound                  | Yes                                 | No                                    |
| Reward paid to caller[^1] | Yes                                 | No                                    |
| Sweep tokens              | Yes (if not a high liquidity token) | Yes (any token)                       |
| Vote                      | Yes                                 | Yes                                   |
| Increase rewards          | Yes                                 | No                                    |
| Set caller reward amount  | Yes                                 | No                                    |
| Add high liquidity tokens | Yes                                 | Yes                                   |
| Add/remove Keepers        | Yes                                 | Yes                                   |

## Implementation

There are several key components of the `Relay`:

-   Access control / trust levels
-   Time windows of access
-   (m)veNFT design considerations

## Access Control / Trust levels

There are degrees of trust and access given to various groups. The groups are:

-   Public
-   Keepers
-   Allowed callers
-   Relay Admins
-   Velodrome team

### Public

Can be any EOA or contract. Are allowed to claim rewards, swap (and compound - for autocompounders)
within the last 24 hours of an epoch. Swap routes are determined using a fixed optimizer contract,
although callers can provide their own custom route provided there is a better return. The optional
swap route provided must only route through high liquidity tokens, as added by team. In the
autocompounder, Public callers are rewarded based on the amount compounded - they receive a minimum
of either (a) 1% of the VELO converted from swaps (rounded down) or (b) the constant VELO reward set
by the team.

### Keepers

Addresses authorized by Velodrome team to claim rewards (and compound - for autocompounders)
starting one hour after epoch flips. Keepers are trusted to swap rewarded tokens using the routes
they determine (as long as they are better than the routes provided by the optimizer) which is then
deposited into the (m)veNFT.

### Allowed Callers

Addresses authorized by the Relay admin to vote for gauges and send additional VELO rewards to the
(m)veNFT to be distributed among veNFTs who have locked into the (m)veNFT.

### Relay Admins

An initial admin is set on Relay creation who can then add/remove other admins, as well as revoke
their own admin role. Admins can also add/remove Allowed Callers. Within the first 24 hours after an
epoch flip, an admin can claim and sweep reward tokens to any recipients.

### Velodrome Team

The team can set the VELO reward amount for public callers, add high liquidity tokens, and
add/remove keepers.

## Roles

|                           | Public | Keeper | Allowed Caller | Admin                               | Velodrome Team |
| ------------------------- | ------ | ------ | -------------- | ----------------------------------- | -------------- |
| Claim Rewards             | Yes    | Yes    |                | Yes                                 |                |
| Swap and Compound         | Yes    | Yes    |                | Yes                                 |                |
| Reward paid to caller[^1] | Yes    |        |                |                                     |                |
| Sweep tokens              |        |        |                | Yes (if not a high liquidity token) |                |
| Vote & increase rewards   |        |        | Yes            |                                     |                |
| Set caller reward amount  |        |        |                |                                     | Yes            |
| Add high liquidity tokens |        |        |                |                                     | Yes            |
| Add/remove Keepers        |        |        |                |                                     | Yes            |

## Time Windows of Access

| Who             | First hour | Middle[^2] | Last 24 Hours |
| --------------- | ---------- | ---------- | ------------- |
| Public          |            |            | X             |
| Keeper          |            | X          | X             |
| Allowed Callers | X          | X          | X             |
| Admin           | X          | X          | X             |
| Team            | X          | X          | X             |

## (m)veNFT Design Considerations

### Who can create a Relay?

Anyone who owns a (m)veNFT can create a Relay. Only the `allowedManager` role within VotingEscrow
and the `governor` role within Voter have permission to create a (m)veNFT. The (m)veNFT is sent to
the Relay in creation where it will permanently reside.

### Lack of Governance voting ability

Anyone with a normal veNFT can deposit into a (m)veNFT. Therefore, we expect to see (m)veNFTs
controlled with the aggregate voting power of hundreds normal veNFTs or more. The motivation in
depositing a normal veNFT is to earn passive rewards, not to delegate voting power for governance.
However, the cumulative voting power of the (m)veNFT could be significant enough to influence
Velodrome governance proposals. Therefore, the Relay is designed:

-   Without governance voting functionality
-   No ability to withdraw the (m)veNFT

So, once a (m)veNFT is deposited into a Relay, it will stay there permanently.

### Leaving the (m)veNFT

What happens if a (m)veNFT is deactivated by the team? What happens if the controllers for the
(m)veNFT can no longer be trusted to act in the best interest of the veNFT depositors? What happens
if a veNFT depositor finds a different (m)veNFT to deposit into, or if they decide to vote from
their own veNFT again? The answer to these questions is the same:

**At any time, a normal veNFT can be withdrawn from its' deposited (m)veNFT, as long as it has _not_
been deposited within the same epoch**.

### What if Keepers provide less-than-optimal routes to extract value?

The routes provided by the keepers are only used if they're better than the routes provided by the
Optimizer.

### Can I trust the Admin in sweeping tokens?

The intention of sweep is solely to allow pulling of low liquidity tokens earned by the (m)veNFT, to
prevent compounding the tokens with high slippage. The admin can revoke their own access if desired.
High liquidity tokens are initially set when a relay is deployed by the factory. Key aspects about these tokens include:

-   They are established during the relay's deployment.
-   Once added to the list, these tokens cannot be removed, not even by the admin/owner.
-   Only the owner of the relay factory has the permission to add more high liquidity tokens to the list.

Since the autoconverter isn't intended for public use, the admin has the authority to sweep any token, even if it is not a high liquidity token.
It's important to understand sweeping is designed to work as a last-resort. If the need arises, the admin can sweep tokens and deposit the high liquidity tokens back manually. They also can try to swap these tokens by identifying the appropriate routes which aren't unavailable in the optimizer.

### Why different time windows of access?

The first hour after an epoch flip are given solely to the Admin in the case a token sweep is
needed. After this privileged access, the Keeper can claim and compound tokens as desired. This
prevents a race to sweep if the keepers are automated or compound as soon as they are able to. The
following five days are given solely to keepers to compound rewards. Then, within the last 24 hours,
everyone is incentivized to claim and compound any remaining rewards, including keepers. This
guarantees that rewards of high liquidity tokens will always be claimed and compounded, even without
active keepers.

### Current list of high liquidity tokens

These tokens exist within Velodrome with at least $1M+ liquidity or $250k+ VELO liquidity in two or
more pools:

-   [USDC](https://optimistic.etherscan.io/token/0x7F5c764cBc14f9669B88837ca1490cCa17c31607)
-   [DOLA](https://optimistic.etherscan.io/token/0x8aE125E8653821E851F12A49F7765db9a9ce7384)
-   [WETH](https://optimistic.etherscan.io/token/0x4200000000000000000000000000000000000006)
-   [USD+](https://optimistic.etherscan.io/token/0x73cb180bf0521828d8849bc8CF2B920918e23032)
-   [OP](https://optimistic.etherscan.io/token/0x4200000000000000000000000000000000000042)
-   [MAI](https://optimistic.etherscan.io/token/0xdFA46478F9e5EA86d57387849598dbFB2e964b02)
-   [wstETH](https://optimistic.etherscan.io/token/0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb)
-   [DAI](https://optimistic.etherscan.io/token/0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1)
-   [LUSD](https://optimistic.etherscan.io/token/0xc40F949F8a4e094D1b49a23ea9241D289B7b2819)
-   [FRAX](https://optimistic.etherscan.io/token/0x2E3D870790dC77A83DD1d18184Acc7439A53f475)
-   [frxETH](https://optimistic.etherscan.io/token/0x6806411765Af15Bddd26f8f544A34cC40cb9838B)

## Deployment

See `script/README.md` for more detail.

## Footnotes

[^1]: Caller is referring to anyone who calls the autocompounder's function `rewardAndCompound`. Even if the caller is a keeper/admin/allowed caller, they are treated the same in the reward amount calculation.
[^2]: Middle is the timeframe between the end of the 1st hour after an epoch flip and the start of the last day of epoch.
