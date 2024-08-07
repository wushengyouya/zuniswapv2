// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;
import {IZuniswapV2Factory} from "./interfaces/IZuniswapV2Factory.sol";
import {IZuniswapV2Pair} from "./interfaces/IZuniswapV2Pair.sol";
import {ZuniswapV2Library} from "./ZuniswapV2Library.sol";

contract ZuniswapV2Router {
    error InsufficientAAmount();
    error InsufficientBAmount();
    error SafeTransferFailed();
    error InsufficientOutputAmount();
    error ExcessiveInputAmount();
    IZuniswapV2Factory factory;

    //初始化工厂地址
    constructor(address factoryAddress) {
        factory = IZuniswapV2Factory(factoryAddress);
    }

    //添加流动性,不收取手续费
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) public returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        //不存在合约则创建
        if (factory.pairs(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB);
        }
        //计算流动性
        (amountA, amountB) = _calculateLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        address pairAddress = ZuniswapV2Library.pairFor(
            address(factory),
            tokenA,
            tokenB
        );
        _safeTransferFrom(tokenA, msg.sender, pairAddress, amountA);
        _safeTransferFrom(tokenB, msg.sender, pairAddress, amountB);

        //mint流动性代币
        liquidity = IZuniswapV2Pair(pairAddress).mint(to);
    }

    //计算流动性
    function _calculateLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        //获取记录的token总额
        (uint256 reserveA, uint256 reserveB) = ZuniswapV2Library.getReserves(
            address(factory),
            tokenA,
            tokenB
        );

        //reserveA=0,reserveB=0,为首次添加流动性
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            //非首次，存在代币

            //确认tokenA,计算需要添加tokenB数量
            uint256 amountBOptimal = ZuniswapV2Library.queto(
                amountADesired, //1
                reserveA, //1
                reserveB //2
            );

            //tokenB需求数量小于等于添加的数量
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal <= amountBMin) revert InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = ZuniswapV2Library.queto(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal <= amountAMin) {
                    revert InsufficientAAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    //移除流动性
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) public returns (uint256 amountA, uint256 amountB) {
        address pair = ZuniswapV2Library.pairFor(
            address(factory),
            tokenA,
            tokenB
        );
        //将要销毁的liquidity转入pair合约
        IZuniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        (amountA, amountB) = IZuniswapV2Pair(pair).burn(to);

        if (amountA < amountAMin) revert InsufficientAAmount();
        if (amountB < amountBMin) revert InsufficientBAmount();
    }

    //TODO: 确定tokenA数量,换取tokenB
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) public returns (uint256[] memory amounts) {
        amounts = ZuniswapV2Library.getAmountsOut(
            address(factory),
            amountIn,
            path
        );
        if (amounts[amounts.length - 1] < amountOutMin)
            revert InsufficientOutputAmount();
        _safeTransferFrom(
            path[0],
            msg.sender,
            ZuniswapV2Library.pairFor(address(factory), path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    //TODO:确定要提取TokenB数量，计算要投入多少TokenA
    function swapTokensForExactTokens(
        uint256 amountOut, //提取的TokenB
        uint256 amountInMax, //最大投入
        address[] calldata path,
        address to
    ) public returns (uint256[] memory amounts) {
        amounts = ZuniswapV2Library.getAmountsIn(
            address(factory),
            amountOut,
            path
        );

        if (amounts[amounts.length - 1] > amountInMax)
            revert ExcessiveInputAmount();
        _safeTransferFrom(
            path[0],
            msg.sender,
            ZuniswapV2Library.pairFor(address(factory), path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    //TODO:
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address to_
    ) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = ZuniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? ZuniswapV2Library.pairFor(
                    address(factory),
                    output,
                    path[i + 2]
                )
                : to_;
            IZuniswapV2Pair(
                ZuniswapV2Library.pairFor(address(factory), input, output)
            ).swap(amount0Out, amount1Out, to, "");
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                from,
                to,
                value
            )
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFailed();
        }
    }
}
