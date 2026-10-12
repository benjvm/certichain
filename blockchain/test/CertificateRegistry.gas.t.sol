// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {CertificateRegistry} from "../src/CertificateRegistry.sol";

/// @dev Deterministic, isolated scenarios for snapshot checks (no fuzz medians).
contract CertificateRegistryGasTest is Test {
    CertificateRegistry internal registry;
    bytes32 internal constant K = bytes32(uint256(1));
    bytes32 internal constant C = bytes32(uint256(2));
    bytes32 internal constant I = bytes32(uint256(3));
    address internal constant SIGNER = address(0xA11CE);

    function setUp() public {
        vm.warp(100);
        registry = new CertificateRegistry(address(this));
        registry.setIssuer(I, SIGNER, true, true);
    }

    function testGasDeploy() public {
        new CertificateRegistry(address(this));
    }

    function testGasConfigure() public {
        registry.setIssuer(bytes32(uint256(4)), SIGNER, true, true);
    }

    function testGasIssue() public {
        vm.prank(SIGNER);
        registry.issue(K, C, I);
    }

    function testGasRevoke() public {
        vm.pauseGasMetering();
        vm.prank(SIGNER);
        registry.issue(K, C, I);
        vm.resumeGasMetering();
        vm.prank(SIGNER);
        registry.revoke(K);
    }

    function testGasRotate() public {
        registry.setIssuer(I, address(0xB0B), true, true);
    }

    function testGasRead() public {
        vm.pauseGasMetering();
        vm.prank(SIGNER);
        registry.issue(K, C, I);
        vm.resumeGasMetering();
        registry.getCertificate(K);
    }
}
