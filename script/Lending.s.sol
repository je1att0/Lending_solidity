// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "../src/UpsideAcademyLending.sol";

contract LendingScript is Script {
    UpsideAcademyLending public lending;

    function setUp() public {}

    function run() public {
        // vm.startBroadcast();

        // counter = new Counter();

        // vm.stopBroadcast();
    }
}
