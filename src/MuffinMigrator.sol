// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IManagerMinimal} from "./interfaces/muffin/IManagerMinimal.sol";
import {INonfungiblePositionManagerMinimal} from "./interfaces/uniswap/INonfungiblePositionManagerMinimal.sol";

contract MuffinMigrator {
    IManagerMinimal public immutable muffinManager;
    INonfungiblePositionManagerMinimal public immutable uniV3PositionManager;

    struct PermitUniV3Params {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct RemoveUniV3Params {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct MintParams {
        address recipient;
        bool needCreatePool;
        bool needAddTier;
        uint24 sqrtGamma;
        uint128 sqrtPrice;
        uint8 tierId;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    constructor(address muffinManager_, address uniV3PositionManager_) {
        muffinManager = IManagerMinimal(muffinManager_);
        uniV3PositionManager = INonfungiblePositionManagerMinimal(uniV3PositionManager_);
    }

    function migrateFromUniV3WithPermit(
        PermitUniV3Params calldata permitParams,
        RemoveUniV3Params calldata removeParams,
        MintParams calldata mintParams
    ) external {
        // permit this contract to access the uniswap v3 position
        // also act as token owner validation
        uniV3PositionManager.permit(
            address(this),
            removeParams.tokenId,
            permitParams.deadline,
            permitParams.v,
            permitParams.r,
            permitParams.s
        );

        // get uniswap position info
        (address token0, address token1) = _getUniV3Position(removeParams.tokenId);

        // record the current balance of tokens
        uint256 balance0 = ERC20(token0).balanceOf(address(this));
        uint256 balance1 = ERC20(token1).balanceOf(address(this));

        // remove and collect uniswap v3 position
        (uint256 amount0, uint256 amount1) = _removeAndCollectUniV3Position(removeParams);

        // allow muffin manager to use the tokens
        _approveTokenToMuffinManager(token0, amount0);
        _approveTokenToMuffinManager(token1, amount1);

        // mint muffin position
        _mintPosition(token0, token1, mintParams);

        // calculate the remaining tokens, need underflow check if over-used
        balance0 = ERC20(token0).balanceOf(address(this)) - balance0;
        balance1 = ERC20(token1).balanceOf(address(this)) - balance1;

        // refund remaining tokens to recipient's wallet
        if (balance0 > 0) SafeTransferLib.safeTransfer(ERC20(token0), mintParams.recipient, balance0);
        if (balance1 > 0) SafeTransferLib.safeTransfer(ERC20(token1), mintParams.recipient, balance1);
    }

    function _getUniV3Position(uint256 tokenId)
        internal
        view
        returns (address token0, address token1)
    {
        (
            ,
            ,
            token0,
            token1,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = uniV3PositionManager.positions(tokenId);
    }

    function _removeAndCollectUniV3Position(RemoveUniV3Params calldata removeParams)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        uniV3PositionManager.decreaseLiquidity(
            INonfungiblePositionManagerMinimal.DecreaseLiquidityParams({
                tokenId: removeParams.tokenId,
                liquidity: removeParams.liquidity,
                amount0Min: removeParams.amount0Min,
                amount1Min: removeParams.amount1Min,
                deadline: removeParams.deadline
            })
        );

        (amount0, amount1) = uniV3PositionManager.collect(
            INonfungiblePositionManagerMinimal.CollectParams({
                tokenId: removeParams.tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    function _approveTokenToMuffinManager(address token, uint256 amount) internal {
        uint256 allowance = ERC20(token).allowance(address(this), address(muffinManager));
        if (allowance >= amount) return;

        // revoke allowance before setting a new one
        if (allowance != 0) ERC20(token).approve(address(muffinManager), 0);

        try ERC20(token).approve(address(muffinManager), type(uint256).max) {
        } catch {
            // if the token contract disallow approve max, approve the exact amount only
            ERC20(token).approve(address(muffinManager), amount);
        }
    }

    function _mintPosition(address token0, address token1, MintParams calldata mintParams) internal {
        if (mintParams.needCreatePool) {
            muffinManager.createPool(token0, token1, mintParams.sqrtGamma, mintParams.sqrtPrice, false);
        } else if (mintParams.needAddTier) {
            muffinManager.addTier(token0, token1, mintParams.sqrtGamma, false, mintParams.tierId);
        }

        muffinManager.mint(
            IManagerMinimal.MintParams({
                token0: token0,
                token1: token1,
                tierId: mintParams.tierId,
                tickLower: mintParams.tickLower,
                tickUpper: mintParams.tickUpper,
                amount0Desired: mintParams.amount0Desired,
                amount1Desired: mintParams.amount1Desired,
                amount0Min: mintParams.amount0Min,
                amount1Min: mintParams.amount1Min,
                recipient: mintParams.recipient,
                useAccount: false
            })
        );
    }
}
