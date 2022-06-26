// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import { IWorldID } from "world-id/interfaces/IWorldID.sol";
import { ByteHasher } from "world-id/libraries/ByteHasher.sol";
import { ModuleBase } from "lens-protocol/core/modules/ModuleBase.sol";
import { ICollectModule } from "lens-protocol/interfaces/ICollectModule.sol";
import { FollowValidationModuleBase } from "lens-protocol/core/modules/FollowValidationModuleBase.sol";

contract PerPersonCollectModule is FollowValidationModuleBase, ICollectModule {
  using ByteHasher for bytes;

  IWorldID public immutable worldId;
  uint256 public immutable groupId;

  constructor(
    address hub,
    IWorldID worldId_,
    uint256 groupId_
  ) ModuleBase(hub) {
    worldId = worldId_;
    groupId = groupId_;
  }

  mapping(uint256 => mapping(uint256 => bool)) internal followerOnlyPublications;

  function initializePublicationCollectModule(
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) external override onlyHub returns (bytes memory) {
    bool followerOnly = abi.decode(data, (bool));
    if (followerOnly) followerOnlyPublications[profileId][pubId] = true;
    return data;
  }

  function processCollect(
    uint256,
    address collector,
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) external view override {
    if (followerOnlyPublications[profileId][pubId]) _checkFollowValidity(profileId, collector);
    (uint256 root, uint256[8] memory proof) = abi.decode(data, (uint256, uint256[8]));
    worldId.verifyProof(
      root,
      groupId,
      abi.encodePacked(collector).hashToField(),
      abi.encodePacked(profileId, pubId).hashToField(),
      abi.encodePacked(address(this)).hashToField(),
      proof
    );
  }
}
