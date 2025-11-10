// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '../src/StudyTokenStaking.sol';


contract FakeStudyToken is ERC20 {
    constructor() ERC20('StudyToken', 'STUDY') {
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract StudyTokenStakingTest is Test {
    StudyTokenStaking staking;
    FakeStudyToken studyToken;
    address user1 = vm.addr(1);

    function setUp() public {
        studyToken = new FakeStudyToken();
        studyToken.mint(user1, 1000 ether);
        staking = new StudyTokenStaking(studyToken, 1000, address(this)); // 10% apr, test contract as owner
        studyToken.mint(address(staking), 100 ether); // Add extra for anticipated rewards

        vm.startPrank(user1);
        studyToken.approve(address(staking), 1000 ether);
        vm.stopPrank();
    }

    function testStakeAndClaimFullFlow() public {
        vm.startPrank(user1);
        staking.stake(100 ether);
        (, uint stakedAt, uint unlockTime,) = staking.stakes(user1);
        assertEq(stakedAt > 0, true);
        assertEq(unlockTime > stakedAt, true);

        // fast-forward time
        vm.warp(unlockTime);

        staking.claim();
        assertEq(studyToken.balanceOf(user1) > 900 ether, true);
        vm.stopPrank();
    }

    function testStakeTwiceIncreasesAmountAndResetsUnlock() public {
        vm.startPrank(user1);
        staking.stake(100 ether);
        (uint amount1, uint stakedAt1, uint unlock1, ) = staking.stakes(user1);
        uint256 firstUnlock = unlock1;

        vm.warp(block.timestamp + 1 days);
        staking.stake(50 ether);
        (uint amount2, uint stakedAt2, uint unlock2, ) = staking.stakes(user1);
        assertEq(amount2, 150 ether);
        assertEq(unlock2, stakedAt2 + staking.stakingPeriod());
        assertGt(unlock2, firstUnlock); // unlock gets reset
        vm.stopPrank();
    }

    function testCannotClaimEarly() public {
        vm.startPrank(user1);
        staking.stake(100 ether);
        vm.expectRevert();
        staking.claim();
        vm.stopPrank();
    }

    function testCannotClaimTwice() public {
        vm.startPrank(user1);
        staking.stake(100 ether);
        vm.warp(block.timestamp + 91 days);
        staking.claim();
        vm.expectRevert();
        staking.claim();
        vm.stopPrank();
    }
}