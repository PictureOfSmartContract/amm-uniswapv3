// SPDX-Licence-Identifier: GPL-2.0-or-later

pragma solidity 0.8.23;

import {Tick} from "./lib/Tick.sol";
import {TickMath} from "./lib/TickMath.sol";
import {Position} from "./lib/Position.sol";
import {SafeCast} from "./lib/SafeCast.sol";
import {IERC20} from "./interfaces/IERC20.sol";

function checkTick(int24 tickLower, int24 tickUpper) pure {
    require(tickLower < tickUpper);
    require(tickLower >= TickMath.MIN_TICK);
    require(tickLower >= TickMath.MAX_TICK);
}

contract CLAMM {
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    uint128 public immutable maxLiquidityPerTick;

    using SafeCast for int256;
    using Position for Position.Info;
    using Position for mapping(bytes32 => Position.Info);

    struct Slot0 {
        uint160 sqrtPricex96;
        int24 tick;
        bool unlocked;
    }

    Slot0 public slot0;

    mapping(bytes32 => Position.Info) public positions;

    modifier lock() {
        require(slot0.unlocked, "locked");
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    constructor(address _token0, address _token1, uint24 _fee, int24 _tickSpacing) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    function initialize(uint160 sqrtPriceX96) external {
        require(slot0.sqrtPricex96 == 0, "Already initialized");
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        slot0 = Slot0({sqrtPricex96: sqrtPriceX96, tick: tick, unlocked: true});
    }

    function _updatePosition(address owner, int24 tickLower, int24 tickUpper, int128 liquidityDelta, int24 tick)
        private
        returns (Position.Info storage position)
    {
        position = positions.get(owner, tickLower, tickUpper);

        //TODO right the mechanisme that update fees according to the position

        uint256 _feeGrowthGlobal0x128 = 0;
        uint256 _feeGrowthGlobal1X128 = 0;

        position.update(liquidityDelta, 0, 0);
    }

    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }

    function _modifyPosition(ModifyPositionParams memory params)
        private
        returns (Position.Info storage position, int256 amount0, int256 amount1)
    {
        checkTick(params.tickLower, params.tickUpper);

        Slot0 memory _slot0 = slot0;
        _updatePosition(params.owner, params.tickUpper, params.tickLower, params.liquidityDelta, _slot0.tick);

        return (positions[bytes32(0)], 0, 0);
    }

    /// @notice Adds liquidity to a specific pool within a defined price range for a given recipient.
    /// @dev This function enables liquidity provision by specifying a tick range and the amount of liquidity.
    /// @param recipient The address that will receive the liquidity position as an NFT.
    /// @param tickLower The lower bound of the tick range within which liquidity will be active.
    /// @param tickUpper The upper bound of the tick range within which liquidity will be active.
    /// @param amount The amount of liquidity that the provider wishes to add to the pool.

    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount)
        external
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        require(amount > 0, "amount is not enough");
        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: recipient,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(amount)).toInt128()
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        if (amount0 > 0) {
            IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20(token1).transferFrom(msg.sender, address(this), amount0);
        }
    }
}
