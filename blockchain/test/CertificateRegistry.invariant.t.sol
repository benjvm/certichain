// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {CertificateRegistry} from "../src/CertificateRegistry.sol";

/// @dev Expected reverts are compared byte-for-byte; unexpected failures fail the run.
contract RegistryHandler is Test {
    CertificateRegistry public immutable registry;

    struct Model {
        bytes32 commitment;
        bytes32 issuer;
        uint64 registered;
        uint64 revoked;
        bool present;
    }

    struct Authority {
        address signer;
        bool issueAllowed;
        bool revokeAllowed;
    }
    mapping(bytes32 => Model) public records;
    mapping(bytes32 => Authority) public authorities;
    address internal constant A = address(0xA11CE);
    address internal constant B = address(0xB0B);
    address internal constant SHARED = address(0x5151);
    address internal constant OUTSIDER = address(0xBAD);
    uint256 public issued;
    uint256 public revoked;
    uint256 public rejected;
    uint256 public configured;

    constructor() {
        registry = new CertificateRegistry(address(this));
        vm.warp(100);
        configure(0, 1, true, true);
        configure(1, 2, true, true);
        issue(0, bytes32(uint256(11)), 0);
        issue(1, bytes32(uint256(12)), 4);
        revoke(0, 0);
        unauthorized(3, bytes32(uint256(13)));
    }

    function configure(uint256 issuerChoice, uint256 signerChoice, bool ci, bool cr) public {
        bytes32 i = bytes32(issuerChoice % 2 + 1);
        address s = signerChoice % 4 == 0
            ? address(0)
            : signerChoice % 4 == 1 ? A : signerChoice % 4 == 2 ? B : SHARED;
        if (s == address(0)) {
            ci = false;
            cr = false;
        }
        registry.setIssuer(i, s, ci, cr);
        authorities[i] = Authority(s, ci, cr);
        configured++;
        checkModel(); // Configuration and rotation must preserve every record.
    }

    function actor(bytes32 i, uint256 choice) internal view returns (address) {
        uint256 n = choice % 4;
        return n == 0 ? authorities[i].signer : n == 1 ? A : n == 2 ? B : OUTSIDER;
    }

    function execute(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.recordLogs();
        vm.prank(caller);
        (bool ok, bytes memory result) = address(registry).call(data);
        if (expectedError.length == 0) {
            assertTrue(ok, "Unexpected rejection of valid modeled operation");
            assertEq(result.length, 0);
        } else {
            assertFalse(ok, "Expected rejection succeeded");
            assertEq(result, expectedError, "Unexpected revert (not swallowed)");
            assertEq(vm.getRecordedLogs().length, 0, "Rejected write emitted event");
            rejected++;
            checkModel(); // Failure must not create, overwrite, revoke or remove anything.
        }
    }

    function issue(uint256 slot, bytes32 c, uint256 choice) public {
        bytes32 k = bytes32(slot % 16 + 1);
        bytes32 i = bytes32((choice / 4) % 2 + 1);
        if (c == 0) c = bytes32(uint256(1));
        address caller = actor(i, choice);
        Authority memory auth = authorities[i];
        bytes memory errorData;
        if (auth.signer == address(0) || caller != auth.signer || !auth.issueAllowed) {
            errorData = abi.encodeWithSelector(CertificateRegistry.IssuerUnauthorized.selector, i, caller);
        } else if (records[k].present) {
            errorData = abi.encodeWithSelector(CertificateRegistry.CertificateAlreadyExists.selector, k);
        }
        vm.warp(block.timestamp + 1);
        execute(caller, abi.encodeCall(registry.issue, (k, c, i)), errorData);
        if (errorData.length == 0) {
            records[k] = Model(c, i, uint64(block.timestamp), 0, true);
            issued++;
            checkModel();
        }
    }

    function revoke(uint256 slot, uint256 choice) public {
        bytes32 k = bytes32(slot % 16 + 1);
        Model memory m = records[k];
        address caller = actor(m.issuer, choice);
        Authority memory auth = authorities[m.issuer];
        bytes memory errorData;
        if (!m.present) {
            errorData = abi.encodeWithSelector(CertificateRegistry.CertificateNotFound.selector, k);
        } else if (auth.signer == address(0) || caller != auth.signer || !auth.revokeAllowed) {
            errorData =
                abi.encodeWithSelector(CertificateRegistry.IssuerUnauthorized.selector, m.issuer, caller);
        } else if (m.revoked != 0) {
            errorData = abi.encodeWithSelector(CertificateRegistry.CertificateAlreadyRevoked.selector, k);
        }
        vm.warp(block.timestamp + 1);
        execute(caller, abi.encodeCall(registry.revoke, (k)), errorData);
        if (errorData.length == 0) {
            records[k].revoked = uint64(block.timestamp);
            revoked++;
            checkModel();
        }
    }

    function unauthorized(uint256 slot, bytes32 c) public {
        bytes32 k = bytes32(slot % 16 + 1);
        if (c == 0) c = bytes32(uint256(1));
        bytes32 i = bytes32(slot % 2 + 1);
        execute(
            OUTSIDER,
            abi.encodeCall(registry.issue, (k, c, i)),
            abi.encodeWithSelector(CertificateRegistry.IssuerUnauthorized.selector, i, OUTSIDER)
        );
        Model memory m = records[k];
        execute(
            OUTSIDER,
            abi.encodeCall(registry.revoke, (k)),
            m.present
                ? abi.encodeWithSelector(CertificateRegistry.IssuerUnauthorized.selector, m.issuer, OUTSIDER)
                : abi.encodeWithSelector(CertificateRegistry.CertificateNotFound.selector, k)
        );
    }

    function checkModel() public view {
        assertFalse(registry.exists(0));
        for (uint256 n = 1; n <= 16; ++n) {
            bytes32 k = bytes32(n);
            Model memory m = records[k];
            assertEq(registry.exists(k), m.present, "Presence changed");
            if (m.present) {
                (bytes32 c, bytes32 i, uint64 registered, uint64 revocation) = registry.getCertificate(k);
                assertEq(c, m.commitment, "Commitment changed");
                assertEq(i, m.issuer, "Issuer changed");
                assertEq(registered, m.registered, "Registration changed");
                assertEq(revocation, m.revoked, "Revocation changed or undone");
            }
        }
        for (uint256 n = 1; n <= 2; ++n) {
            bytes32 i = bytes32(n);
            (address s, bool ci, bool cr) = registry.getIssuer(i);
            Authority memory auth = authorities[i];
            assertEq(s, auth.signer);
            assertEq(ci, auth.issueAllowed);
            assertEq(cr, auth.revokeAllowed);
        }
    }
}

contract CertificateRegistryInvariantTest is StdInvariant, Test {
    RegistryHandler internal handler;

    function setUp() public {
        handler = new RegistryHandler();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = RegistryHandler.issue.selector;
        selectors[1] = RegistryHandler.revoke.selector;
        selectors[2] = RegistryHandler.configure.selector;
        selectors[3] = RegistryHandler.unauthorized.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariantRecordsAndAuthorityMatchModel() public view {
        handler.checkModel();
    }

    function invariantValidAndRejectedOperationsAreReached() public view {
        assertGe(handler.issued(), 2);
        assertGe(handler.revoked(), 1);
        assertGe(handler.configured(), 2);
        assertGe(handler.rejected(), 2);
    }
}
