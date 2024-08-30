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
    event label(string value);
    struct LoanAccount {
        uint256 depositedETH;
        uint256 depositedUSDC;
        uint256 borrowedUSDC;
        uint256 lastDepositBlock;
        uint256 lastBorrowedBlock;
        uint256 limitLeft;
        uint256 liquidableLeft;
        bool liquidable;
        uint256 interest;
    }

    mapping(address => LoanAccount) private accounts;

    IPriceOracle public upsideOracle;
    ERC20 public usdc;

    address[] public accountAddr;

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
            if (accounts[msg.sender].depositedUSDC == 0) {
                accountAddr.push(msg.sender);
            }
            accounts[msg.sender].lastDepositBlock = block.number;
            accounts[msg.sender].depositedUSDC += _amount;
            usdc.transferFrom(msg.sender, address(this), _amount);
        } else{
            require(msg.value > 0, "Empty TxValue");
            require(msg.value == _amount, "Insufficient Value");
            if (accounts[msg.sender].depositedETH == 0) {
                accountAddr.push(msg.sender);
            }
            accounts[msg.sender].lastDepositBlock = block.number;
            accounts[msg.sender].depositedETH += msg.value;
            payable(address(this)).transfer(msg.value);
        }
    }

    function borrow (address _tokenAddress, uint256 _amount) public payable {
        uint ETHprice = upsideOracle.getPrice(address(0x0));
        uint USDCprice = upsideOracle.getPrice(address(usdc));
        LoanAccount memory borrowerAccount = updatedAccount(msg.sender);

        require(usdc.balanceOf(address(this))>0, "Insufficient USDC supply");
        require (borrowerAccount.limitLeft>=_amount, "Insufficient collateral");

        if (borrowerAccount.borrowedUSDC >= 100 ether) {
            borrowerAccount.liquidableLeft = borrowerAccount.borrowedUSDC*25/100;
        } else {
            borrowerAccount.liquidableLeft = borrowerAccount.borrowedUSDC;
        }

        borrowerAccount.borrowedUSDC += _amount;
        borrowerAccount.lastBorrowedBlock = block.number;
        usdc.transfer(msg.sender, _amount);
        accounts[msg.sender] = borrowerAccount;
    } 

    function updatedAccount(address _userAddress) public returns (LoanAccount memory account) {
        uint ETHprice = upsideOracle.getPrice(address(0x0));
        uint USDCprice = upsideOracle.getPrice(address(usdc));
        account = accounts[_userAddress];

        if ((((account.depositedETH/10**18)*ETHprice)/USDCprice)*1e18*LTV/100 >= account.borrowedUSDC) {
            account.limitLeft = (((account.depositedETH/10**18)*ETHprice)/USDCprice)*1e18*LTV/100-account.borrowedUSDC;
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
        distributeInterest();
        return accounts[msg.sender].depositedUSDC + accounts[msg.sender].interest;
        
    }

    function calTotalInterest () public returns (uint) {
        uint total_borrowed_usdc;
        uint day_elapsed;
        for (uint i=0;i<accountAddr.length;i++) {
            address borrowed_account = accountAddr[i];
            if (accounts[borrowed_account].borrowedUSDC > 0) {
                total_borrowed_usdc += accounts[borrowed_account].borrowedUSDC;
                emit label("total_borrowed_usdc");
                emit log(total_borrowed_usdc);
                day_elapsed = (block.number - accounts[borrowed_account].lastBorrowedBlock)*12/86400;
                emit label("day_elapsed");
                emit log(day_elapsed);
            }
        }
        uint totalInterest = calExponentialInterest(total_borrowed_usdc, day_elapsed);
        return totalInterest;
    }

    function calExponentialInterest(uint _total_borrowed_usdc, uint _day_elapsed) public returns (uint256) {
        // 1을 고정 소수점으로 변환
        bytes16 one = ABDKMathQuad.fromUInt(1);

        // 1/1000 을 고정 소수점으로 변환
        bytes16 fraction = ABDKMathQuad.div(ABDKMathQuad.fromUInt(1), ABDKMathQuad.fromUInt(1000));

        // 1 + 1/1000 을 계산
        bytes16 base = ABDKMathQuad.add(one, fraction);

        // (1 + 1/1000) ** 1000 을 계산
        bytes16 result = ABDKMathQuad.pow(base, ABDKMathQuad.fromUInt(_day_elapsed));

        result = ABDKMathQuad.mul(result, ABDKMathQuad.fromUInt(_total_borrowed_usdc));
        
        uint result_int = ABDKMathQuad.toUInt(result);

        return result_int;
    }

    function distributeInterest () public {
        uint interestAccrued = calTotalInterest();
        emit label("interestAccrued");
        emit log(interestAccrued);
        uint interestDistributed;
        for (uint i=0;i<accountAddr.length;i++) {
            address distributed_account = accountAddr[i];
            interestDistributed += accounts[distributed_account].interest;
        }

        uint interest_left = interestAccrued - interestDistributed;
        uint total_deposited_usdc;
        for (uint i=0;i<accountAddr.length;i++) {
            address deposited_account = accountAddr[i];
            total_deposited_usdc += accounts[deposited_account].depositedUSDC;
        }
        for (uint i=0;i<accountAddr.length;i++) {
            address interest_account = accountAddr[i];
            if (accounts[interest_account].depositedUSDC > 0) {
                accounts[interest_account].interest += interest_left*(accounts[interest_account].depositedUSDC/total_deposited_usdc);
            }
        }

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
