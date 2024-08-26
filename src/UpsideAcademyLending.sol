// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPriceOracle {
    function operator() external view returns (address);
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

contract UpsideAcademyLending {
    IPriceOracle public upsideOracle;
    ERC20 public usdc;

    constructor(IPriceOracle _upsideOracle, address _usdcAddress) {
        upsideOracle = IPriceOracle(_upsideOracle);
        usdc = ERC20(_tokenAddress); 
    }

    function initializeLendingProtocol(address _usdcAddress) public payable {
        
    }

    function deposit (address _tokenAddress, uint256 _amount) public payable {

    }

    function borrow (address _tokenAddress, uint256 _amount) public payable {

    }

    receive() external payable {

    }
}
