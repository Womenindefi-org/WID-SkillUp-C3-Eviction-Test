// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// AUDIT FIXES:
/// - Uses SafeERC20 for secure transfers
/// - Adds ReentrancyGuard to claim fn
/// - Pausing/Ownership controls for emergency
/// - Allows users to add to existing stake
/// - rewardRate/stakingPeriod can be updated by owner

contract StudyTokenStaking is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable studyToken;
    uint256 public rewardRate;
    uint256 public stakingPeriod = 30 days;

    struct Stake {
        uint256 amount;
        uint256 stakedAt;
        uint256 unlockedAt;
        bool claimed;
    }

    mapping(address => Stake) public stakes;

    event Staked(address indexed user, uint256 amount, uint256 indexed unlockedAt);
    event Claimed(address indexed user, uint256 amount, uint256 reward);
    event StakeIncreased(address indexed user, uint256 newAmount, uint256 resetUnlock);
    event ParametersChanged(uint256 newRewardRate, uint256 newStakingPeriod);

    constructor(IERC20 _studyToken, uint256 _rewardRate, address _owner) Ownable(_owner) {
        studyToken = _studyToken;
        rewardRate = _rewardRate;
    }

    // ADDED: Owner can update reward rate
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        rewardRate = _rewardRate;
        emit ParametersChanged(rewardRate, stakingPeriod);
    }
    // ADDED: Owner can update staking period
    function setStakingPeriod(uint256 _stakingPeriod) external onlyOwner {
        stakingPeriod = _stakingPeriod;
        emit ParametersChanged(rewardRate, stakingPeriod);
    }
    // ADDED: Pause staking/claiming in emergency
    function pause() public onlyOwner { _pause(); }
    function unpause() public onlyOwner { _unpause(); }

    function stake(uint256 _amount) external whenNotPaused {
        require(_amount > 0, "Cannot stake zero");
        // FIX: Allow to add to stake, resets unlock
        Stake storage st = stakes[msg.sender];
        if (st.amount > 0 && !st.claimed) {
            // Add to existing position
            st.amount += _amount;
            st.stakedAt = block.timestamp;
            st.unlockedAt = block.timestamp + stakingPeriod;
            emit StakeIncreased(msg.sender, st.amount, st.unlockedAt);
        } else {
            // New stake or re-stake
            stakes[msg.sender] = Stake({
                amount: _amount,
                stakedAt: block.timestamp,
                unlockedAt: block.timestamp + stakingPeriod,
                claimed: false
            });
            emit Staked(msg.sender, _amount, block.timestamp + stakingPeriod);
        }
        studyToken.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function claim() external nonReentrant whenNotPaused {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No stake");
        require(block.timestamp >= userStake.unlockedAt, "Not unlocked");
        require(!userStake.claimed, "Already claimed");
        // reward formula unchanged
        uint256 reward = (userStake.amount * rewardRate * stakingPeriod) / (365 days * 10000);
        uint256 total = userStake.amount + reward;
        userStake.claimed = true;
        studyToken.safeTransfer(msg.sender, total);
        emit Claimed(msg.sender, userStake.amount, reward);
    }
}
// AUDIT DOCS:
// - Used SafeERC20 for all transfers to prevent non-standard ERC20 issues.
// - Added ReentrancyGuard for claim().
// - Added Pausable (owner) for emergency stops.
// - Allow users to add to ongoing stake (resets timer) for flexibility.
// - Added admin functions for updating rate/period.
// - Documented vulnerabilities in code comments.   