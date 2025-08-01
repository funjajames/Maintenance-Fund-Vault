# 🏗️ Maintenance Fund Vault

A decentralized smart contract for managing community maintenance funds with democratic voting mechanisms on the Stacks blockchain.

## 🌟 Features

- 💰 **Community Contributions**: Members can contribute STX to build a shared maintenance fund
- 📝 **Maintenance Requests**: Submit requests for maintenance work with detailed descriptions
- 🗳️ **Democratic Voting**: Token-weighted voting system for fund allocation decisions
- ⚡ **Automated Execution**: Approved requests can be executed by authorized vendors
- 🔒 **Security Controls**: Owner permissions and vendor approval system
- 📊 **Transparent Tracking**: Full visibility into fund balances and request status

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://docs.hiro.so/stacks/clarinet) installed
- Basic understanding of Stacks blockchain and Clarity smart contracts

### Installation

1. Clone this repository
2. Run `clarinet check` to verify contract compilation
3. Run `clarinet test` to execute test suite

## 📋 Contract Functions

### Public Functions

#### 💵 `contribute(amount)`
Contribute STX tokens to the maintenance fund
- **Parameters**: `amount` (uint) - Amount of STX to contribute
- **Returns**: Amount contributed

#### 📄 `submit-maintenance-request(amount, description)`
Submit a new maintenance request for community voting
- **Parameters**: 
  - `amount` (uint) - Requested funding amount
  - `description` (string-ascii 500) - Detailed description of maintenance work
- **Returns**: Request ID

#### 🗳️ `vote-on-request(request-id, vote-for)`
Vote on a pending maintenance request (voting power based on contribution)
- **Parameters**:
  - `request-id` (uint) - ID of the request to vote on
  - `vote-for` (bool) - true to approve, false to reject
- **Returns**: Vote preference

#### ✅ `finalize-request(request-id)`
Finalize voting and determine approval status (callable after voting period ends)
- **Parameters**: `request-id` (uint) - ID of request to finalize
- **Returns**: Final status ("approved" or "rejected")

#### 💸 `execute-approved-request(request-id)`
Execute an approved request and transfer funds (owner/vendor only)
- **Parameters**: `request-id` (uint) - ID of approved request
- **Returns**: Amount transferred

#### 🏦 `withdraw-contribution(amount)`
Withdraw up to 25% of your contribution
- **Parameters**: `amount` (uint) - Amount to withdraw
- **Returns**: Amount withdrawn

### Admin Functions (Owner Only)

#### 👥 `add-approved-vendor(vendor)`
Add a principal to the approved vendor list
- **Parameters**: `vendor` (principal) - Address to approve

#### ❌ `remove-approved-vendor(vendor)`
Remove a principal from approved vendor list
- **Parameters**: `vendor` (principal) - Address to remove

#### ⏰ `update-voting-duration(new-duration)`
Update the voting period duration (in blocks)
- **Parameters**: `new-duration` (uint) - New duration in blocks

#### 🚨 `emergency-withdraw()`
Emergency function to withdraw all funds (owner only)

### Read-Only Functions

#### 📊 `get-total-funds()`
Get current total fund balance

#### 💰 `get-contributor-balance(contributor)`
Get contribution balance for a specific address

#### 📋 `get-maintenance-request(request-id)`
Get full details of a maintenance request

#### ⏱️ `get-voting-duration()`
Get current voting period duration

#### ✅ `has-voted(request-id, voter)`
Check if an address has voted on a specific request

#### 🏪 `is-approved-vendor(vendor)`
Check if an address is an approved vendor

#### 📈 `calculate-voting-power(contributor)`
Calculate voting power percentage for a contributor

## 🔧 Usage Examples

### Contributing to the Fund
```clarity
(contract-call? .maintenance-fund-vault contribute u1000000) ;; Contribute 1 STX
```

### Submitting a Maintenance Request
```clarity
(contract-call? .maintenance-fund-vault submit-maintenance-request 
  u500000 
  "Repair roof leak in community center - materials and labor")
```

### Voting on a Request
```clarity
(contract-call? .maintenance-fund-vault vote-on-request u1 true) ;; Vote to approve request #1
```

### Checking Fund Status
```clarity
(contract-call? .maintenance-fund-vault get-total-funds) ;; Get current fund balance
```

## 🏛️ Governance Model

- **Voting Weight**: Proportional to STX contribution amount
- **Approval Threshold**: Requires majority of total fund value in "yes" votes
- **Voting Period**: Configurable duration (default: 144 blocks ≈ 24 hours)
- **Execution**: Only approved vendors or contract owner can execute approved requests

## 🔐 Security Features

- **Contribution Limits**: Withdrawals limited to 25% of individual contribution
- **Vendor Approval**: Only pre-approved vendors can execute maintenance requests
- **Time-Locked Voting**: Prevents vote manipulation with fixed voting periods
- **Emergency Controls**: Owner can emergency-withdraw funds if needed

## ⚠️ Important Notes

- Voting power is based on contribution amount
- Each address can only vote once per request
- Requests cannot be modified after submission
- Vendor approval is required for request execution
- Contract owner has administrative privileges

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests with `clarinet test`
5. Submit a pull request

## 📄 License

This project is open source and available under the MIT License.

---

Built with ❤️ for the Stacks ecosystem
