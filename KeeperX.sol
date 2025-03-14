// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract KeeperCoinRebase is ReentrancyGuard {
    // Token details
    string public constant name = "KeeperX";
    string public constant symbol = "KPX";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    uint256 private constant TOTAL_GONS = INITIAL_TOTAL_SUPPLY * 54;
    uint256 public gonsPerFragment;

    // Supply constants
    uint256 public constant INITIAL_TOTAL_SUPPLY = 18_500_000 * 10**18;
    uint256 public constant FOUNDER_ALLOCATION = 1_200_000 * 10**18;
    uint256 public constant FREE_CIRCULATION_ALLOCATION = 13_250_000 * 10**18;
    uint256 public constant STAKING_POOL_ALLOCATION = 1_800_000 * 10**18;
    uint256 public constant LIQUIDITY_POOL_ALLOCATION = 2_250_000 * 10**18;

    // Balances and allowances
    mapping(address => uint256) private _gonBalances;
    mapping(address => mapping(address => uint256)) public allowance;

    // Returns the adjusted balance of an account
    function balanceOf(address account) public view returns (uint256) {
        if (totalSupply == 0 || gonsPerFragment == 0) return 0;
        return _gonBalances[account] / gonsPerFragment;
    }

    // Addresses
    address public immutable founder = 0x35e6A761F7E7fE74117a5e099ECaF0e6f0a58A1F;
    
    // Main liquidity pair address – a single pair address used for automatic operations.
    address public pairAddress;

    // Getter for the main pair address
    function getPairAddress() external view returns (address) {
        return pairAddress;
    }

    // Only founder can set the main pair address (one-time update)
    function setPairAddress(address _pair) external {
        require(msg.sender == founder, "Only founder can set pair address");
        require(_pair != address(0), "Invalid address");
        pairAddress = _pair;
    }

    // Fee parameters (percentage values remain unchanged)
    uint256 constant TIER1_THRESHOLD = 10_000 * 10**18;
    uint256 constant TIER2_THRESHOLD = 100_000 * 10**18;
    uint256 constant TIER1_BURN_RATE = 50;    // 0.5%
    uint256 constant TIER1_POOL_RATE = 50;    // 0.5%
    uint256 constant TIER2_BURN_RATE = 25;    // 0.25%
    uint256 constant TIER2_POOL_RATE = 25;    // 0.25%
    uint256 constant TIER3_BURN_RATE = 10;    // 0.1%
    uint256 constant TIER3_POOL_RATE = 10;    // 0.1%

    // Calculates the burn fee and pool fee for a transfer amount
    function _getTransferFees(uint256 amount) internal pure returns (uint256 burnFee, uint256 poolFee) {
        uint256 burnRate;
        uint256 poolRate;
        if (amount <= TIER1_THRESHOLD) {
            burnRate = TIER1_BURN_RATE;
            poolRate = TIER1_POOL_RATE;
        } else if (amount <= TIER2_THRESHOLD) {
            burnRate = TIER2_BURN_RATE;
            poolRate = TIER2_POOL_RATE;
        } else {
            burnRate = TIER3_BURN_RATE;
            poolRate = TIER3_POOL_RATE;
        }
        unchecked {
            burnFee = (amount * burnRate) / 10000;
            poolFee = (amount * poolRate) / 10000;
        }
    }

    // Liquidity and rewards management
    uint256 public stakingPool;
    mapping(address => uint256) public liquidityProviderBalance;
    uint256 public totalLiquidityProvided;
    uint256 public totalLiquidityRewards;
    address[] public liquidityProviders;
    mapping(address => bool) public isLiquidityProvider;
    mapping(address => uint256) public liquidityProviderDepositTime;
    mapping(address => uint256) public claimedLiquidityRewards;
    
    uint256 public constant INITIAL_LIQUIDITY_POOL = 2_250_000 * 10**18;
    uint256 public liquidityPoolRemaining = INITIAL_LIQUIDITY_POOL;
    uint256 public burnRewardsPool;
    
    uint256 public constant REWARD_CLAIM_COOLDOWN = 7 days;
    mapping(address => uint256) public lastRewardClaimTime;

    // Allows liquidity providers to claim their rewards
    function claimLiquidityRewards() external nonReentrant {
        require(block.timestamp >= lastRewardClaimTime[msg.sender] + REWARD_CLAIM_COOLDOWN, "Reward claim cooldown active");
        uint256 reward = calculateLiquidityRewards(msg.sender) - claimedLiquidityRewards[msg.sender];
        require(reward > 0, "No reward available to claim");
        require(reward <= balanceOf(address(this)), "Insufficient reward token balance");
        claimedLiquidityRewards[msg.sender] += reward;
        lastRewardClaimTime[msg.sender] = block.timestamp;
        _transferNoFee(address(this), msg.sender, reward);
    }

    // Calculates liquidity rewards based on provider's share of liquidity
    function calculateLiquidityRewards(address provider) public view returns (uint256) {
        if (totalLiquidityProvided == 0) return 0;
        return (totalLiquidityRewards * liquidityProviderBalance[provider]) / totalLiquidityProvided;
    }

    // Automatically distributes rewards to liquidity providers
    function _autoDistributeRewards() internal {
        uint256 numProviders = liquidityProviders.length;
        if (numProviders > 0 && totalLiquidityProvided > 0 && liquidityPoolRemaining > 0) {
            for (uint256 i = 0; i < numProviders; i++) {
                address provider = liquidityProviders[i];
                uint256 providerBalance = liquidityProviderBalance[provider];
                uint256 providerReward = (liquidityPoolRemaining * 10 * providerBalance) /
                    (numProviders * 1000 * totalLiquidityProvided);
                if (providerReward > 0 && providerReward <= liquidityPoolRemaining) {
                    liquidityPoolRemaining -= providerReward;
                    _gonBalances[provider] += providerReward * gonsPerFragment;
                    emit Transfer(address(this), provider, providerReward);
                }
            }
        }
    }

    // Transfers tokens without fee deduction
    function _transferNoFee(address from, address to, uint256 amount) internal {
        require(balanceOf(from) >= amount, "Insufficient balance");
        uint256 gonAmount = amount * gonsPerFragment;
        _gonBalances[from] -= gonAmount;
        _gonBalances[to] += gonAmount;
        emit Transfer(from, to, amount);
    }

    // Liquidity deposit function
    function depositLiquidity(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        _transferNoFee(msg.sender, address(this), amount);
        liquidityProviderBalance[msg.sender] += amount;
        totalLiquidityProvided += amount;
        if (liquidityProviderDepositTime[msg.sender] == 0) {
            liquidityProviderDepositTime[msg.sender] = block.timestamp;
            liquidityProviders.push(msg.sender);
            isLiquidityProvider[msg.sender] = true;
        }
    }

    // Liquidity withdrawal function
    function withdrawLiquidity(uint256 amount) external nonReentrant {
        require(liquidityProviderBalance[msg.sender] >= amount, "Insufficient liquidity balance");
        liquidityProviderBalance[msg.sender] -= amount;
        totalLiquidityProvided -= amount;
        _transferNoFee(address(this), msg.sender, amount);
    }

    // Staking mechanism
    struct Stake {
        uint256 amount;
        uint256 startTime;
    }
    mapping(address => Stake) public stakes;

    // Event declarations (each event is declared only once)
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Rebase(uint256 previousSupply, uint256 newSupply);
    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event Unstaked(address indexed user, uint256 stakedAmount, uint256 reward);
    event RewardClaimed(address indexed staker, uint256 reward);
    
    uint256 public constant MIN_LOCK_PERIOD_FOR_BALINAS = 30 days;
    uint256 public numStakers;
    uint256 public constant MAX_STAKERS = 1000;
    uint256 public constant BASE_APR = 10;

    // Calculates the Annual Percentage Rate (APR) for staking rewards
    function _calculateAPR() public view returns (uint256) {
        uint256 _stakingPool = stakingPool;
        uint256 _numStakers = numStakers;
        uint256 _totalSupply = totalSupply;
        if (_stakingPool == 0 || _numStakers == 0) return BASE_APR;
        uint256 aprFactor = (_stakingPool * _numStakers) / (_totalSupply * MAX_STAKERS);
        unchecked {
            return BASE_APR * (1 - aprFactor);
        }
    }

    // Stake tokens into the contract
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake zero");
        _transferNoFee(msg.sender, address(this), amount);
        if (stakes[msg.sender].amount == 0) {
            numStakers++;
        }
        stakes[msg.sender].amount += amount;
        stakes[msg.sender].startTime = block.timestamp;
        emit Staked(msg.sender, amount, block.timestamp);
    }

    // Unstake tokens from the contract
    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot unstake zero");
        require(stakes[msg.sender].amount >= amount, "Insufficient staked amount");
        require(block.timestamp >= stakes[msg.sender].startTime + MIN_LOCK_PERIOD_FOR_BALINAS, "Stake locked");
        stakes[msg.sender].amount -= amount;
        if (stakes[msg.sender].amount == 0) {
            numStakers--;
        }
        _transferNoFee(address(this), msg.sender, amount);
        emit Unstaked(msg.sender, amount, 0);
    }

    // Calculate staking rewards for a given staker
    function calculateStakingReward(address staker) public view returns (uint256) {
        Stake storage s = stakes[staker];
        if (s.amount == 0) return 0;
        uint256 elapsed = block.timestamp - s.startTime;
        uint256 apr = _calculateAPR();
        uint256 reward = (s.amount * apr * elapsed) / (365 days * 100);
        if (reward > stakingPool) reward = stakingPool;
        return reward;
    }

    // Claim staking rewards
    function claimStakingReward() external nonReentrant {
        uint256 reward = calculateStakingReward(msg.sender);
        require(reward > 0, "No reward available");
        stakes[msg.sender].startTime = block.timestamp;
        stakingPool -= reward;
        _transferNoFee(address(this), msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    // Auto-rebase mechanism: periodically reduces the total supply
    uint256 public constant REBASE_INTERVAL = 30 days;
    uint256 public lastRebaseTime;

    function _autoRebase() internal {
        if (block.timestamp >= lastRebaseTime + REBASE_INTERVAL) {
            uint256 _prevSupply = totalSupply;
            unchecked {
                uint256 _burnAmount = (_prevSupply * 1667) / 1000000;
                uint256 _liquidityReward = _burnAmount / 10;
                totalSupply = _prevSupply - _burnAmount;
                gonsPerFragment = TOTAL_GONS / totalSupply;
                liquidityPoolRemaining += _liquidityReward;
            }
            lastRebaseTime = block.timestamp;
            emit Rebase(_prevSupply, totalSupply);
        }
    }

    // Transaction limits and anti-bot mechanism
    mapping(address => uint256) public lastTransactionBlock;
    uint256 public constant MAX_TRANSACTIONS_PER_HOUR = 10;
    mapping(address => uint256) public lastTransferTime;
    uint256 public constant cooldownTime = 60;
    mapping(address => uint256) public transactionCount;
    mapping(address => uint256) public transactionCountResetTime;
    mapping(address => uint8) public warnings;
    mapping(address => uint256) public lastWarningTime;
    
    // Transfer event is already declared above.

    modifier oneTxPerBlock(address user) {
        require(lastTransactionBlock[user] < block.number, "Only one transaction per block allowed");
        lastTransactionBlock[user] = block.number;
        _;
    }

    function _checkAntiBot(address user) internal {
        if (block.timestamp >= transactionCountResetTime[user] + 1 hours) {
            transactionCount[user] = 0;
            transactionCountResetTime[user] = block.timestamp;
            warnings[user] = 0;
        }
        transactionCount[user]++;
        if (transactionCount[user] > MAX_TRANSACTIONS_PER_HOUR && warnings[user] < 1) {
            warnings[user]++;
            lastWarningTime[user] = block.timestamp;
        }
    }
    
    function _checkWarningRestriction(address user) internal view {
        if (warnings[user] >= 1) {
            require(block.timestamp >= lastWarningTime[user] + 24 hours, "Transaction restricted due to prior warning");
        }
    }
    
    function getCooldownTime() public view returns (uint256) {
        uint256 baseCooldown = 60;
        uint256 dynamicCooldown = (baseCooldown * INITIAL_TOTAL_SUPPLY) / totalSupply;
        return dynamicCooldown < 60 ? 60 : (dynamicCooldown > 900 ? 900 : dynamicCooldown);
    }

    // Transfer functionality with auto-rebase, anti-bot, and fee calculation
    function _transferInternal(
        address from,
        address to,
        uint256 amount
    ) internal oneTxPerBlock(from) {
        require(to != address(0), "Invalid recipient");
        require(balanceOf(from) >= amount, "Insufficient balance");

        _checkAntiBot(from);
        _checkWarningRestriction(from);

        uint256 gonAmount = amount * gonsPerFragment;
        (uint256 burnFee, uint256 poolFee) = _getTransferFees(amount);
        uint256 netAmount = amount - burnFee - poolFee;
        require(netAmount > 0, "Amount too low after fees");

        uint256 gonNet = netAmount * gonsPerFragment;
        _gonBalances[from] -= gonAmount;
        _gonBalances[to] += gonNet;

        totalSupply -= burnFee;
        emit Transfer(from, address(0), burnFee);

        stakingPool += poolFee;
        emit Transfer(from, address(this), poolFee);
        emit Transfer(from, to, netAmount);

        lastTransferTime[from] = block.timestamp;

        _autoRebase();
        _autoDistributeRewards();
    }
    
    function transfer(address to, uint256 amount) public nonReentrant returns (bool) {
        _transferInternal(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public nonReentrant returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Allowance exceeded");
        allowance[from][msg.sender] -= amount;
        _transferInternal(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) public nonReentrant returns (bool) {
        require(spender != address(0), "Invalid spender");
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    // safeApprove is a simple wrapper for approve
    function safeApprove(address spender, uint256 amount) public returns (bool) {
        return approve(spender, amount);
    }

    // Additional functions
    function getAllowedSaleLimit() public view returns (uint256) {
        if (msg.sender == founder) return type(uint256).max;
        if (totalSupply == 0 || totalLiquidityProvided == 0) return 0;
        uint256 liquidityRatio = (totalLiquidityProvided * 100) / totalSupply;
        if (liquidityRatio >= 10) return (totalLiquidityProvided * 10) / 100;
        else if (liquidityRatio >= 7) return (totalLiquidityProvided * 25) / 100;
        else if (liquidityRatio >= 5) return (totalLiquidityProvided * 15) / 100;
        else if (liquidityRatio >= 3) return (totalLiquidityProvided * 10) / 100;
        else return (totalLiquidityProvided * 5) / 100;
    }
    
    function getContractState() public view returns (
        uint256 _totalSupply,
        uint256 _lastRebaseTime,
        uint256 _stakingPool,
        uint256 _cooldownTime,
        address _founder
    ) {
        return (totalSupply, lastRebaseTime, stakingPool, cooldownTime, founder);
    }
    
    // Constructor: Initialize state – main pair address is set via constructor parameter
    constructor(address _pairAddress) {
        require(_pairAddress != address(0), "Invalid pair address");
        pairAddress = _pairAddress;
        totalSupply = INITIAL_TOTAL_SUPPLY;
        gonsPerFragment = TOTAL_GONS / totalSupply;
    
        uint256 founderAllocation = FOUNDER_ALLOCATION + FREE_CIRCULATION_ALLOCATION;
        _gonBalances[founder] = founderAllocation * gonsPerFragment;
    
        _gonBalances[address(this)] = (LIQUIDITY_POOL_ALLOCATION * TOTAL_GONS) / totalSupply;
    
        stakingPool = STAKING_POOL_ALLOCATION;
        totalLiquidityProvided = 0;
        totalLiquidityRewards = 0;
        lastRebaseTime = block.timestamp;
    }
}
