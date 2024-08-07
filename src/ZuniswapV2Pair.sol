// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Math} from "./libraries/Math.sol";
import {console} from "forge-std/Test.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";
import {IZuniswapV2Callee} from "./interfaces/IZuniswapV2Callee.sol";

interface IERC20 {
    function balanceOf(address) external returns (uint256);

    function transfer(address to, uint256 amount) external;
}
error AlreadyInitialized();
error BalanceOverflow();
error InsufficientLiquidityMinted();
error InsufficientLiquidityBurned();
error InsufficientInputAmount();
error InsufficientOutputAmount();
error InsufficientLiquidity();
error InvalidK();
error TransferFailed();

contract ZuniswapV2Pair is ERC20, Math {
    using UQ112x112 for uint224;
    //TODO: 默认值,？？
    uint256 constant MINIMUM_LIQUIDITY = 1000;
    //Token币对地址
    address public token0;
    address public token1;

    //币对合约记录的token总量
    uint112 private reserve0;
    uint112 private reserve1;

    uint32 private blockTimestampLast;

    //最新token价格
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    //事件
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address to
    );
    event BurnValue(uint256 liquidity, uint256 balance, uint256 totalSupply);

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserve0, uint256 reserve1);

    event Swap(
        address indexed sender,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    //初始化LP-Token,初始化token币对
    constructor() ERC20("ZuniswapV2 Pair", "ZUNIV2", 18) {}

    //mint LR-Token,添加流动性
    function mint(address to) public returns (uint256 liquidity) {
        //获取存储的货币余额
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        //获取当前合约代币余额
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        //计算用户投入的代币
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        //计算流动性代币，当为初始状态时,为投入代币对的开平方-MINIMUM_LIQUIDITY
        //如果已存在流动性池,按比例计算选择小的token,（流动性代币与token代币成正比关系）
        //totalSupply * amount/reserve
        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount0 * totalSupply) / _reserve0,
                (amount1 * totalSupply) / _reserve1
            );
        }
        if (liquidity <= 0) {
            revert InsufficientLiquidityMinted();
        }
        console.log(liquidity);
        //给用户铸造LR-Token
        _mint(to, liquidity);
        //更新合约代币余额
        _update(balance0, balance1, _reserve0, _reserve1);

        emit Mint(to, amount0, amount1);
    }

    //初始化token
    function initialize(address token0_, address token1_) public {
        if (token0 != address(0) || token1 != address(0))
            revert AlreadyInitialized();
        token0 = token0_;
        token1 = token1_;
    }

    //burn LR-Token,撤回流动性
    function burn(
        address to
    ) public returns (uint256 amount0, uint256 amount1) {
        //获取存储的货币余额
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        //获取用户,转入合约要销毁的流动性代币
        uint256 liquidity = balanceOf[address(this)];
        //按照持有的流动性代币计算应得的代币份额
        //((2 ether - 1000) * 3 ether))/2
        amount0 = (liquidity * balance0) / totalSupply;
        emit BurnValue(liquidity, balance0, totalSupply);
        amount1 = (liquidity * balance1) / totalSupply;
        emit BurnValue(liquidity, balance1, totalSupply);

        if (amount0 == 0 || amount1 == 0) {
            revert InsufficientLiquidityBurned();
        }
        //销毁用户转入合约中的所有流动性代币
        _burn(address(this), liquidity);

        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        //更新pair合约 token总额
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    //token转换
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data //闪电贷参数
    ) public {
        //out的token不能为0
        if (amount0Out == 0 && amount1Out == 0) {
            revert InsufficientOutputAmount();
        }

        //获取币对合约记录的token总量
        (uint112 reserve0_, uint112 reserve1_, ) = getReserves();

        console.log(reserve0_, reserve1_);
        //提取的金额不能大于记录的总量
        if (amount0Out > reserve0_ || amount1Out > reserve1_) {
            revert InsufficientLiquidity();
        }

        //执行安全转账
        if (amount0Out > 0) {
            _safeTransfer(token0, to, amount0Out);
        }
        if (amount1Out > 0) {
            _safeTransfer(token1, to, amount1Out);
        }

        //闪电贷回调
        if (data.length > 0) {
            IZuniswapV2Callee(to).zuniswapV2Call(
                msg.sender,
                amount0Out,
                amount1Out,
                data
            );
        }

        //获取币对合约当权的tokens余额，计算恒定乘积x * y = k
        //提取后的tokens余额乘积不能小于记录的tokens余额乘积
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        /** 计算要存入多少币
         *  balance0 = reserve0 + amount0In - amout0Out
            balance1 = reserve1 + amount1In - amout1Out         
         * =>amountIn = balance - (reserve - amountOut)
         */
        uint256 amount0In = balance0 > reserve0 - amount0Out
            ? balance0 - (reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out
            ? balance1 - (reserve1 - amount1Out)
            : 0;
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();
        //减去手续费
        uint256 balance0Ajusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Ajusted = (balance1 * 1000) - (amount1In * 3);

        console.log(balance0, balance1, reserve0_, reserve1_);
        if (
            balance0Ajusted * balance1Ajusted <
            uint256(reserve0_) * uint256(reserve1_) * (1000 ** 2)
        ) {
            revert InvalidK();
        }
        //更新合约token的总量记录
        _update(balance0, balance1, reserve0_, reserve1_);

        emit Swap(msg.sender, amount0Out, amount1Out, to);
    }

    //安全转账方法
    //撤退流动性后，回退代币给用户
    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, value)
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }

    //update Pair Contract reserve
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 reserve0_,
        uint112 reserve1_
    ) private {
        //余额不能大于 uint112 max值
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert BalanceOverflow();
        }
        //时间加权平均价格计算(TWAP)
        //price0Cumulative = reserve1 / reserve0 * timeElapsed = 40000/10*5 = 20000 USDT
        //price1Cumulative = reserve0 / reserve1 * timeElapsed = 10/40000*5 = 0.00125 WETH
        unchecked {
            uint32 timeElapsed = uint32(block.timestamp) - blockTimestampLast;

            //更新Uniswap池的价格累积器（price accumulators）
            if (timeElapsed > 0 && reserve0_ > 0 && reserve1_ > 0) {
                price0CumulativeLast +=
                    uint256(UQ112x112.encode(reserve1_).uqdiv(reserve0_)) *
                    timeElapsed;
                price1CumulativeLast +=
                    uint256(UQ112x112.encode(reserve0_).uqdiv(reserve1_)) *
                    timeElapsed;
            }
        }
        //更新存储的Token总量
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);

        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }

    function sync() public {
        (uint112 reserve0_, uint112 reserve1_, ) = getReserves();
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0_,
            reserve1_
        );
    }

    //get pair contract reserve
    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }
}
