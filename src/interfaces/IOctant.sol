// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IOctant
 * @notice Interface for interacting with Octant protocol
 * @dev This interface should be implemented based on Octant's actual contract interface
 */
interface IOctant {
    /**
     * @notice Request funding from Octant protocol
     * @param _amount Amount of funding requested
     * @param _description Description of the funding request
     */
    function requestFunding(uint256 _amount, string memory _description) external;

    /**
     * @notice Check if a project is eligible for funding
     * @param _project Address of the project
     * @return Whether the project is eligible
     */
    function isEligible(address _project) external view returns (bool);

    /**
     * @notice Get available funding for a project
     * @param _project Address of the project
     * @return Available funding amount
     */
    function getAvailableFunding(address _project) external view returns (uint256);
}

