// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CertificateRegistry} from "../src/CertificateRegistry.sol";

contract CertificateRegistryTest is Test {
    CertificateRegistry internal registry;
    address internal signer = makeAddr("signer");
    address internal second = makeAddr("second");
    address internal stranger = makeAddr("stranger");
    bytes32 internal key;
    bytes32 internal commitment;
    bytes32 internal issuer;
    bytes32 internal constant I2 = bytes32(uint256(2));
    bytes32 internal constant K2 = bytes32(uint256(2));

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
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        string memory vector = vm.readFile("fixtures/protocol-v1.json");
        key = vm.parseJsonBytes32(vector, ".certificate_key");
        commitment = vm.parseJsonBytes32(vector, ".commitment");
        issuer = vm.parseJsonBytes32(vector, ".issuer_id");
        registry = new CertificateRegistry(address(this));
        vm.warp(100);
        registry.setIssuer(issuer, signer, true, true);
    }

    function issueFixture() internal {
        vm.prank(signer);
        registry.issue(key, commitment, issuer);
    }

    function assertRecord(bytes32 k, bytes32 c, bytes32 i, uint64 registered, uint64 revoked) internal view {
        assertTrue(registry.exists(k));
        (bytes32 actualC, bytes32 actualI, uint64 actualRegistered, uint64 actualRevoked) =
            registry.getCertificate(k);
        assertEq(actualC, c);
        assertEq(actualI, i);
        assertEq(actualRegistered, registered);
        assertEq(actualRevoked, revoked);
    }

    function unauthorized(bytes32 i, address caller) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CertificateRegistry.IssuerUnauthorized.selector, i, caller);
    }

    function testConstructorRejectsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new CertificateRegistry(address(0));
    }

    function testConstructorVersionAndPublicAbsence() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(0), stranger);
        CertificateRegistry fresh = new CertificateRegistry(stranger);
        assertEq(fresh.owner(), stranger);
        assertEq(fresh.pendingOwner(), address(0));
        assertEq(fresh.protocolVersion(), uint16(1));
        vm.startPrank(stranger);
        assertFalse(registry.exists(0));
        assertFalse(registry.exists(key));
        (address s, bool ci, bool cr) = registry.getIssuer(0);
        assertEq(s, address(0));
        assertFalse(ci);
        assertFalse(cr);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateNotFound.selector, key));
        registry.getCertificate(key);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateNotFound.selector, bytes32(0)));
        registry.getCertificate(0);
        vm.stopPrank();
    }

    function testConfigurationValidationAndOwnerErrors() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        registry.setIssuer(0, address(0), true, true);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.setIssuer(0, signer, false, false);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.setIssuer(I2, address(0), true, false);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.setIssuer(I2, address(0), false, true);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.setIssuer(I2, address(0), true, true);
        vm.recordLogs();
        registry.setIssuer(I2, address(0), false, false);
        assertEq(vm.getRecordedLogs().length, 0);
        registry.setIssuer(I2, signer, false, false);
        (address s, bool ci, bool cr) = registry.getIssuer(I2);
        assertEq(s, signer);
        assertFalse(ci);
        assertFalse(cr);
    }

    function testExactConfigurationEventAndNoop() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit IssuerConfigured(I2, second, true, false);
        registry.setIssuer(I2, second, true, false);
        vm.recordLogs();
        registry.setIssuer(I2, second, true, false);
        assertEq(vm.getRecordedLogs().length, 0);
        vm.expectEmit(true, true, false, true, address(registry));
        emit IssuerConfigured(I2, second, false, true);
        registry.setIssuer(I2, second, false, true);
    }

    function testSyntheticIssueRevokeEventsAndPublicReading() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit CertificateIssued(key, issuer, commitment, signer, 100);
        issueFixture();
        vm.prank(stranger);
        assertRecord(key, commitment, issuer, 100, 0);
        vm.warp(200);
        vm.expectEmit(true, true, false, true, address(registry));
        emit CertificateRevoked(key, issuer, signer, 200);
        vm.prank(signer);
        registry.revoke(key);
        assertRecord(key, commitment, issuer, 100, 200);
    }

    function testIssueValidationOrderAndNoRejectedMutation() public {
        issueFixture();
        vm.warp(0);
        vm.startPrank(stranger);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.issue(0, commitment, issuer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.issue(key, 0, issuer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.issue(key, commitment, 0);
        vm.expectRevert(unauthorized(issuer, stranger));
        registry.issue(key, commitment, issuer);
        vm.expectRevert(unauthorized(I2, stranger));
        registry.issue(K2, commitment, I2);
        vm.stopPrank();
        vm.prank(signer);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateAlreadyExists.selector, key));
        registry.issue(key, commitment, issuer);
        vm.prank(signer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.issue(K2, commitment, issuer);
        assertFalse(registry.exists(K2));
        assertRecord(key, commitment, issuer, 100, 0);
    }

    function testEveryDuplicateIncludingRevokedAndDifferentIssuer() public {
        issueFixture();
        registry.setIssuer(I2, second, true, true);
        vm.startPrank(signer);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateAlreadyExists.selector, key));
        registry.issue(key, commitment, issuer);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateAlreadyExists.selector, key));
        registry.issue(key, bytes32(uint256(3)), issuer);
        registry.revoke(key);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateAlreadyExists.selector, key));
        registry.issue(key, commitment, issuer);
        vm.stopPrank();
        vm.prank(second);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateAlreadyExists.selector, key));
        registry.issue(key, bytes32(uint256(3)), I2);
        assertRecord(key, commitment, issuer, 100, 100);
    }

    function testRevokeValidationOrderAndRejectedState() public {
        issueFixture();
        vm.startPrank(signer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.revoke(0);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateNotFound.selector, K2));
        registry.revoke(K2);
        registry.revoke(key);
        vm.warp(0);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.CertificateAlreadyRevoked.selector, key));
        registry.revoke(key);
        vm.stopPrank();
        vm.prank(stranger);
        vm.expectRevert(unauthorized(issuer, stranger));
        registry.revoke(key);
        assertFalse(registry.exists(K2));
        assertRecord(key, commitment, issuer, 100, 100);
    }

    function testPermissionsIndependentSuspensionAndWithdrawal() public {
        registry.setIssuer(issuer, signer, true, false);
        issueFixture();
        vm.prank(signer);
        vm.expectRevert(unauthorized(issuer, signer));
        registry.revoke(key);
        registry.setIssuer(issuer, signer, false, true);
        vm.prank(signer);
        vm.expectRevert(unauthorized(issuer, signer));
        registry.issue(K2, commitment, issuer);
        assertRecord(key, commitment, issuer, 100, 0);
        vm.prank(signer);
        registry.revoke(key);
        registry.setIssuer(issuer, address(0), false, false);
        vm.prank(signer);
        vm.expectRevert(unauthorized(issuer, signer));
        registry.issue(K2, commitment, issuer);
        vm.prank(signer);
        vm.expectRevert(unauthorized(issuer, signer));
        registry.revoke(key);
        assertRecord(key, commitment, issuer, 100, 100);
        assertFalse(registry.exists(K2));
        registry.setIssuer(issuer, second, true, true);
        assertRecord(key, commitment, issuer, 100, 100);
    }

    function testRotationPreservesAndNewSignerRevokesOldRecord() public {
        issueFixture();
        registry.setIssuer(issuer, second, true, true);
        assertRecord(key, commitment, issuer, 100, 0);
        vm.startPrank(signer);
        vm.expectRevert(unauthorized(issuer, signer));
        registry.issue(K2, commitment, issuer);
        vm.expectRevert(unauthorized(issuer, signer));
        registry.revoke(key);
        vm.stopPrank();
        vm.startPrank(second);
        registry.issue(K2, commitment, issuer);
        registry.revoke(key);
        vm.stopPrank();
        assertRecord(key, commitment, issuer, 100, 100);
        assertRecord(K2, commitment, issuer, 100, 0);
    }

    function testDistinctAndSharedCrossIssuerAuthority() public {
        registry.setIssuer(I2, second, true, true);
        vm.prank(second);
        registry.issue(K2, commitment, I2);
        vm.prank(signer);
        vm.expectRevert(unauthorized(I2, signer));
        registry.revoke(K2);
        issueFixture();
        vm.prank(second);
        vm.expectRevert(unauthorized(issuer, second));
        registry.revoke(key);
        registry.setIssuer(I2, signer, true, true);
        vm.startPrank(signer);
        registry.revoke(key);
        registry.revoke(K2);
        registry.issue(bytes32(uint256(3)), commitment, I2);
        vm.stopPrank();
        assertRecord(key, commitment, issuer, 100, 100);
        assertRecord(K2, commitment, I2, 100, 100);
    }

    function testAdministrationDoesNotGrantOperationButCanBeConfigured() public {
        vm.expectRevert(unauthorized(issuer, address(this)));
        registry.issue(key, commitment, issuer);
        issueFixture();
        vm.expectRevert(unauthorized(issuer, address(this)));
        registry.revoke(key);
        registry.setIssuer(issuer, address(this), true, true);
        registry.issue(K2, commitment, issuer);
        registry.revoke(key);
        assertRecord(key, commitment, issuer, 100, 100);
    }

    function testTimestampZeroMaximumAndOverflow() public {
        vm.warp(0);
        vm.prank(signer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.issue(key, commitment, issuer);
        assertFalse(registry.exists(key));
        vm.warp(type(uint64).max);
        issueFixture();
        vm.prank(signer);
        registry.revoke(key);
        assertRecord(key, commitment, issuer, type(uint64).max, type(uint64).max);
        vm.warp(uint256(type(uint64).max) + 1);
        vm.prank(signer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.issue(K2, commitment, issuer);
        assertFalse(registry.exists(K2));
    }

    function testRevokeInvalidTimestampLeavesRecordUnchanged() public {
        issueFixture();
        vm.warp(0);
        vm.prank(signer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.revoke(key);
        assertRecord(key, commitment, issuer, 100, 0);
        vm.warp(uint256(type(uint64).max) + 1);
        vm.prank(signer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.revoke(key);
        assertRecord(key, commitment, issuer, 100, 0);
    }

    function testTwoStepAdministrationAcceptanceCancellationAndReplacement() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        registry.transferOwnership(second);
        vm.expectEmit(true, true, false, true, address(registry));
        emit OwnershipTransferStarted(address(this), second);
        registry.transferOwnership(second);
        assertEq(registry.owner(), address(this));
        assertEq(registry.pendingOwner(), second);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        registry.acceptOwnership();
        registry.transferOwnership(address(0));
        assertEq(registry.pendingOwner(), address(0));
        vm.prank(second);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, second));
        registry.acceptOwnership();
        registry.transferOwnership(second);
        registry.transferOwnership(stranger);
        vm.prank(second);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, second));
        registry.acceptOwnership();
        vm.expectEmit(true, true, false, true, address(registry));
        emit OwnershipTransferred(address(this), stranger);
        vm.prank(stranger);
        registry.acceptOwnership();
        assertEq(registry.owner(), stranger);
        assertEq(registry.pendingOwner(), address(0));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        registry.setIssuer(I2, second, true, true);
        vm.prank(stranger);
        registry.setIssuer(I2, second, true, true);
    }

    function testRenounceDisabledAndInheritedUnauthorizedError() public {
        registry.transferOwnership(second);
        vm.expectRevert(CertificateRegistry.RenounceDisabled.selector);
        registry.renounceOwnership();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        registry.renounceOwnership();
        assertEq(registry.owner(), address(this));
        assertEq(registry.pendingOwner(), second);
    }

    function testNormalCallsRejectFunds() public {
        bytes[] memory calls = new bytes[](14);
        calls[0] = "";
        calls[1] = hex"ffffffff";
        calls[2] = abi.encodeCall(registry.issue, (key, commitment, issuer));
        calls[3] = abi.encodeCall(registry.revoke, (key));
        calls[4] = abi.encodeCall(registry.setIssuer, (issuer, signer, true, true));
        calls[5] = abi.encodeCall(registry.getIssuer, (issuer));
        calls[6] = abi.encodeCall(registry.getCertificate, (key));
        calls[7] = abi.encodeCall(registry.exists, (key));
        calls[8] = abi.encodeCall(registry.protocolVersion, ());
        calls[9] = abi.encodeCall(registry.transferOwnership, (second));
        calls[10] = abi.encodeCall(registry.acceptOwnership, ());
        calls[11] = abi.encodeCall(registry.renounceOwnership, ());
        calls[12] = abi.encodeCall(registry.owner, ());
        calls[13] = abi.encodeCall(registry.pendingOwner, ());
        vm.deal(address(this), calls.length);
        for (uint256 n; n < calls.length; ++n) {
            (bool ok,) = address(registry).call{value: 1}(calls[n]);
            assertFalse(ok);
        }
        assertFalse(registry.exists(key));
        assertEq(address(registry).balance, 0);
        assertEq(registry.owner(), address(this));
    }

    function testFuzzRoundTrip(bytes32 k, bytes32 c, bytes32 i, uint64 created, uint64 revoked) public {
        vm.assume(k != 0 && c != 0 && i != 0);
        created = uint64(bound(created, 1, type(uint64).max));
        revoked = uint64(bound(revoked, created, type(uint64).max));
        registry.setIssuer(i, signer, true, true);
        vm.warp(created);
        vm.prank(signer);
        registry.issue(k, c, i);
        assertRecord(k, c, i, created, 0);
        vm.warp(revoked);
        vm.prank(signer);
        registry.revoke(k);
        assertRecord(k, c, i, created, revoked);
    }

    function testFuzzPermissions(bytes32 i, address s, bool ci, bool cr) public {
        vm.assume(i != 0 && s != address(0));
        registry.setIssuer(i, s, ci, cr);
        (address actual, bool actualIssue, bool actualRevoke) = registry.getIssuer(i);
        assertEq(actual, s);
        assertEq(actualIssue, ci);
        assertEq(actualRevoke, cr);
        vm.prank(s);
        if (!ci) vm.expectRevert(unauthorized(i, s));
        registry.issue(key, commitment, i);
        if (ci) {
            vm.prank(s);
            if (!cr) vm.expectRevert(unauthorized(i, s));
            registry.revoke(key);
            assertRecord(key, commitment, i, 100, cr ? 100 : 0);
        } else {
            assertFalse(registry.exists(key));
        }
    }

    function testFuzzOverflowTimestamp(uint256 timestamp) public {
        timestamp = bound(timestamp, uint256(type(uint64).max) + 1, type(uint256).max);
        issueFixture();
        vm.warp(timestamp);
        vm.startPrank(signer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.issue(K2, commitment, issuer);
        vm.expectRevert(CertificateRegistry.InvalidInput.selector);
        registry.revoke(key);
        vm.stopPrank();
        assertFalse(registry.exists(K2));
        assertRecord(key, commitment, issuer, 100, 0);
    }

    function testFuzzUnauthorizedCaller(address caller, bytes32 k, bytes32 c) public {
        vm.assume(caller != signer && k != 0 && c != 0);
        issueFixture();
        vm.startPrank(caller);
        vm.expectRevert(unauthorized(issuer, caller));
        registry.issue(k, c, issuer);
        vm.expectRevert(unauthorized(issuer, caller));
        registry.revoke(key);
        vm.stopPrank();
        assertRecord(key, commitment, issuer, 100, 0);
        if (k != key) assertFalse(registry.exists(k));
    }
}
