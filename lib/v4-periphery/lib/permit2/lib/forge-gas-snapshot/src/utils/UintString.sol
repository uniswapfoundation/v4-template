// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

library UintString {
    error InvalidStringNumber(string s);

    /// @notice converts the given string s into a uint256
    function stringToUint(string memory s)
        internal
        pure
        returns (uint256 result)
    {
        bytes memory b = bytes(s);
        uint256 oldResult = 0;
        for (uint256 i = 0; i < b.length; i++) {
            // c = b[i] was not needed
            if (uint8(b[i]) >= 48 && uint8(b[i]) <= 57) {
                // store old value so we can check for overflows
                oldResult = result;
                result = result * 10 + (uint8(b[i]) - 48);
                if (oldResult > result) {
                    // we can only get here if the result overflowed and is smaller than last stored value
                    revert InvalidStringNumber(s);
                }
            } else {
                revert InvalidStringNumber(s);
            }
        }
    }
}
