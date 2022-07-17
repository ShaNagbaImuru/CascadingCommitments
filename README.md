# Cascading Commitments
Cascading commitments are a coordination primitive on the blockchain that help people create and fulfill compacts: agreements to do something only if other people also agree to do it. You can think of it a little like a version of Kickstarter where the people giving the donations pick their own personal funding goal.

This is an experiment. Any feedback is greatly appreciated.

## Example
Alice, Bob, and Carlos all want to donate to a project, but only if they think it will raise enough money to be successful.

* Alice can donate $100 and thinks the project needs $200 to succeed.
* Bob can donate $200 and thinks the project needs $300 to succeed.
* Carlos can donate $300 and thinks the project needs $600 to succeed.

If Alice, Bob, and Carlos cannot coordinate, then none of them will donate since their individual donations don't meet what they think is needed. But if they can coordinate, then they can realize they should all donate and be assured that the project will reach or exceed their bar for success. Cascading commitments are a technology for enabling that coordination.

## How it Works
- Users can register commitments of the form "I will contribute X units if that brings the total contributed to Y."
  - These commitments can involve holding resources in escrow. For each commitment, the user also provides a small (programatically determined) amount of native currency (e.g. ether) for the gas that will be spent to fulfill their commitment.
  - These commitments are fully revokable until fulfilled.
- Since these commitments are made publicly, it is trivial to programatically determine (off-chain) which subset of the commitments can be fulfilled together. Anyone can 'trigger' these fulfillments, with correctness being checked on-chain.
  - Since the caller triggering the commitments may end up paying high fees in terms of gas, they are reimbursed out of the previously set aside native currency.

## Provided Uses
- `CascadingDonation.sol` has contracts to manage donations (of native currency or ERC20 tokens).
- `CascadingERC721Purchase.sol` has a contract for minting NFTs: this may be useful, for instance, to assist projects in reaching their full capacity.

## Issues
- Since the gas reimbursement rates are set in contract creation, if gas fees go up the reimbursements may cease being attractive.
- There is no guarantee that the trigger call will include all levels that could be triggered-- in particular, it may 'skip' lower levels in favor of higher ones. This behavior is not logically incorrect but is arguably unfair.
- The provided contracts check the balance of the donation target to determine triggering thresholds; this is more accurate than relying only on donations from the contract itself, but is not robust to 'cheating' through e.g. flashloans.

## Future Work
- Reference implementation for a script to monitor contract events and determine possible trigger calls
- Gas optimization
- Implement more use cases (please contact us if you have one in mind)

## Other Uses
- **Voting**
  - Most chain voting is strict up/down, for which this is not useful.
  - I would hope that votes involving more than 2 options would not use first past the post; if they do, cascading commitments can help provide better voting structures (by serving as a delegate and allowing people to make commitments to their first-choice option).
  - They could also conceivably be used for a form of commitment or horse trading, i.e. registering a commitment to vote for X if Y passes.
- **Boycotts**: instead of individually divesting of a noxious asset, holders might want to divest only when they know that the collective sell-off will have a significant effect.
  - **Buycotts** work similarly.