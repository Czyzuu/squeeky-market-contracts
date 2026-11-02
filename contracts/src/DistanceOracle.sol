// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ConditionalTokens} from "./ConditionalTokens.sol";

/// V1 trust: reporter supplies distance, guardian may replace a pending report.
contract DistanceOracle {
    ConditionalTokens public immutable ctf;
    address public immutable reporter;
    address public immutable guardian;
    uint256 public immutable disputeSeconds;
    struct Market { uint64 start; uint64 end; uint64 line; bool early; uint8 outcomes; }
    struct Report { uint256 distance; bytes32 dataHash; uint64 finalizeAt; bool invalid; bool finalized; }
    mapping(bytes32 => Market) public markets;
    mapping(bytes32 => Report) public reports;
    mapping(bytes32 => uint256[]) private bounds;
    event Reported(bytes32 indexed market, uint256 distanceMeters, bytes32 dataHash, bool invalid, uint256 finalizeAt);
    constructor(ConditionalTokens tokens, address source, address guard, uint256 delay) {
        require(source != address(0) && guard != address(0) && delay >= 1, "Bad config");
        ctf = tokens; reporter = source; guardian = guard; disputeSeconds = delay;
    }
    function createMarket(bytes32 id, uint64 start, uint64 end, uint64 line, bool early, uint256[] calldata bucketBounds) external {
        require(msg.sender == reporter && start < end && end > block.timestamp && markets[id].end == 0, "Bad market");
        require(bucketBounds.length <= 7, "Too many buckets");
        uint8 n = bucketBounds.length == 0 ? 2 : uint8(bucketBounds.length + 1);
        require(n <= 8 && (bucketBounds.length == 0 || !early), "Bad buckets");
        for (uint256 i; i < bucketBounds.length; i++) require(bucketBounds[i] > (i == 0 ? 0 : bucketBounds[i-1]), "Unsorted bounds");
        markets[id] = Market(start, end, line, early, n); bounds[id] = bucketBounds; ctf.prepare(id, n);
    }
    function report(bytes32 id, uint256 distance, bytes32 dataHash, bool invalid) external {
        require(msg.sender == reporter && reports[id].finalizeAt == 0, "Reporter or duplicate");
        _report(id, distance, dataHash, invalid);
    }
    function overrideReport(bytes32 id, uint256 distance, bytes32 dataHash, bool invalid) external {
        require(msg.sender == guardian && reports[id].finalizeAt != 0 && !reports[id].finalized && block.timestamp < reports[id].finalizeAt, "Outside dispute window");
        _report(id, distance, dataHash, invalid);
    }
    function _report(bytes32 id, uint256 distance, bytes32 dataHash, bool invalid) internal {
        Market memory m = markets[id];
        require(m.end > 0 && block.timestamp >= m.start, "Unknown or not started");
        require(block.timestamp >= m.end || (m.early && distance > m.line && !invalid), "Too early");
        reports[id] = Report(distance, dataHash, uint64(block.timestamp + disputeSeconds), invalid, false);
        emit Reported(id, distance, dataHash, invalid, block.timestamp + disputeSeconds);
    }
    function isTradable(bytes32 id) external view returns (bool) {
        Market memory m = markets[id];
        return block.timestamp >= m.start && block.timestamp < m.end && reports[id].finalizeAt == 0;
    }
    function finalize(bytes32 id) external {
        Report storage r = reports[id]; Market memory m = markets[id];
        require(r.finalizeAt > 0 && !r.finalized && block.timestamp >= r.finalizeAt, "Not final");
        r.finalized = true; uint256[] memory nums = new uint256[](m.outcomes);
        if (r.invalid) { for (uint256 i; i < m.outcomes; i++) nums[i] = 1; }
        else if (bounds[id].length == 0) nums[r.distance > m.line ? 0 : 1] = 1;
        else { uint256 index; while (index < bounds[id].length && r.distance >= bounds[id][index]) index++; nums[index] = 1; }
        ctf.reportPayouts(id, nums);
    }
}
