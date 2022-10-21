# Muffin Migrator

**Muffin Migrator** is a helper contract to migrate liquidity from Uniswap V3 to Muffin.

## Entry point

- [`MuffinMigrator.sol`](./src/MuffinMigrator.sol): It contains a major function `migrateFromUniV3WithPermit()` for migrating liquidity from Uniswap V3 to Muffin.

### Detailed steps inside `migrateFromUniV3WithPermit`

1. Call `permit` from Uniswap V3 to approve this contract to "spend" the position. It also act as token owner verification to prevent other people to migrate the position without a correct signature.

1. Get `token0` and `token1` address from the position.

1. Check the initial balances of both tokens of this contract.

1. Remove the liquidity and collect both tokens from Uniswap V3. Only the newly withdrew amounts are collected by this contract, fee and previously removed liquidity are remained in Uniswap V3.

1. Mint a new Muffin position by the collected tokens. Create a new Muffin pool or new fee tier if needed.

1. Check the balances of both tokens of this contract again to determine the refund amounts.

1. Refund the amounts to recipient and that's the end of the migration.

### Notes

- Muffin needs a [certain amount of both tokens](https://github.com/muffinfi/muffin-sdk/blob/v1.0.8/src/entities/pool.ts#L91-L110) to create new pool/fee tier.<br>
  If you are migrating an out of range position and a new pool/fee tier is needed, this migrator contract cannot help you to migrate as it does not have enough tokens to create them.

- You should only deposit liquidity into Muffin at a price you believe is correct.<br>
  If the price seems incorrect, you can either make a swap to move the price or wait for someone else to do so.
