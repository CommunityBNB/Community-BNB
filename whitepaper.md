# cBNB Whitepaper

`v0.1` · `single page` · `immutable contract`

[← Back to repo](README.md) · [📜 白皮书（中文）](whitepaper-cn.md)

---

A deflationary primitive, on BSC.

cBNB is an ERC-20 on BNB Smart Chain. Single immutable contract. It does not migrate. There is no v2, no fork, no successor token. The contract that exists is the contract.

---

## ┌ problem

BNB is the native asset of BNB Smart Chain. It is consumed, held, and traded. But no native mechanism exists for the community to burn it in a decentralized, permissionless way.

cBNB is that mechanism.

---

## ┌ design

Every cBNB is produced by burning BNB. The contract is the sole issuer. No premine, no team allocation, no presale.

The burn is irreversible. Every BNB sent to the contract is permanently transferred to the dead address and removed from circulation.

The issuance schedule is Bitcoin's. The smart contract enforces it.

---

## ┌ mechanism

```
Round opens. Threshold = T BNB.
Participants send BNB to the contract. Weight = amount sent.
When accumulated burn ≥ T:
  → exactly one winner, selected by weighted draw
  → winner receives the full round reward
  → threshold adjusts, new round begins
```

---

## ┌ halvings

`reward = 12,000 cBNB >> era`, where `era = (round - 1) / 875`.

| Era | Reward/round | Era total |
|-----|-------------|-----------|
| 1 | 12,000 cBNB | 10,500,000 |
| 2 | 6,000 cBNB | 5,250,000 |
| 3 | 3,000 cBNB | 2,625,000 |
| 4 | 1,500 cBNB | 1,312,500 |
| 5+ | 750 cBNB | converges |

Cap is 21,000,000 cBNB. The halving series converges asymptotically; the contract truncates the final rounds to the remaining supply.

*We did not invent these numbers. We mapped them from Bitcoin, in the spirit of its original design.*

---

## ┌ difficulty

Every 8 rounds, the contract retargets:

```
next_threshold = old_threshold × (target_interval / actual_interval)
```

Clamped to ±4× per period. The global rate converges to 1 round per 4 hours.

---

## ┌ supply

```
total .................................................. 21,000,000 cBNB
premine / presale / team / airdrop ..................... 0
burn-to-earn · 100% .................................... 21,000,000 cBNB
```

---

## ┌ deployment

One Solidity file. One constructor call. No proxy. No upgrade. No admin. No `selfdestruct`.

If everyone who shipped this disappeared tonight, the contract would run tomorrow under the same rules. That is what "no operator" means. That is the feature.

---

## ┌ address

| | |
|---|---|
| contract | *(to be filled after deployment)* |
| chain | BNB Smart Chain (chainId 56) |
