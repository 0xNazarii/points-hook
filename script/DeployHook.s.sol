// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {PointsHook} from "../src/PointsHook.sol";

/// @notice Deploys PointsHook to an address whose low bits match its permissions.
/// Set POOL_MANAGER to the chain's v4 PoolManager and pass the signer on the CLI
/// (--account or --private-key).
contract DeployHook is Script {
    function run() external returns (PointsHook hook) {
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));

        // The PoolManager only calls hooks whose address encodes their permissions,
        // so mine a CREATE2 salt that gives such an address
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory initCode = abi.encodePacked(
            type(PointsHook).creationCode,
            abi.encode(manager)
        );
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY,
            flags,
            type(PointsHook).creationCode,
            abi.encode(manager)
        );

        // Deploy through the CREATE2 factory the salt was mined for. A salted `new`
        // in a script deploys from the broadcaster instead, giving another address.
        vm.startBroadcast();
        (bool success, ) = CREATE2_FACTORY.call(abi.encodePacked(salt, initCode));
        vm.stopBroadcast();

        require(success, "DeployHook: deployment failed");
        require(hookAddress.code.length > 0, "DeployHook: hook not deployed");

        hook = PointsHook(hookAddress);
        console.log("PointsHook deployed at", hookAddress);
    }
}
