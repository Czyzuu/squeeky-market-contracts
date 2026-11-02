// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {MockUSDC} from "../src/MockUSDC.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {DistanceOracle} from "../src/DistanceOracle.sol";
import {Exchange} from "../src/Exchange.sol";
import {NegRiskAdapter} from "../src/NegRiskAdapter.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
interface Vm {
    function warp(uint256) external;
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function addr(uint256) external returns(address);
    function sign(uint256,bytes32) external returns(uint8,bytes32,bytes32);
    function expectRevert() external;
    function chainId(uint256) external;
}
contract WheelTest is ERC1155Holder {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    MockUSDC u; ConditionalTokens c; DistanceOracle o; Exchange e; NegRiskAdapter adapter;
    address a; address b; bytes32 constant M = keccak256("day");
    function setUp() public {
        vm.chainId(31337); vm.warp(100000); a=vm.addr(11); b=vm.addr(22);
        u=new MockUSDC(); c=new ConditionalTokens(u); o=new DistanceOracle(c,address(this),address(this),10); c.setOracle(address(o));
        e=new Exchange(c,o,address(this),address(this),address(this)); adapter=new NegRiskAdapter(c);
        uint256[] memory empty=new uint256[](0); o.createMarket(M,99999,200000,1000,true,empty);
        fund(a); fund(b);
        vm.prank(a); c.splitPosition(M,1,10e6);
    }
    function fund(address who) internal { vm.startPrank(who); u.faucet(); u.approve(address(c),type(uint256).max); u.approve(address(e),type(uint256).max); c.setApprovalForAll(address(e),true); c.setApprovalForAll(address(adapter),true); vm.stopPrank(); }
    function order(address who,uint256 mask,uint8 side,uint256 price,uint256 nonce) internal view returns(Exchange.Order memory) { return Exchange.Order(who,c.tokenId(M,mask),side,price,20e6,190000,nonce,25,0); }
    function sig(Exchange.Order memory x,uint256 key) internal returns(bytes memory) { (uint8 v,bytes32 r,bytes32 s)=vm.sign(key,e.hashOrder(x)); return abi.encodePacked(r,s,v); }
    function matchPair(Exchange.Order memory x,Exchange.Order memory y,uint256 amount) public {
        Exchange.Match[] memory ms=new Exchange.Match[](1); ms[0]=Exchange.Match(x,sig(x,x.maker==a?11:22),y,sig(y,y.maker==a?11:22),amount); e.matchOrders(ms);
    }
    function testComplementaryPartialFillAndFees() public {
        Exchange.Order memory x=order(a,1,1,600000,1); Exchange.Order memory y=order(b,1,0,700000,2);
        uint256 before=u.balanceOf(a); matchPair(x,y,4e6);
        require(c.balanceOf(b,c.tokenId(M,1))==4e6); require(e.filled(e.hashOrder(x))==4e6);
        require(u.balanceOf(a)==before+2400000-6000); require(u.balanceOf(address(this))==12000);
        matchPair(x,y,2e6); require(e.filled(e.hashOrder(x))==6e6);
    }
    function testMint() public { uint256 before=c.locked(M); matchPair(order(a,1,0,600000,1),order(b,2,0,450000,2),5e6); require(c.locked(M)==before+5e6); require(c.balanceOf(b,c.tokenId(M,2))==5e6); }
    function testMerge() public {
        uint256 id=c.tokenId(M,2); vm.prank(a); c.safeTransferFrom(a,b,id,5e6,"");
        matchPair(order(a,1,1,600000,1),order(b,2,1,350000,2),5e6); require(c.locked(M)==5e6);
    }
    function testCancelNonceAndOrderAndReplay() public {
        Exchange.Order memory x=order(a,1,1,600000,1); Exchange.Order memory y=order(b,1,0,700000,2);
        vm.prank(a); e.cancelNonce(1); vm.expectRevert(); this.matchPair(x,y,1e6);
        x.nonce=3; vm.prank(a); e.cancel(x); vm.expectRevert(); this.matchPair(x,y,1e6);
        x.nonce=4; Exchange.Match[] memory ms=new Exchange.Match[](1); ms[0]=Exchange.Match(x,sig(x,11),y,sig(y,22),1e6);
        vm.chainId(11155111); vm.expectRevert(); e.matchOrders(ms);
    }
    function testOverfillAndPauseAndOperator() public {
        Exchange.Order memory x=order(a,1,1,600000,1); Exchange.Order memory y=order(b,1,0,700000,2);
        vm.expectRevert(); this.matchPair(x,y,21e6); e.setPaused(true); vm.expectRevert(); this.matchPair(x,y,1e6);
        e.setPaused(false); Exchange.Match[] memory empty=new Exchange.Match[](0); vm.prank(a); vm.expectRevert(); e.matchOrders(empty);
    }
    function testEarlyStrictAndDispute() public {
        vm.expectRevert(); o.report(M,1000,bytes32(0),false);
        o.report(M,1001,keccak256("data"),false); require(!o.isTradable(M)); vm.expectRevert(); o.finalize(M);
        o.overrideReport(M,1100,keccak256("corrected"),false); vm.warp(block.timestamp+10); o.finalize(M);
        uint256[] memory masks=new uint256[](2); masks[0]=1; masks[1]=2; vm.prank(a); c.redeemPositions(M,masks);
        require(c.claimable(a)==10e6); vm.prank(a); c.withdraw(); require(c.claimable(a)==0);
    }
    function testInvalidHalfPayout() public {
        vm.warp(200001); o.report(M,0,bytes32(0),true); vm.warp(200011); o.finalize(M);
        uint256[] memory masks=new uint256[](1); masks[0]=1; vm.prank(a); c.redeemPositions(M,masks); require(c.claimable(a)==5e6);
    }
    function testFokIocAndPostOnlyPolicies() public {
        Exchange.Order memory x=order(a,1,1,600000,1); Exchange.Order memory y=order(b,1,0,700000,2);
        y.timeInForce=2; y.size=5e6;
        vm.expectRevert(); this.matchPair(x,y,3e6); require(e.filled(e.hashOrder(x))==0);
        matchPair(x,y,5e6); require(e.filled(e.hashOrder(y))==5e6);
        y.nonce=3; y.timeInForce=3; matchPair(x,y,2e6); require(e.cancelled(e.hashOrder(y)));
        vm.expectRevert(); this.matchPair(x,y,1e6);
        y.nonce=4; y.timeInForce=4; vm.expectRevert(); this.matchPair(x,y,1e6);
    }
    function testSelfTradeExpiryAndMinNonce() public {
        Exchange.Order memory x=order(a,1,1,600000,1); Exchange.Order memory y=order(a,1,0,700000,2);
        vm.expectRevert(); this.matchPair(x,y,1e6);
        y.maker=b; vm.prank(a); e.invalidateNonces(2); vm.expectRevert(); this.matchPair(x,y,1e6);
        x.nonce=3; vm.warp(190000); vm.expectRevert(); this.matchPair(x,y,1e6);
    }
    function testBucketAndNegRisk() public {
        bytes32 id=keccak256("buckets"); uint256[] memory bounds=new uint256[](2); bounds[0]=500; bounds[1]=1000;
        o.createMarket(id,99999,200000,0,false,bounds);
        vm.startPrank(a); c.splitPosition(id,2,3e6); c.splitPosition(id,4,3e6);
        uint256 before=u.balanceOf(a); adapter.convert(id,0,3e6);
        require(u.balanceOf(a)==before+3e6); require(c.balanceOf(a,c.tokenId(id,1))==3e6); vm.stopPrank();
        vm.warp(200001); o.report(id,500,bytes32(0),false); vm.warp(200011); o.finalize(id); require(c.payout(id,1)==1);
    }
    function testTopBucketWaitsForNoonAndVerificationBeforeClaim() public {
        bytes32 id=keccak256("daily-six-ranges");
        uint256[] memory bounds=new uint256[](5); bounds[0]=500; bounds[1]=1000; bounds[2]=2000; bounds[3]=3000; bounds[4]=5000;
        o.createMarket(id,99999,200000,0,false,bounds);
        vm.prank(a); c.splitPosition(id,32,10e6);
        vm.expectRevert(); o.report(id,5000,keccak256("top reached before noon"),false);
        uint256[] memory masks=new uint256[](1); masks[0]=32;
        vm.prank(a); vm.expectRevert(); c.redeemPositions(id,masks);
        vm.warp(200000); o.report(id,5000,keccak256("noon report"),false);
        vm.expectRevert(); o.finalize(id);
        vm.warp(200010); o.finalize(id);
        for(uint256 i;i<6;i++) require(c.payout(id,i)==(i==5?1:0));
        vm.prank(a); c.redeemPositions(id,masks); require(c.claimable(a)==10e6);
        uint256 before=u.balanceOf(a); vm.prank(a); c.withdraw(); require(u.balanceOf(a)==before+10e6);
    }
    function testFuzzMintConservesCollateral(uint96 raw,uint8 cent) public {
        uint256 amount=(uint256(raw)%100+1)*1e6; uint256 price=(uint256(cent)%98+1)*10000;
        Exchange.Order memory x=order(a,1,0,price,1); Exchange.Order memory y=order(b,2,0,1e6-price,2); x.size=amount; y.size=amount;
        matchPair(x,y,amount); require(u.balanceOf(address(c))==c.locked(M)); require(c.locked(M)==10e6+amount);
    }
}
contract CollateralHandler is ERC1155Holder {
    MockUSDC public u; ConditionalTokens public c; bytes32 public constant M=keccak256("invariant"); uint256 public sets;
    constructor() { u=new MockUSDC(); c=new ConditionalTokens(u); c.setOracle(address(this)); c.prepare(M,2); u.faucet(); u.approve(address(c),type(uint256).max); }
    function split(uint96 raw) external { uint256 amount=uint256(raw)%1e6+1; if (u.balanceOf(address(this))<amount) return; c.splitPosition(M,1,amount); sets+=amount; }
    function merge(uint96 raw) external { if(sets==0)return; uint256 amount=uint256(raw)%sets+1; c.mergePositions(M,1,amount); sets-=amount; }
}
contract CollateralInvariant {
    CollateralHandler h; address[] internal targets;
    function setUp() public { Vm(address(uint160(uint256(keccak256("hevm cheat code"))))).warp(100000); h=new CollateralHandler(); targets.push(address(h)); }
    function targetContracts() external view returns(address[] memory) {return targets;}
    function invariantCollateralEqualsOutstandingCompleteSets() public view {
        require(h.u().balanceOf(address(h.c()))==h.sets()); require(h.c().locked(h.M())==h.sets());
        require(h.c().balanceOf(address(h),h.c().tokenId(h.M(),1))==h.sets());
        require(h.c().balanceOf(address(h),h.c().tokenId(h.M(),2))==h.sets());
    }
}
