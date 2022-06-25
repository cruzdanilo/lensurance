// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import { Test } from "forge-std/Test.sol";
import { LibRLP } from "solmate/utils/LibRLP.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { FollowNFT } from "lens-protocol/core/FollowNFT.sol";
import { CollectNFT } from "lens-protocol/core/CollectNFT.sol";
import { ModuleGlobals } from "lens-protocol/core/modules/ModuleGlobals.sol";
import { LensHub, DataTypes } from "lens-protocol/core/LensHub.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { InsuranceCollectModule } from "../src/InsuranceCollectModule.sol";

contract InsuranceCollectModuleTest is Test {
  using LibRLP for address;

  address internal constant BOB = address(0x69);
  address internal constant ALICE = address(0x420);

  LensHub internal hub;
  uint256 internal profileId;
  MockERC20 internal erc20;
  ModuleGlobals internal globals;
  InsuranceCollectModule internal collectModule;

  function setUp() public {
    erc20 = new MockERC20("X", "x", 18);
    hub = LensHub(address(this).computeAddress(vm.getNonce(address(this)) + 3));
    vm.label(address(hub), "LensHub");
    new TransparentUpgradeableProxy(
      address(new LensHub(address(new FollowNFT(address(hub))), address(new CollectNFT(address(hub))))),
      address(0x666),
      abi.encodeWithSelector(LensHub.initialize.selector, "profile", "profile", address(this))
    );
    globals = new ModuleGlobals(address(this), address(this), 0);
    globals.whitelistCurrency(address(erc20), true);
    collectModule = new InsuranceCollectModule(address(hub), address(globals));

    hub.setState(DataTypes.ProtocolState.Unpaused);
    hub.whitelistCollectModule(address(collectModule), true);
    hub.whitelistProfileCreator(address(this), true);
    profileId = hub.createProfile(
      DataTypes.CreateProfileData({
        to: address(this),
        handle: "test",
        imageURI: "",
        followModule: address(0),
        followModuleInitData: "",
        followNFTURI: ""
      })
    );
    erc20.mint(address(this), 666 ether);
    erc20.mint(BOB, 666 ether);
    erc20.mint(ALICE, 666 ether);
    erc20.approve(address(collectModule), 666 ether);
    vm.prank(BOB);
    erc20.approve(address(collectModule), 666 ether);
    vm.prank(ALICE);
    erc20.approve(address(collectModule), 666 ether);
  }

  function testCollect() public {
    uint256 postId = hub.post(
      DataTypes.PostData({
        profileId: profileId,
        contentURI: "",
        collectModule: address(collectModule),
        collectModuleInitData: abi.encode(uint256(420), address(erc20), address(this), uint16(1), false),
        referenceModule: address(0),
        referenceModuleInitData: ""
      })
    );
    vm.prank(BOB);
    hub.collect(profileId, postId, abi.encode(address(erc20), uint256(420)));
  }
}
