// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {MyGovernor} from "../src/MyGovernance.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGovernanceTest is Test {
    Box box;
    GovToken token;
    MyGovernor governor;
    TimeLock timelock;

    address public USER = makeAddr("user");

    uint256 private constant INITIAL_SUPPLY = 100 ether;
    uint256 private constant MIN_DELAY = 3600;
    uint256 private constant VOTING_DELAY = 7200;
    uint256 private constant VOTING_PERIOD = 50400;


    address[] proposers;
    address[] executors;

    uint256[] values;
    address[] targets;
    bytes[] calldatas;

    function setUp() external {
        token = new GovToken(INITIAL_SUPPLY);
        token.delegate(USER);

        vm.startPrank(USER);
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(token, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() external {
        vm.expectRevert();
        box.storeNumber(1);
    }

    function testGovernanceUpdateBox() external {
        uint256 newNumber = 600;
        string memory description = "to store new number in box contract";
        bytes memory encodedCallData = abi.encodeWithSignature("storeNumber(uint256)", newNumber);

        values.push(0);
        targets.push(address(box));
        calldatas.push(encodedCallData);

        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        console.log("Proposal State: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal State: ", uint256(governor.state(proposalId)));

        string memory reason = "Because am feeling dizzy";
        uint8 support = 1;
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, support, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);


        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        governor.execute(targets, values, calldatas, descriptionHash);

        console.log("Box Number: ", box.getNumber());
        assertEq(box.getNumber(), newNumber);
    }
}