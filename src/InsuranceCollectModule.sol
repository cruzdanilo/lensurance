// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.10;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "lens-protocol/libraries/Errors.sol";
import { ModuleBase } from "lens-protocol/core/modules/ModuleBase.sol";
import { FeeModuleBase } from "lens-protocol/core/modules/FeeModuleBase.sol";
import { ICollectModule } from "lens-protocol/interfaces/ICollectModule.sol";
import { FollowValidationModuleBase } from "lens-protocol/core/modules/FollowValidationModuleBase.sol";

/**
 * @notice A struct containing the necessary data to execute collect actions on a publication.
 *
 * @param amount The collecting cost associated with this publication.
 * @param currency The currency associated with this publication.
 * @param recipient The recipient address associated with this publication.
 * @param referralFee The referral fee associated with this publication.
 * @param followerOnly Whether only followers should be able to collect.
 */
struct ProfilePublicationData {
  uint256 amount;
  address currency;
  address recipient;
  uint16 referralFee;
  bool followerOnly;
}

/**
 * @title FeeCollectModule
 * @author Lens Protocol
 *
 * @notice This is a simple Lens CollectModule implementation, inheriting from the ICollectModule interface and
 * the FeeCollectModuleBase abstract contract.
 *
 * This module works by allowing unlimited collects for a publication at a given price.
 */
contract InsuranceCollectModule is FeeModuleBase, FollowValidationModuleBase, ICollectModule {
  using SafeERC20 for IERC20;

  mapping(uint256 => mapping(uint256 => ProfilePublicationData)) internal publicationData;

  constructor(address hub, address moduleGlobals) FeeModuleBase(moduleGlobals) ModuleBase(hub) {}

  /**
   * @notice This collect module levies a fee on collects and supports referrals. Thus, we need to decode data.
   *
   * @param profileId The token ID of the profile of the publisher, passed by the hub.
   * @param pubId The publication ID of the newly created publication, passed by the hub.
   * @param data The arbitrary data parameter, decoded into:
   *      uint256 amount: The currency total amount to levy.
   *      address currency: The currency address, must be internally whitelisted.
   *      address recipient: The custom recipient address to direct earnings to.
   *      uint16 referralFee: The referral fee to set.
   *      bool followerOnly: Whether only followers should be able to collect.
   *
   * @return bytes An abi encoded bytes parameter, which is the same as the passed data parameter.
   */
  function initializePublicationCollectModule(
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) external override onlyHub returns (bytes memory) {
    (uint256 amount, address currency, address recipient, uint16 referralFee, bool followerOnly) = abi.decode(
      data,
      (uint256, address, address, uint16, bool)
    );
    if (!_currencyWhitelisted(currency) || recipient == address(0) || referralFee > BPS_MAX || amount == 0) {
      revert Errors.InitParamsInvalid();
    }

    publicationData[profileId][pubId] = ProfilePublicationData({
      amount: amount,
      currency: currency,
      recipient: recipient,
      referralFee: referralFee,
      followerOnly: followerOnly
    });
    return data;
  }

  /**
   * @dev Processes a collect by:
   *  1. Ensuring the collector is a follower
   *  2. Charging a fee
   */
  function processCollect(
    uint256 referrerProfileId,
    address collector,
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) external virtual override onlyHub {
    if (publicationData[profileId][pubId].followerOnly) _checkFollowValidity(profileId, collector);
    if (referrerProfileId == profileId) {
      _processCollect(collector, profileId, pubId, data);
    } else {
      _processCollectWithReferral(referrerProfileId, collector, profileId, pubId, data);
    }
  }

  function _processCollect(
    address collector,
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) internal {
    uint256 amount = publicationData[profileId][pubId].amount;
    address currency = publicationData[profileId][pubId].currency;
    _validateDataIsExpected(data, currency, amount);

    (address treasury, uint16 treasuryFee) = _treasuryData();
    address recipient = publicationData[profileId][pubId].recipient;
    uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;
    uint256 adjustedAmount = amount - treasuryAmount;

    IERC20(currency).safeTransferFrom(collector, recipient, adjustedAmount);
    if (treasuryAmount > 0) IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
  }

  function _processCollectWithReferral(
    uint256 referrerProfileId,
    address collector,
    uint256 profileId,
    uint256 pubId,
    bytes calldata data
  ) internal {
    uint256 amount = publicationData[profileId][pubId].amount;
    address currency = publicationData[profileId][pubId].currency;
    _validateDataIsExpected(data, currency, amount);

    uint256 referralFee = publicationData[profileId][pubId].referralFee;
    address treasury;
    uint256 treasuryAmount;

    // Avoids stack too deep
    {
      uint16 treasuryFee;
      (treasury, treasuryFee) = _treasuryData();
      treasuryAmount = (amount * treasuryFee) / BPS_MAX;
    }

    uint256 adjustedAmount = amount - treasuryAmount;

    if (referralFee != 0) {
      // The reason we levy the referral fee on the adjusted amount is so that referral fees
      // don't bypass the treasury fee, in essence referrals pay their fair share to the treasury.
      uint256 referralAmount = (adjustedAmount * referralFee) / BPS_MAX;
      adjustedAmount = adjustedAmount - referralAmount;

      address referralRecipient = IERC721(HUB).ownerOf(referrerProfileId);

      IERC20(currency).safeTransferFrom(collector, referralRecipient, referralAmount);
    }
    address recipient = publicationData[profileId][pubId].recipient;

    IERC20(currency).safeTransferFrom(collector, recipient, adjustedAmount);
    if (treasuryAmount > 0) IERC20(currency).safeTransferFrom(collector, treasury, treasuryAmount);
  }
}
