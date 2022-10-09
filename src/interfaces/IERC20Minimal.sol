// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}
