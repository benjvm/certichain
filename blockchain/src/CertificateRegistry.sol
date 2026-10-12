// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Protocol v1: opaque commitments, current issuer authority and irreversible revocation.
/// @dev Does not establish PDF correspondence, institutional identity or academic truth.
contract CertificateRegistry is Ownable2Step {
    struct Issuer {
        address signer;
        bool canIssue;
        bool canRevoke;
    }

    struct Certificate {
        bytes32 commitment;
        bytes32 issuerId;
        uint64 registeredAt;
        uint64 revokedAt;
        bool present;
    }

    mapping(bytes32 => Issuer) private _issuers;
    mapping(bytes32 => Certificate) private _certificates;

    error InvalidInput();
    error IssuerUnauthorized(bytes32 issuerId, address caller);
    error CertificateAlreadyExists(bytes32 certificateKey);
    error CertificateNotFound(bytes32 certificateKey);
    error CertificateAlreadyRevoked(bytes32 certificateKey);
    error RenounceDisabled();

    event IssuerConfigured(bytes32 indexed issuerId, address indexed signer, bool canIssue, bool canRevoke);
    event CertificateIssued(
        bytes32 indexed certificateKey,
        bytes32 indexed issuerId,
        bytes32 commitment,
        address signer,
        uint64 registeredAt
    );
    event CertificateRevoked(
        bytes32 indexed certificateKey, bytes32 indexed issuerId, address signer, uint64 revokedAt
    );

    constructor(address administrator) Ownable(administrator) {}

    function protocolVersion() external pure returns (uint16) {
        return 1;
    }

    /// @dev Renouncing is disabled; unauthorized callers retain the inherited Ownable error.
    function renounceOwnership() public override onlyOwner {
        revert RenounceDisabled();
    }

    function setIssuer(bytes32 issuerId, address signer, bool canIssue, bool canRevoke) external onlyOwner {
        if (issuerId == bytes32(0) || (signer == address(0) && (canIssue || canRevoke))) {
            revert InvalidInput();
        }
        Issuer storage current = _issuers[issuerId];
        if (current.signer == signer && current.canIssue == canIssue && current.canRevoke == canRevoke) {
            return;
        }
        _issuers[issuerId] = Issuer(signer, canIssue, canRevoke);
        emit IssuerConfigured(issuerId, signer, canIssue, canRevoke);
    }

    function getIssuer(bytes32 issuerId)
        external
        view
        returns (address signer, bool canIssue, bool canRevoke)
    {
        Issuer storage current = _issuers[issuerId];
        return (current.signer, current.canIssue, current.canRevoke);
    }

    function issue(bytes32 certificateKey, bytes32 commitment, bytes32 issuerId) external {
        if (certificateKey == bytes32(0) || commitment == bytes32(0) || issuerId == bytes32(0)) {
            revert InvalidInput();
        }
        Issuer storage issuer = _issuers[issuerId];
        if (issuer.signer == address(0) || issuer.signer != msg.sender || !issuer.canIssue) {
            revert IssuerUnauthorized(issuerId, msg.sender);
        }
        if (_certificates[certificateKey].present) revert CertificateAlreadyExists(certificateKey);
        uint64 timestamp = _timestamp();
        _certificates[certificateKey] = Certificate(commitment, issuerId, timestamp, 0, true);
        emit CertificateIssued(certificateKey, issuerId, commitment, msg.sender, timestamp);
    }

    function exists(bytes32 certificateKey) external view returns (bool) {
        return _certificates[certificateKey].present;
    }

    function getCertificate(bytes32 certificateKey)
        external
        view
        returns (bytes32 commitment, bytes32 issuerId, uint64 registeredAt, uint64 revokedAt)
    {
        Certificate storage certificate = _certificates[certificateKey];
        if (!certificate.present) revert CertificateNotFound(certificateKey);
        return (certificate.commitment, certificate.issuerId, certificate.registeredAt, certificate.revokedAt);
    }

    function revoke(bytes32 certificateKey) external {
        if (certificateKey == bytes32(0)) revert InvalidInput();
        Certificate storage certificate = _certificates[certificateKey];
        if (!certificate.present) revert CertificateNotFound(certificateKey);
        bytes32 issuerId = certificate.issuerId;
        Issuer storage issuer = _issuers[issuerId];
        if (issuer.signer == address(0) || issuer.signer != msg.sender || !issuer.canRevoke) {
            revert IssuerUnauthorized(issuerId, msg.sender);
        }
        if (certificate.revokedAt != 0) revert CertificateAlreadyRevoked(certificateKey);
        uint64 timestamp = _timestamp();
        certificate.revokedAt = timestamp;
        emit CertificateRevoked(certificateKey, issuerId, msg.sender, timestamp);
    }

    function _timestamp() private view returns (uint64) {
        if (block.timestamp == 0 || block.timestamp > type(uint64).max) revert InvalidInput();
        return uint64(block.timestamp);
    }
}
