// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import { Test } from "forge-std/Test.sol";
import { LibRLP } from "solmate/utils/LibRLP.sol";
import { Semaphore } from "world-id/Semaphore.sol";
import { FollowNFT } from "lens-protocol/core/FollowNFT.sol";
import { CollectNFT } from "lens-protocol/core/CollectNFT.sol";
import { LensHub, DataTypes } from "lens-protocol/core/LensHub.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { PerPersonCollectModule } from "../src/PerPersonCollectModule.sol";

contract PerPersonCollectModuleTest is Test {
  using LibRLP for address;

  address internal constant BOB = address(0x69);
  address internal constant ALICE = address(0x420);

  LensHub internal hub;
  uint256 internal profileId;
  PerPersonCollectModule internal collectModule;

  function setUp() public {
    hub = LensHub(address(this).computeAddress(vm.getNonce(address(this)) + 3));
    vm.label(address(hub), "LensHub");
    new TransparentUpgradeableProxy(
      address(new LensHub(address(new FollowNFT(address(hub))), address(new CollectNFT(address(hub))))),
      address(0x666),
      abi.encodeWithSelector(LensHub.initialize.selector, "profile", "profile", address(this))
    );
    Semaphore semaphore = new Semaphore();
    semaphore.createGroup(1, 20, 0);
    collectModule = new PerPersonCollectModule(address(hub), semaphore, 1);

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
  }

  function testCollect() public {
    uint256 postId = hub.post(
      DataTypes.PostData({
        profileId: profileId,
        contentURI: "",
        collectModule: address(collectModule),
        collectModuleInitData: abi.encode(false),
        referenceModule: address(0),
        referenceModuleInitData: ""
      })
    );
    vm.prank(BOB);
    hub.collect(profileId, postId, abi.encode());
  }
}
