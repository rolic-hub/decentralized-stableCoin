// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralisedStableCoin.sol";

contract DecentralisedStableCointTest is Test {
    DecentralizedStableCoin private s_decentralized;

    address public another_person = makeAddr("Another Person");

    function setUp() public {
        vm.prank(msg.sender);

        s_decentralized = new DecentralizedStableCoin();
    }

    function testName() public view {
        assert(
            keccak256(abi.encodePacked(s_decentralized.name()))
                == keccak256(abi.encodePacked("DecentralizedStableCoin"))
        );
    }

    function testCanMintToken() public {
        vm.prank(msg.sender);
        s_decentralized.mint(msg.sender, 2 ether);

        assert(s_decentralized.balanceOf(msg.sender) == 2 ether);
    }

    function testCanBurnToken() public {
        vm.prank(msg.sender);
        s_decentralized.mint(msg.sender, 2 ether);

        vm.prank(msg.sender);
        s_decentralized.burn(2 ether);

        assert(s_decentralized.balanceOf(msg.sender) == 0);
    }

    function testFail_onlyOwnerCanMint() public {
        vm.prank(another_person);
        s_decentralized.mint(msg.sender, 2 ether);

        assert(s_decentralized.balanceOf(another_person) == 0);
    }

    function testFail_onlyOwnerCanBurn() public {
        vm.prank(another_person);
        s_decentralized.mint(another_person, 2 ether);

        vm.prank(another_person);
        s_decentralized.burn(2 ether);
    }
}
