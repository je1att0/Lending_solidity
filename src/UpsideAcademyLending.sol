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
    mapping (address => uint256) public ETHcollateral;
    mapping (address => uint256) public limit;
    mapping (address => bool) public Borrowed;
    uint public lendingPeriod;
    

    constructor(IPriceOracle _priceOracle, address _usdcAddress) {
        upsideOracle = _priceOracle;
        usdc = ERC20(_usdcAddress); 
    }

    function initializeLendingProtocol(address _usdcAddress) public payable {
        deposit(_usdcAddress, msg.value);
        deposit(address(0x0), msg.value);
    }

    function deposit (address _tokenAddress, uint256 _amount) public payable {
        if (_tokenAddress == address(0x0)) {
            require(msg.value > 0, "Empty TxValue");
            require(msg.value == _amount, "Insufficient Value");
            depositETH();
        }
        else {
            ERC20 token = ERC20(_tokenAddress);
            require(token.allowance(msg.sender, address(this)) >= _amount, "ERC20: insufficient allowance");
            depositUSDC(_amount);
        }
    }

    function depositETH() public payable {
        payable(address(this)).transfer(msg.value);
        ETHcollateral[msg.sender] += msg.value;
    }

    function depositUSDC(uint256 _amount) public payable {
        usdc.transferFrom(msg.sender, address(this), _amount);
    }

    function borrow (address _tokenAddress, uint256 _amount) public payable {
        uint ETHprice = upsideOracle.getPrice(address(0x0));
        uint USDCprice = upsideOracle.getPrice(address(usdc));
        // eth : usdc = 1339 : 1
        if (!Borrowed[msg.sender]) {
            limit[msg.sender] = (ETHprice/USDCprice)*ETHcollateral[msg.sender] - 2000 ether; //1339*deposit
            Borrowed[msg.sender] = true;
            lendingPeriod = block.number;
        }
        require(usdc.balanceOf(address(this))*_amount >= limit[msg.sender], "Insufficient USDC supply");
        require(limit[msg.sender] > 0, "Insufficient ETH collateral");
        usdc.transfer(msg.sender, _amount);
        limit[msg.sender] = limit[msg.sender] - _amount;
    }

    function repay (address _tokenAddress, uint _amount) public payable {
        uint interest = block.number - lendingPeriod;
        uint amount = _amount - interest;
        deposit(_tokenAddress, amount);
        limit[msg.sender] = limit[msg.sender] + amount;
    }

    function withdraw (address _tokenAddress, uint256 _amount) public payable {
        uint ETHprice = upsideOracle.getPrice(address(0x0));
        uint USDCprice = upsideOracle.getPrice(address(usdc));
        uint interest = block.number - lendingPeriod;
        uint amount = _amount + interest;
        if (!Borrowed[msg.sender]) {
            limit[msg.sender] = (ETHprice/USDCprice)*ETHcollateral[msg.sender] - 2000 ether; //1339*deposit
        }
        // require(limit[msg.sender] > 0, "Insufficient ETH collateral");
        
        require(amount <= ETHcollateral[msg.sender], "Insufficient ETH balance");
        payable(msg.sender).transfer(amount);
        ETHcollateral[msg.sender] = ETHcollateral[msg.sender] - amount;
    }

    function getAccruedSupplyAmount(address _tokenAddress) public view returns (uint256) {

    }

    function liquidate (address _userAddress, address _tokenAddress, uint256 _amount) public payable {

    }

    receive() external payable {

    }
}
