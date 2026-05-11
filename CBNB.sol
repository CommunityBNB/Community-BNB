// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CBNB is ERC20 {
    // ── 供应 / Supply ─────────────────────────────────────────
    // 全部通过挖矿产出，无预铸造，无创世
    // All supply via mining only — no premint, no genesis
    uint256 public constant MINE_SUPPLY = 21_000_000e18;

    // ── 挖矿参数 / Mining parameters ──────────────────────────
    uint256 public constant INITIAL_REWARD    = 12_000e18; // 首轮奖励 / Initial round reward
    uint256 public constant INITIAL_THRESHOLD = 1 ether;   // 首轮阈值 / Initial round threshold
    uint256 public constant TARGET_INTERVAL   = 4 hours;   // 目标每轮耗时 / Target round duration
    uint256 public constant ADJUSTMENT_PERIOD = 8;         // 每 N 轮调整阈值 / Adjust threshold every N rounds
    uint256 public constant HALVING_PERIOD    = 875;        // 每 N 轮奖励减半 / Halve reward every N rounds
    uint256 public constant MAX_ADJUSTMENT    = 4;          // 单次调整上限倍数 / Max adjustment multiplier

    // BNB 黑洞地址，销毁不可逆 / BNB burn address — irreversible
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // ── 挖矿状态 / Mining state ───────────────────────────────
    uint256 public currentRound     = 1;
    uint256 public currentThreshold = INITIAL_THRESHOLD;
    uint256 public roundAccumulated = 0;
    uint256 public totalMined       = 0;
    uint256 public lastAdjustTime   = 0;
    uint256 public lastAdjustRound  = 0;

    // 当前轮参与者（加权抽签用）/ Current round participants (weighted draw)
    address[] private _participants;
    uint256[] private _weights;
    uint256   private _totalWeight;

    // ── 事件 / Events ─────────────────────────────────────────
    event RoundSettled(uint256 indexed round, address winner, uint256 reward, uint256 threshold);
    event Burned(address indexed burner, uint256 amountBurned, uint256 round);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold, uint256 rounds, uint256 actualInterval);

    constructor() ERC20("cBNB", "cBNB") {
        // 不铸造任何初始代币，全部由挖矿产出
        // No initial mint — all supply emerges from mining
        lastAdjustTime = block.timestamp;
    }

    // ── 入口：用户直接转账 BNB 即可 / Entry: just send BNB ────
    receive() external payable {
        _burnToMine(msg.sender, msg.value);
    }

    fallback() external payable {
        _burnToMine(msg.sender, msg.value);
    }

    // ── 挖矿：销毁 BNB，加权参与，自动结算 / Mine: burn BNB, weighted entry, auto-settle ──
    function _burnToMine(address miner, uint256 bnbAmount) internal {
        require(bnbAmount >= 0.001 ether, "Min 0.001 BNB");

        // 挖矿已结束，仍接受并销毁 BNB / Mining complete — still accept and burn BNB
        if (totalMined >= MINE_SUPPLY) {
            (bool ok,) = BURN_ADDRESS.call{value: bnbAmount}("");
            require(ok, "Burn failed");
            return;
        }

        uint256 remaining = bnbAmount;

        while (remaining > 0 && totalMined < MINE_SUPPLY) {
            uint256 needed = currentThreshold - roundAccumulated;
            uint256 use = remaining >= needed ? needed : remaining;

            _addParticipant(miner, use);
            remaining -= use;

            if (use == needed) {
                // 阈值已满，触发结算 / Threshold met, trigger settlement
                roundAccumulated = currentThreshold;
                _settle();
            } else {
                roundAccumulated += use;
            }

            // 每笔 BNB 立即销毁到黑洞 / Burn each chunk to dead address immediately
            (bool ok,) = BURN_ADDRESS.call{value: use}("");
            require(ok, "Burn failed");
        }

        // 销毁超出挖矿上限的剩余部分 / Burn remainder after mining cap
        if (remaining > 0) {
            (bool ok,) = BURN_ADDRESS.call{value: remaining}("");
            require(ok, "Burn failed");
        }

        emit Burned(miner, bnbAmount, currentRound);
    }

    // ── 结算当前轮 / Settle current round ─────────────────────
    function _settle() internal {
        uint256 reward = _currentReward();
        if (reward == 0) {
            totalMined = MINE_SUPPLY; // 整数截断导致减半序列未能精确达到上限，强制对齐以防止 while 死锁
            return;
        }
        if (totalMined + reward > MINE_SUPPLY) reward = MINE_SUPPLY - totalMined;

        address winner = _drawWinner();
        totalMined += reward;
        _mint(winner, reward); // 奖励直接铸造到获胜者 / Mint reward directly to winner
        emit RoundSettled(currentRound, winner, reward, currentThreshold);

        // 重置轮次状态 / Reset round state
        delete _participants;
        delete _weights;
        _totalWeight = 0;
        roundAccumulated = 0;
        currentRound++;

        if (currentRound - 1 - lastAdjustRound >= ADJUSTMENT_PERIOD) _adjustThreshold();
    }

    // ── 加权随机抽签 / Weighted random draw ───────────────────
    // 注意：使用链上可预测值，适合低价值娱乐场景
    // Note: uses on-chain predictable values, suitable for low-stakes entertainment
    function _drawWinner() internal view returns (address) {
        if (_participants.length == 1) return _participants[0];
        uint256 rand = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1), block.timestamp, currentRound, _totalWeight
        ))) % _totalWeight;
        uint256 cumulative = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            cumulative += _weights[i];
            if (rand < cumulative) return _participants[i];
        }
        return _participants[_participants.length - 1];
    }

    // 同一地址累加权重，避免重复存储 / Accumulate weight for same address
    function _addParticipant(address user, uint256 weight) internal {
        for (uint256 i = 0; i < _participants.length; i++) {
            if (_participants[i] == user) {
                _weights[i] += weight;
                _totalWeight += weight;
                return;
            }
        }
        _participants.push(user);
        _weights.push(weight);
        _totalWeight += weight;
    }

    // ── 减半计算 / Halving calculation ────────────────────────
    function _currentReward() internal view returns (uint256) {
        uint256 era = (currentRound - 1) / HALVING_PERIOD;
        if (era >= 64) return 0;
        return INITIAL_REWARD >> era; // 每个 era 奖励减半 / Reward halves each era
    }

    // ── 难度调整（比特币公式）/ Difficulty adjustment (Bitcoin formula) ──
    function _adjustThreshold() internal {
        uint256 elapsed = block.timestamp - lastAdjustTime;
        uint256 rounds  = currentRound - 1 - lastAdjustRound;
        if (rounds == 0) return;

        uint256 newThreshold;
        if (elapsed == 0) {
            // 极端情况：同一区块内完成多轮 / Edge case: multiple rounds in same block
            newThreshold = currentThreshold * MAX_ADJUSTMENT;
        } else {
            uint256 actualInterval = elapsed / rounds;
            if (actualInterval < TARGET_INTERVAL) {
                // 太快，提高阈值 / Too fast, raise threshold
                uint256 ratio = TARGET_INTERVAL * 1e6 / actualInterval;
                if (ratio > MAX_ADJUSTMENT * 1e6) ratio = MAX_ADJUSTMENT * 1e6;
                newThreshold = currentThreshold * ratio / 1e6;
            } else {
                // 太慢，降低阈值 / Too slow, lower threshold
                uint256 ratio = actualInterval * 1e6 / TARGET_INTERVAL;
                if (ratio > MAX_ADJUSTMENT * 1e6) ratio = MAX_ADJUSTMENT * 1e6;
                newThreshold = currentThreshold * 1e6 / ratio;
            }
        }

        if (newThreshold < 0.001 ether) newThreshold = 0.001 ether; // 最低阈值保护 / Minimum floor
        emit ThresholdUpdated(currentThreshold, newThreshold, rounds, elapsed == 0 ? 0 : elapsed / rounds);
        currentThreshold = newThreshold;
        lastAdjustRound  = currentRound - 1;
        lastAdjustTime   = block.timestamp;
    }

    // ── 公开查询 / Public view functions ──────────────────────
    function currentReward() external view returns (uint256) { return _currentReward(); }
    function roundProgress() external view returns (uint256 accumulated, uint256 threshold) {
        return (roundAccumulated, currentThreshold);
    }
    function participantCount() external view returns (uint256) { return _participants.length; }
}
