// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import { Test } from "forge-std/Test.sol";
import { LibRLP } from "solmate/utils/LibRLP.sol";
import { FollowNFT } from "lens-protocol/core/FollowNFT.sol";
import { CollectNFT } from "lens-protocol/core/CollectNFT.sol";
import { LensHub, DataTypes } from "lens-protocol/core/LensHub.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { InteractsWithWorldID, TypeConverter } from "world-id/test/helpers/InteractsWithWorldID.sol";
import { PerPersonCollectModule } from "../src/PerPersonCollectModule.sol";

contract PerPersonCollectModuleTest is Test, InteractsWithWorldID {
  using TypeConverter for address;
  using LibRLP for address;

  address internal constant BOB = address(0x69);
  address internal constant ALICE = address(0x420);

  LensHub internal hub;
  uint256 internal profileId;
  PerPersonCollectModule internal collectModule;

  function setUp() public {
    setUpWorldID();

    hub = LensHub(address(this).computeAddress(vm.getNonce(address(this)) + 3));
    vm.label(address(hub), "LensHub");
    new TransparentUpgradeableProxy(
      address(new LensHub(address(new FollowNFT(address(hub))), address(new CollectNFT(address(hub))))),
      address(0x666),
      abi.encodeWithSelector(LensHub.initialize.selector, "profile", "profile", address(this))
    );
    collectModule = new PerPersonCollectModule(address(hub), worldID, 1);

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

  function testCannotDoubleCollect() public {
    uint256 pubId = hub.post(
      DataTypes.PostData({
        profileId: profileId,
        contentURI: "",
        collectModule: address(collectModule),
        collectModuleInitData: abi.encode(false),
        referenceModule: address(0),
        referenceModuleInitData: ""
      })
    );

    string[] memory ffiArgs = new string[](2);
    ffiArgs[0] = "node";
    ffiArgs[1] = "lib/world-id-starter/src/test/scripts/generate-commitment.js";
    semaphore.addMember(1, abi.decode(vm.ffi(ffiArgs), (uint256)));

    uint256 root = getRoot();
    address externalNullifier = address(bytes20(keccak256(abi.encodePacked(profileId, pubId))));

    ffiArgs = new string[](3);
    ffiArgs[0] = "bash";
    ffiArgs[1] = "-c";
    ffiArgs[2] = string(
      abi.encodePacked(
        "cd lib/world-id-starter && node --no-warnings src/test/scripts/generate-proof.js ",
        BOB.toString(),
        " ",
        externalNullifier.toString()
      )
    );
    (uint256 nullifierHash, uint256[8] memory proof) = abi.decode(vm.ffi(ffiArgs), (uint256, uint256[8]));

    vm.prank(BOB);
    hub.collect(profileId, pubId, abi.encode(root, nullifierHash, proof));

    ffiArgs[2] = string(
      abi.encodePacked(
        "cd lib/world-id-starter && node --no-warnings src/test/scripts/generate-proof.js ",
        ALICE.toString(),
        " ",
        externalNullifier.toString()
      )
    );
    (nullifierHash, proof) = abi.decode(vm.ffi(ffiArgs), (uint256, uint256[8]));

    vm.prank(ALICE);
    vm.expectRevert(PerPersonCollectModule.InvalidNullifier.selector);
    hub.collect(profileId, pubId, abi.encode(root, nullifierHash, proof));
  }
}
