pragma solidity ^0.5.0;

import "./IERC20.sol";

interface pair{
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}
// 调用Uniswap路由合约里面的该函数，用来兑换币
interface uniRouter{
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

// 因为我们借到钱了，又马上还了，但是交易需要费用，所以我们最后借到的钱就不够还了，所以我们先存点钱，以满足还款
interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}
// 注意：以下数据都是生产数据（我们是要用ETH借USDT）
contract FlashLoan {
    
    address public router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    // 要在UniSwap这个配对合约里面借钱（我们是要用ETH借USDT）
    address public USDTETH = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // 借款数量
    uint256 public loanAmount;
    uint256 public ETHAmount;
    // 用于借款参数（只要有值就行）
    bytes _data = bytes("FlashLoan");
    event Balance(uint256 amount);
    
    constructor() public{
        safeApprove(WETH,router,uint(-1));
        safeApprove(USDT,router,uint(-1));
        safeApprove(USDC,router,uint(-1));
    }
    
    function deposit() public payable{
        ETHAmount = msg.value;
        IWETH(WETH).deposit.value(ETHAmount)();
        emit Balance(IERC20(WETH).balanceOf(address(this)));
    }
    
    /**
     * 该函数是在从Uniswap借钱时，Uniswap要回调的函数（该函数的作用就是你借到钱了想拿钱干啥）
     * 我们的逻辑是借到USDT了，就将USDT换成USDT，在换成ETH给它还回去
     */
    function uniswapV2Call(address account,uint256 amount0,uint256 amount1,bytes memory data) public{
        // 查询当前合约地址是否借到钱了，也就是查看当前合约地址余额是否有钱了
        uint256 balance = IERC20(USDT).balanceOf(address(this));
        // 触发事件
        emit Balance(balance);
        // 创建币兑换路径数组（就是币要从哪个币兑换成哪个币）（这个是将USDT兑换成USDC）
        address[] memory path1 = new address[](2);
        path1[0] = USDT;
        path1[1] = USDC;
        // 调用Uniswap路由合约里面的兑换函数，进行兑换币
        uint[] memory amounts1 = uniRouter(router).swapExactTokensForTokens(balance,uint(0),path1,address(this),block.timestamp+1800);
        emit Balance(amounts1[1]);
        
        // 创建币兑换路径数组（就是币要从哪个币兑换成哪个币）（这个是将USDC兑换成WETH）
        address[] memory path2 = new address[](2);
        path2[0] = USDC;
        path2[1] = WETH;
        // 调用Uniswap路由合约里面的兑换函数，进行兑换币
        uint[] memory amounts2 = uniRouter(router).swapExactTokensForTokens(amounts1[1],uint(0),path2,address(this),block.timestamp+1800);
        emit Balance(amounts2[1]);
        
        // 创建币兑换路径数组（就是币要从哪个币兑换成哪个币）（这个是将WETH兑换成USDT）
        address[] memory path3 = new address[](2);
        path3[0] = WETH;
        path3[1] = USDT;
        // 调用Uniswap路由合约里面的兑换函数，计算可兑换数量（注意：这个是为了计算我们要还多少钱）
        uint[] memory amounts3 = uniRouter(router).getAmountsIn(loanAmount,path3);
        emit Balance(amounts3[0]);
        // 还钱
        IERC20(WETH).transfer(USDTETH,amounts3[0]);
        
        emit Balance(ETHAmount - amounts3[0]);
    }
    
    /**
     * 调用Uniswap配对合约进行借款
     */
    function swap(uint256 _loanAmount) public {
        loanAmount = _loanAmount;
        // 我们用ETH借USDT
        // swap函数第一个是参数输出数量，对应的是ETH，我们填0；第二个参数是我们要借的USDT数量；第三个参数是收款地址；第四个参数是byte值数组，只要长度大于0就是借款
        pair(USDTETH).swap(uint(0),_loanAmount,address(this),_data);
    }
    
    // 调用ERC20币合约进行授权操作
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        // token.call（调用合约里面的某个函数）；abi.encodeWithSelector(0x095ea7b3, to, value) 编码合约里面的某个函数，以供token.call使用
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }
}
