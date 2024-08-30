// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPriceOracle {
    function operator() external view returns (address);
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

contract UpsideAcademyLending {
    event log(uint256 value);
    struct LoanAccount {
        uint256 depositedETH;
        uint256 borrowedUSDC;
        uint256 lastBlock;
        uint256 limitLeft;
        uint256 liquidableLeft;
        bool liquidable;
    }

    mapping(address => LoanAccount) private accounts;

    IPriceOracle public upsideOracle;
    ERC20 public usdc;

    uint LTV = 50;
    uint THRESHOLD = 75;
    uint256 constant public INTEREST = 1;


    constructor(IPriceOracle _priceOracle, address _usdcAddress) {
        upsideOracle = _priceOracle;
        usdc = ERC20(_usdcAddress); 
    }

    function initializeLendingProtocol(address _usdcAddress) public payable {
        deposit(_usdcAddress, msg.value);
        deposit(address(0x0), msg.value);
    }

    function deposit (address _tokenAddress, uint256 _amount) public payable {
        if(_tokenAddress != address(0x0)) {
            usdc.transferFrom(msg.sender, address(this), _amount);
        } else{
            require(msg.value > 0, "Empty TxValue");
            require(msg.value == _amount, "Insufficient Value");
            accounts[msg.sender].depositedETH += msg.value;
            payable(address(this)).transfer(msg.value);
        }
    }

    function borrow (address _tokenAddress, uint256 _amount) public payable {
        uint ETHprice = upsideOracle.getPrice(address(0x0));
        uint USDCprice = upsideOracle.getPrice(address(usdc));
        LoanAccount memory borrowerAccount = updatedAccount(msg.sender);

        borrowerAccount.borrowedUSDC += _amount;
        require(usdc.balanceOf(address(this))>0, "Insufficient USDC supply");
        require (borrowerAccount.limitLeft>=_amount, "Insufficient collateral");

        if (borrowerAccount.borrowedUSDC >= 100 ether) {
            borrowerAccount.liquidableLeft = borrowerAccount.borrowedUSDC*25/100;
        } else {
            borrowerAccount.liquidableLeft = borrowerAccount.borrowedUSDC;
        }
        usdc.transfer(msg.sender, _amount);
        accounts[msg.sender] = borrowerAccount;
    } 

    function updatedAccount(address _userAddress) public returns (LoanAccount memory account) {
        uint ETHprice = upsideOracle.getPrice(address(0x0));
        uint USDCprice = upsideOracle.getPrice(address(usdc));
        account = accounts[_userAddress];

        if (account.borrowedUSDC > 0) {
            uint256 blockDelta = block.number - account.lastBlock;
            uint256 interest = account.borrowedUSDC * blockDelta * INTEREST/1000;

            //account.depositedETH = (account.depositedETH >= interest) ? account.depositedETH - interest : 0;
        }

        account.lastBlock = block.number;
        emit log(account.depositedETH);
        emit log(ETHprice);
        emit log(account.borrowedUSDC);
        if ((((account.depositedETH/10**18)*ETHprice)/USDCprice)*1e18*LTV/100 >= account.borrowedUSDC) {
            emit log(3);
            account.limitLeft = (((account.depositedETH/10**18)*ETHprice)/USDCprice)*1e18*LTV/100-account.borrowedUSDC;
            emit log(account.limitLeft);
        } else {
            account.limitLeft = 0;
            account.liquidable = true;
        }
    }

    function repay (address _tokenAddress, uint _amount) public payable {
        LoanAccount memory account = updatedAccount(msg.sender);
        account.borrowedUSDC -= _amount;
        accounts[msg.sender] = account;

        usdc.transferFrom(msg.sender, address(this), _amount);
    }

    function withdraw (address _tokenAddress, uint256 _amount) public payable {
        uint ETHprice = upsideOracle.getPrice(address(0x0));
        uint USDCprice = upsideOracle.getPrice(address(usdc));
        LoanAccount memory account = updatedAccount(msg.sender);
        account.depositedETH -= _amount;
        if (account.borrowedUSDC > 0) {
            require(checkThreshold(account), "Undercollateralized $SEAGOLD loan");
            }   
        accounts[msg.sender] = account;

        payable(msg.sender).transfer(_amount);
    }
    

    function checkThreshold (LoanAccount memory _account) public returns (bool) {
        uint ETHprice = upsideOracle.getPrice(address(0x0));
        uint USDCprice = upsideOracle.getPrice(address(usdc));
        uint threshold = (ETHprice*_account.depositedETH)/(USDCprice*_account.borrowedUSDC);

        return threshold>THRESHOLD/100;
    }

    function getAccruedSupplyAmount(address _tokenAddress) public returns (uint256) {

    }

    function liquidate (address _userAddress, address _tokenAddress, uint256 _amount) public payable {
        LoanAccount memory account = updatedAccount(_userAddress);
        uint ETHprice = upsideOracle.getPrice(address(0x0));
        require(account.liquidable == true && account.limitLeft == 0, "Loan is not undercollateralized"); 
        require(account.liquidableLeft>=_amount, "Exceed amount to liquidate");
        
        uint liquidate_amount = (_amount/ETHprice)*10**18;
        account.depositedETH -= liquidate_amount;
        account.liquidableLeft -= _amount;
        
        payable(msg.sender).transfer(liquidate_amount);
        accounts[_userAddress] = account;
    }

    receive() external payable {

    }
}
