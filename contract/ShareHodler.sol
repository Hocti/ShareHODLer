// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NonRaribleToken.sol";

contract ShareHodler is NonRaribleToken {

    event PaymentReleased(address to, uint256 amount);
    event ERC20PaymentReleased(IERC20 indexed token, address to, uint256 amount);
	
    using SafeERC20 for IERC20;

    //var 

    struct tokenInfo{
        uint unit;
        uint share;
        uint totalFeeRedeemed;
        uint phase;//immutable
        bool stockLegal;//immutable
    }

    struct phaseInfo{
        uint pastShare;
        uint totalShare;

        uint endUnit;
        uint totalUnit;
        uint totalFee;
        uint endTime;
    }

    mapping (uint => phaseInfo) public phaseInfoList;

    mapping (uint => tokenInfo) public tokenInfoList;

    mapping (uint => mapping (uint => bool)) public redeemedPhase;

    uint constant minUnitPerPhase=10;

    uint public currentPhase=1;
    uint public totalFeeRedeemed=0;
    
    uint public nextPhaseDurationTime;
    uint public nextPhaseMaxUnit;
    uint public eachPhaseShareRemain;

    //contract owner

    constructor(
        string memory name_, string memory symbol_,
        bool _buyWithETH,
        address _buyToken,
        address _creator,
        uint _creatorShare
    ) NonRaribleToken(name_, symbol_,_buyWithETH,_buyToken,_creator,_creatorShare,0){

    }

    function constructor2(
        uint _newPrice,
        uint _phaseDurationTime,
        uint _nextPhaseMaxUnit,
        uint _eachPhaseShareRemain
    ) external onlyCreator {
        require(price==0,"price must be 0");

        setPrice(_newPrice);

        //require(_priceChangeFreezeDuration>=86400,"price change at least one day");
        //priceChangeFreezeDuration=_priceChangeFreezeDuration;
        
        //end phase
        require(_phaseDurationTime>=86400,"each phase at least one day");
        require(_phaseDurationTime<=86400*60,"each phase at most 60 day");
        require(_nextPhaseMaxUnit>=minUnitPerPhase,"too low");
        nextPhaseDurationTime=_phaseDurationTime;
        nextPhaseMaxUnit=_nextPhaseMaxUnit;

        //change phase
        require(_eachPhaseShareRemain<=5000,"old phase share too high");
        require(_eachPhaseShareRemain>=1,"old phase share too low");
        eachPhaseShareRemain=_eachPhaseShareRemain;

        //* Phase1,make Creator NFT
    }

    //buyer

    function _mintUnit(
        uint unit,
        uint share,
        uint phase,
        bool stockLegal
    ) internal returns (uint newTokenId){
        newTokenId=mintNext();
        tokenInfoList[newTokenId]=tokenInfo({
            unit:unit,
            share:share,
            totalFeeRedeemed:0,
            phase:phase,
            stockLegal:stockLegal
        });
    }

    function buy(uint _unit,bool _stockLegal) public payable returns (uint newTokenId){
        require(price>0,"not ready for sell");
        require(!_stockLegal || _unit==1 ,"stockLegal place albe to buy 1 unit only");
        require(_unit>0,"unit must > 0");

        //(uint _price,uint share)=checkPrice(_unit,_stockLegal);
        uint fee=price*_unit;
        uint share=0;
        if(!_stockLegal){
            share=_unit;//*
        }

        pay(fee);

        newTokenId=_mintUnit(_unit,share,currentPhase,_stockLegal);

        phaseInfoList[currentPhase].totalShare+=share==0?1:share;
        phaseInfoList[currentPhase].totalUnit+=_unit;
        phaseInfoList[currentPhase].totalFee+=fee;

        if(phaseInfoList[currentPhase].totalUnit>=phaseInfoList[currentPhase].endUnit){
            endPhase();
        }
    }
    
    function buy() public override payable returns (uint newTokenId){
        return buy(1,false);
    }

    function split(uint _tokenID,uint _unit,address _toAddress) external onlyTokenOwner(_tokenID) returns (uint newTokenId){
        require(_unit>=1 && _unit<=tokenInfoList[_tokenID].unit+1,"_unit not enough");
        require(tokenInfoList[_tokenID].totalFeeRedeemed==0,"token started redeem");
        require(_toAddress!=address(0),"address can not be 0");

        uint _splitShare=(tokenInfoList[_tokenID].share*_unit)/tokenInfoList[_tokenID].unit;
        newTokenId=_mintUnit(
            _unit,
            _splitShare,
            tokenInfoList[_tokenID].phase,
            tokenInfoList[_tokenID].stockLegal
        );

        tokenInfoList[_tokenID].unit-=_unit;
        tokenInfoList[_tokenID].share-=_splitShare;
    }

    //view 

    function checkRedeem(uint _tokenID,uint _phase) public view returns (uint){
        if( redeemedPhase[_tokenID][_phase] ||
            tokenInfoList[_tokenID].share==0){
            return 0;
        }

        uint phasePassed=_phase-tokenInfoList[_tokenID].phase;
        uint share=tokenInfoList[_tokenID].share;

        if(phasePassed>0){
            for(uint i=0;i<phasePassed;i++){
                share;//*
            }
        }
        return (phaseInfoList[_phase].totalFee*share)/phaseInfoList[_phase].totalShare;
    }

    function checkRedeemAll(uint _tokenID) public view returns (uint totalFee){
        for(uint i=1;i<currentPhase;i++){
            totalFee+=checkRedeem(_tokenID,i);
        }
    }

    //hodler

    function redeem(uint _tokenID,uint _phase) external payable onlyTokenOwner(_tokenID) returns (uint){
        endPhase();
        uint fee=checkRedeem(_tokenID,_phase);
        require(fee>0,"nothing to redeem");
        redeemedPhase[_tokenID][_phase]=true;
        
        payToAddress(payable(_msgSender()),_tokenID,fee);
        return fee;
    }

    function redeemAll(uint _tokenID) external payable onlyTokenOwner(_tokenID) returns (uint){
        endPhase();
        uint totalFee=0;

        for(uint _phase=1;_phase<currentPhase;_phase++){
            uint fee=checkRedeem(_tokenID,_phase);
            if(fee>0){
                totalFee+=fee;
                redeemedPhase[_tokenID][_phase]=true;
            }
        }

        payToAddress(payable(_msgSender()),_tokenID,totalFee);
        return totalFee;
    }
    
    //internal

    function checkPhaseEnd() internal view returns (bool ended,bool soldAll,bool timeout){
        timeout=block.timestamp>phaseInfoList[currentPhase].endTime;
        soldAll=phaseInfoList[currentPhase].totalUnit>=phaseInfoList[currentPhase].endUnit;
        ended=timeout || soldAll;
    }

    function endPhase() internal{
        (bool ended,bool soldAll,bool timeout)=checkPhaseEnd();
        if(ended){
            if(timeout){//timeout
                uint lastUnit=phaseInfoList[currentPhase].totalUnit;
                nextPhaseMaxUnit=lastUnit>=minUnitPerPhase?lastUnit:minUnitPerPhase;
            }else if(soldAll){//soldAll
                nextPhaseMaxUnit=nextPhaseMaxUnit*(10000+10000*(phaseInfoList[currentPhase].endTime-block.timestamp)/nextPhaseDurationTime)/10000;
            }
            currentPhase++;
            uint pastShare=0;//*
            phaseInfoList[currentPhase]=phaseInfo(
                pastShare,
                pastShare,
                nextPhaseMaxUnit,
                0,
                0,
                block.timestamp+nextPhaseDurationTime
            );
        }
    }

    function payToAddress(address payable account,uint _tokenID,uint fee) internal {
        tokenInfoList[_tokenID].totalFeeRedeemed+=fee;
        if(buyWithETH){
            Address.sendValue(account, fee);
            emit PaymentReleased(account, fee);
        }else{
            SafeERC20.safeTransfer(buyToken, account, fee);
            emit ERC20PaymentReleased(buyToken, account, fee);
        }
        totalFeeRedeemed+=fee;
    }
    
}
