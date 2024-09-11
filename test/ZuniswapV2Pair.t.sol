// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mintable} from "./mock/ERC20Mintable.sol";
import {ZuniswapV2Pair} from "../src/ZuniswapV2Pair.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {UQ112x112} from "../src/libraries/UQ112x112.sol";

//在Uniswap v2中，流动性池通常包含两种代币，我们称之为token0和token1。
//当用户想要通过池子交换代币时，他们可以从池子中取出一定数量的token0或token1（即amount0Out和amount1Out）。
//相应地，为了维持池子中代币价格的恒定乘积，必须向池子中存入一定数量的对方代币。
contract ZuniswapV2PairTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    ZuniswapV2Pair pair;
    TestUser testUser;
    using UQ112x112 for uint256;

    function setUp() public {
        token0 = new ERC20Mintable("Token A", "A");
        token1 = new ERC20Mintable("Token B", "B");
        pair = new ZuniswapV2Pair();
        pair.initialize(address(token0), address(token1));
        testUser = new TestUser();

        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);

        token0.mint(address(testUser), 10 ether);
        token1.mint(address(testUser), 10 ether);
    }

    //比较传入的总金额与合约存储的总金额是否相等
    function assertReserves(
        uint112 expectedReserve0,
        uint112 expectedReserve1
    ) internal view {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(expectedReserve0, reserve0, "unexpected reserve0");
        assertEq(expectedReserve1, reserve1, "unexpected reserve1");
    }

    //初次添加流动性测试
    function testMintBootstrap() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        //首次Mint会burn 1000 流动性代币
        pair.mint(address(this));

        assertEq(pair.balanceOf(address(this)), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);
        assertEq(pair.totalSupply(), 1 ether);
    }

    //已存在流动性
    function testMintWhenTheresLiquidity() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(address(this));

        vm.warp(37); //设置区块时间
        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 2 ether);

        pair.mint(address(this));

        assertEq(pair.balanceOf(address(this)), 3 ether - 1000);
        assertReserves(3 ether, 3 ether);
        assertEq(pair.totalSupply(), 3 ether);
    }

    //投入的不同比例的代币
    function testMintUnbalanced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(address(this));

        assertEq(pair.balanceOf(address(this)), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);
        //投入比例不一样的流动性，取最小值
        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(address(this));

        assertEq(pair.balanceOf(address(this)), 2 ether - 1000);
        assertReserves(3 ether, 2 ether);
    }

    //初始化装修，直接mint，向下溢出
    function testMintLiquidityUnderflow() public {
        vm.expectRevert(
            hex"4e487b710000000000000000000000000000000000000000000000000000000000000011"
        );
        pair.mint(address(this));
    }

    //测试添加0流动性,金额太小开平方后为1000 - 默认值
    function testMintZeroLiquidity() public {
        token0.transfer(address(pair), 1000);
        token1.transfer(address(pair), 1000);

        vm.expectRevert(bytes(hex"d226f9d4")); // InsufficientLiquidityMinted()
        pair.mint(address(this));
    }

    //FIXME:测试销毁
    function testBurn() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(address(this));
        assertEq(pair.balanceOf(address(this)), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);
        pair.transfer(address(pair), pair.balanceOf(address(this)));
        pair.burn(address(this));
        assertEq(token0.balanceOf(address(this)), 10 ether - 1000);
        assertEq(token1.balanceOf(address(this)), 10 ether - 1000);
        assertEq(pair.balanceOf(address(this)), 0 ether);
    }

    // function testBurnUnbalanceDifferrentUsers()public{

    // }

    //FIXME:
    function testBurnZeroLiquidity() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(address(this));

        // bytes memory prankData = abi.encodeWithSignature("burn()");

        vm.prank(address(1));
        vm.expectRevert();
        pair.burn(address(this));
    }

    //不存在流动性，执行burn
    function testBurnZeroTotalSupply() public {
        vm.expectRevert();
        pair.burn(address(this));
    }

    //测试销毁不同比例的代币
    function testBurnUnbalance() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(address(this)); //1 LP

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(address(this)); //1 LP
        pair.transfer(address(pair), pair.balanceOf(address(this)));
        pair.burn(address(this));
        assertEq(pair.balanceOf(address(this)), 0);
        assertReserves(1500, 1000);
        assertEq(token0.balanceOf(address(this)), 10 ether - 1500);
        assertEq(token1.balanceOf(address(this)), 10 ether - 1000);
        // assertEq(token0.balanceOf(address(pair)), 1000);
        // assertEq(token1.balanceOf(address(pair)), 1 ether);
    }

    //测试取出0代币
    function testSwapZeroOut() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(address(this));
        vm.expectRevert();
        pair.swap(0, 0, address(this), "");
    }

    //转入token0,取出token0
    function testSwapOut() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(address(this)); //1 LPT - 1000
        console.log("current LP Token:", pair.balanceOf(address(this)));
        vm.startPrank(address(testUser));
        token0.transfer(address(pair), 0.3 ether);
        pair.swap(0.2 ether, 0, address(testUser), "");
        vm.stopPrank();
        assertEq(pair.balanceOf(address(this)), 1 ether - 1000);
        assertReserves(1 ether + 0.1 ether, 1 ether);

        assertEq(pair.balanceOf(address(this)), 1 ether - 1000);
        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether,
            "unexpected address(this) token0"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 1 ether,
            "unexpected address(this) token1"
        );
        assertEq(
            token0.balanceOf(address(testUser)),
            10 ether - 0.3 ether + 0.2 ether,
            "unexpected testUser token0"
        );
    }

    //测试转入token0，取出token1的场景
    function testSwapBasicScenario() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);

        pair.mint(address(this));

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0, 0.18 ether, address(this), "");

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether + 0.18 ether,
            "unexpected token1 balance"
        );
        assertReserves(1 ether + 0.1 ether, 2 ether - 0.18 ether);
    }

    //测试转入token1，取出token0的场景
    function testSwapBasicScenarioReverseDirection() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        token1.transfer(address(pair), 0.2 ether);
        pair.swap(0.09 ether, 0, address(this), "");

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether + 0.09 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether - 0.2 ether,
            "unexpected token1 balance"
        );

        assertNotEq(pair.balanceOf(address(this)), 1 ether - 1000);
        //首次添加流动性，获取的流动性代币=两种代币乘积再开平方
        assertEq(pair.balanceOf(address(this)), 1.414_2135_6237_3094_048 ether);
        assertReserves(1 ether - 0.09 ether, 2 ether + 0.2 ether);
    }

    //测试同时置换token0与token1
    function testSwapBidirectinal() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        token0.transfer(address(pair), 0.1 ether);
        token1.transfer(address(pair), 0.2 ether);
        pair.swap(0.09 ether, 0.18 ether, address(this), "");

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether + 0.09 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether - 0.2 ether + 0.18 ether,
            "unexpected token1 balance"
        );

        assertReserves(
            1 ether + 0.1 ether - 0.09 ether,
            2 ether + 0.2 ether - 0.18 ether
        );
    }

    //在Uniswap v2中，流动性池通常包含两种代币，我们称之为token0和token1。
    //当用户想要通过池子交换代币时，他们可以从池子中取出一定数量的token0或token1（即amount0Out和amount1Out）。
    //相应地，为了维持池子中代币价格的恒定乘积，必须向池子中存入一定数量的对方代币。
    function testSwapInsufficientLiquidity() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this));

        vm.expectRevert(bytes(hex"bb55fd27")); // InsufficientLiquidity
        pair.swap(0, 2.1 ether, address(this), "");

        vm.expectRevert(bytes(hex"bb55fd27")); // InsufficientLiquidity
        pair.swap(1.1 ether, 0, address(this), "");
    }

    //测试存入token0流动性，取出的token1远远小于添加的流动性
    function testSwapUnderpriced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);

        pair.mint(address(this));

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0, 0.09 ether, address(this), "");
        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether + 0.09 ether,
            "unexpected token1 balance"
        );

        assertReserves(1 ether + 0.1 ether, 2 ether - 0.09 ether);
    }

    //测试存入token0流动性，取出的token1超过了添加的流动性
    function testSwapOverpriced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);

        pair.mint(address(this));

        //由于pair.swap 调用失败，此次转账后合约存储的token总额并未更新
        token0.transfer(address(pair), 0.1 ether);

        vm.expectRevert();
        pair.swap(0, 0.39 ether, address(this), ""); //InsufficientLiquidity

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether,
            "unexpected token1 balance"
        );

        //assertReserves(1 ether + 0.1 ether, 2 ether); //test fail
        assertReserves(1 ether, 2 ether);
    }

    //测试 时间加权平均价格(TWAP)
    function testCumulativePrices() public {
        vm.warp(0);
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(address(this));
        (
            uint256 initialPrice0,
            uint256 initialPrice1
        ) = calculateCurrentPrice();

        //0 秒的时候
        pair.sync();
        assertCumulativePrices(0, 0);

        //1 秒
        vm.warp(1);
        pair.sync();
        assertBlockTimestampLast(1);
        assertCumulativePrices(initialPrice0, initialPrice1);

        //2秒
        vm.warp(2);
        pair.sync();
        assertBlockTimestampLast(2);
        assertCumulativePrices(initialPrice0 * 2, initialPrice1 * 2);
        // 3 seconds passed.
        vm.warp(3);
        pair.sync();
        assertBlockTimestampLast(3);
        assertCumulativePrices(initialPrice0 * 3, initialPrice1 * 3);

        // // Price changed.
        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);
        pair.mint(address(this));

        (uint256 newPrice0, uint256 newPrice1) = calculateCurrentPrice();

        // // 0 seconds since last reserves update.
        assertCumulativePrices(initialPrice0 * 3, initialPrice1 * 3);

        // // 1 second passed.
        vm.warp(4);
        pair.sync();
        assertBlockTimestampLast(4);
        assertCumulativePrices(
            initialPrice0 * 3 + newPrice0,
            initialPrice1 * 3 + newPrice1
        );

        // 2 seconds passed.
        vm.warp(5);
        pair.sync();
        assertBlockTimestampLast(5);
        assertCumulativePrices(
            initialPrice0 * 3 + newPrice0 * 2,
            initialPrice1 * 3 + newPrice1 * 2
        );

        // 3 seconds passed.
        vm.warp(6);
        pair.sync();
        assertBlockTimestampLast(6);
        assertCumulativePrices(
            initialPrice0 * 3 + newPrice0 * 3,
            initialPrice1 * 3 + newPrice1 * 3
        );
    }

    function assertBlockTimestampLast(uint32 expected) internal view {
        (, , uint32 blockTimestampLast) = pair.getReserves();

        assertEq(blockTimestampLast, expected, "unexpected blockTimestampLast");
    }

    function assertCumulativePrices(
        uint256 expectPrice0,
        uint256 expectPrice1
    ) internal view {
        assertEq(
            pair.price0CumulativeLast(),
            expectPrice0,
            "unexpected cumulative price"
        );
        assertEq(
            pair.price1CumulativeLast(),
            expectPrice1,
            "unexpected cumulative price"
        );
    }

    //计算当前价格
    function calculateCurrentPrice()
        internal
        view
        returns (uint256 price0, uint256 price1)
    {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        price0 = reserve0 > 0
            ? (reserve1 * uint256(UQ112x112.Q112)) / reserve0
            : 0;

        price1 = reserve1 > 0
            ? (reserve0 * uint256(UQ112x112.Q112)) / reserve1
            : 0;
    }

    //测试闪电贷
    function testFlashloan() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint(address(this)); //1 LP-TOKEN

        uint256 flashloanAmount = 0.1 ether;
        //计算闪电贷的手续费，uniswapV2 手续0.3%
        /** 
         *  假设用户通过闪电贷借用了 10000 个代币，以下是费用的计算过程：
            首先，10000 * 1000 得到 10000000。
            然后，10000000 / 997 得到大约 10030.04514266499。
            接着，减去原始借款金额 10000，得到 30.04514266499。
            最后，加上 1，得到最终的交易费用 31.04514266499。
            这意味着用户需要支付 31.04514266499 个代币作为闪电贷的费用。
        */
        uint256 flashloanFee = (flashloanAmount * 1000) /
            997 -
            flashloanAmount +
            1;

        Flashloaner fl = new Flashloaner();
        token1.transfer(address(fl), flashloanFee);
        fl.flashloan(address(pair), 0, flashloanAmount, address(token1));

        assertEq(token1.balanceOf(address(fl)), 0);
        assertEq(token1.balanceOf(address(pair)), 2 ether + flashloanFee);
    }
}

contract Flashloaner {
    error InsufficientFlashLoanAmount();

    uint256 expectedLoanAmount;

    function flashloan(
        address pairAddress,
        uint256 amount0Out,
        uint256 amount1Out,
        address tokenAddress
    ) public {
        if (amount0Out > 0) {
            expectedLoanAmount = amount0Out;
        }
        if (amount1Out > 0) {
            expectedLoanAmount = amount1Out;
        }

        ZuniswapV2Pair(pairAddress).swap(
            amount0Out,
            amount1Out,
            address(this),
            abi.encode(tokenAddress)
        );
        console.log(
            "flashloan:",
            ERC20(tokenAddress).balanceOf(address(this)),
            " amount1Out:",
            amount1Out
        );
    }

    function zuniswapV2Call(
        address /*sender*/,
        uint256 /*amount0Out*/,
        uint256 /*amount1Out*/,
        bytes calldata data
    ) public {
        address tokenAddress = abi.decode(data, (address));
        uint256 balance = ERC20(tokenAddress).balanceOf(address(this));
        if (balance < expectedLoanAmount) revert InsufficientFlashLoanAmount();
        ERC20(tokenAddress).transfer(msg.sender, balance);
    }
}

contract TestUser {
    //提供流动性
    function provideLiquidity(
        address pairAddress_,
        address token0Address_,
        address token1Address_,
        uint256 amount0_,
        uint256 amount1_
    ) public {
        ERC20(token0Address_).transfer(pairAddress_, amount0_);
        ERC20(token1Address_).transfer(pairAddress_, amount1_);
        //铸造流动性代币
        ZuniswapV2Pair(pairAddress_).mint(address(this));
    }

    //撤回流动性
    function withdrawLiquidity(address pairAddress_) public {
        ZuniswapV2Pair(pairAddress_).burn(address(this));
    }
}
