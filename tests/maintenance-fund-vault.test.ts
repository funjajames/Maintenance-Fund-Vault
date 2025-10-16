import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";
import { initSimnet } from "@hirosystems/clarinet-sdk";

const simnet = await initSimnet();

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const deployerAddress = accounts.get("deployer")!;

describe("Maintenance Fund Vault Tests", () => {
  describe("Basic Functionality", () => {
    it("should allow contributions", () => {
      const contribution = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "contribute",
        [Cl.uint(1000000)], // 1 STX
        address1
      );
      expect(contribution.result).toBeOk(Cl.uint(1000000));
    });

    it("should track contributor balances", () => {
      simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "contribute",
        [Cl.uint(2000000)], // 2 STX
        address2
      );

      const balance = simnet.callReadOnlyFn(
        "Maintenance-Fund-Vault",
        "get-contributor-balance",
        [Cl.principal(address2)],
        address1
      );
      expect(balance.result).toBeUint(2000000);
    });

    it("should track total funds", () => {
      simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "contribute",
        [Cl.uint(500000)],
        address3
      );

      const totalFunds = simnet.callReadOnlyFn(
        "Maintenance-Fund-Vault",
        "get-total-funds",
        [],
        address1
      );
      expect(totalFunds.result).toBeUint(3500000); // Total from previous tests
    });
  });

  describe("Milestone System", () => {
    it("should allow owner to create milestones", () => {
      const milestone = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "create-milestone",
        [
          Cl.uint(5000000), // 5 STX target
          Cl.uint(5), // 5% reward
          Cl.asciiString("First milestone - Community Growth")
        ],
        deployerAddress
      );
      expect(milestone.result).toBeOk(Cl.uint(1));
    });

    it("should reject milestone creation by non-owner", () => {
      const milestone = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "create-milestone",
        [
          Cl.uint(10000000),
          Cl.uint(3),
          Cl.asciiString("Unauthorized milestone")
        ],
        address1
      );
      expect(milestone.result).toBeErr(Cl.uint(100)); // ERR_UNAUTHORIZED
    });

    it("should reject milestone with invalid reward percentage", () => {
      const milestone = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "create-milestone",
        [
          Cl.uint(5000000),
          Cl.uint(15), // Over 10% limit
          Cl.asciiString("Invalid reward milestone")
        ],
        deployerAddress
      );
      expect(milestone.result).toBeErr(Cl.uint(102)); // ERR_INVALID_AMOUNT
    });

    it("should calculate milestone rewards correctly", () => {
      // First, ensure we have enough contributions to meet the milestone
      simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "contribute",
        [Cl.uint(2000000)], // Add 2 STX to reach 5.5 STX total
        address1
      );

      const reward = simnet.callReadOnlyFn(
        "Maintenance-Fund-Vault",
        "calculate-milestone-reward",
        [Cl.uint(1), Cl.principal(address1)],
        address1
      );
      
      // Address1 contributed 3 STX total out of 5.5 STX, so 3 * 5% = 0.15 STX reward
      expect(reward.result).toBeOk(Cl.uint(150000));
    });

    it("should allow contributors to claim milestone rewards", () => {
      const claim = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "claim-milestone-reward",
        [Cl.uint(1)],
        address1
      );
      expect(claim.result).toBeOk(Cl.uint(150000));
    });

    it("should prevent double claiming of milestone rewards", () => {
      const doubleClaim = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "claim-milestone-reward",
        [Cl.uint(1)],
        address1
      );
      expect(doubleClaim.result).toBeErr(Cl.uint(108)); // ERR_MILESTONE_ALREADY_CLAIMED
    });

    it("should return milestone information", () => {
      const milestone = simnet.callReadOnlyFn(
        "Maintenance-Fund-Vault",
        "get-milestone",
        [Cl.uint(1)],
        address1
      );
      
      expect(milestone.result).toBeSome(
        Cl.tuple({
          "target-amount": Cl.uint(5000000),
          "reward-percentage": Cl.uint(5),
          "description": Cl.asciiString("First milestone - Community Growth"),
          "created-at": Cl.uint(simnet.blockHeight),
          "is-active": Cl.bool(true),
          "total-claimed": Cl.uint(150000)
        })
      );
    });

    it("should deactivate milestones", () => {
      const deactivate = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "deactivate-milestone",
        [Cl.uint(1)],
        deployerAddress
      );
      expect(deactivate.result).toBeOk(Cl.uint(1));

      // Verify milestone is deactivated
      const milestone = simnet.callReadOnlyFn(
        "Maintenance-Fund-Vault",
        "get-milestone",
        [Cl.uint(1)],
        address1
      );
      
      const milestoneData = milestone.result.expectSome();
      expect(milestoneData.expectTuple()["is-active"]).toBeBool(false);
    });
  });

  describe("Analytics", () => {
    it("should return milestone analytics", () => {
      const analytics = simnet.callReadOnlyFn(
        "Maintenance-Fund-Vault",
        "get-milestone-analytics",
        [],
        address1
      );
      
      expect(analytics.result).toBeTuple({
        "total-milestones-created": Cl.uint(1),
        "current-fund-level": Cl.uint(5500000), // Updated total
        "milestone-system-active": Cl.bool(true)
      });
    });

    it("should return active milestones info", () => {
      const activeMilestones = simnet.callReadOnlyFn(
        "Maintenance-Fund-Vault",
        "get-active-milestones",
        [],
        address1
      );
      
      expect(activeMilestones.result).toBeTuple({
        "current-funds": Cl.uint(5500000),
        "next-milestone-id": Cl.uint(2),
        "total-milestone-count": Cl.uint(1)
      });
    });

    it("should return enhanced contract info", () => {
      const contractInfo = simnet.callReadOnlyFn(
        "Maintenance-Fund-Vault",
        "get-contract-info",
        [],
        address1
      );
      
      const info = contractInfo.result.expectTuple();
      expect(info["next-milestone-id"]).toBeUint(2);
      expect(info["total-funds"]).toBeUint(5500000);
    });
  });

  describe("Maintenance Request System", () => {
    it("should allow maintenance request submission", () => {
      const request = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "submit-maintenance-request",
        [
          Cl.uint(1000000),
          Cl.asciiString("Fix community center roof")
        ],
        address2
      );
      expect(request.result).toBeOk(Cl.uint(1));
    });

    it("should allow voting on requests", () => {
      const vote = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "vote-on-request",
        [Cl.uint(1), Cl.bool(true)],
        address2
      );
      expect(vote.result).toBeOk(Cl.bool(true));
    });

    it("should calculate voting power correctly", () => {
      const votingPower = simnet.callReadOnlyFn(
        "Maintenance-Fund-Vault",
        "calculate-voting-power",
        [Cl.principal(address2)],
        address1
      );
      
      // Address2 contributed 2 STX out of 5.5 STX total = ~36.36%
      expect(votingPower.result).toBeUint(36);
    });
  });

  describe("Error Handling", () => {
    it("should reject zero contributions", () => {
      const contribution = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "contribute",
        [Cl.uint(0)],
        address1
      );
      expect(contribution.result).toBeErr(Cl.uint(102)); // ERR_INVALID_AMOUNT
    });

    it("should reject voting by non-contributors", () => {
      // Create a new request first
      simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "submit-maintenance-request",
        [Cl.uint(500000), Cl.asciiString("Test request")],
        address1
      );

      // Try to vote with an account that hasn't contributed
      const vote = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "vote-on-request",
        [Cl.uint(2), Cl.bool(true)],
        accounts.get("wallet_4")! // Fresh account with no contribution
      );
      expect(vote.result).toBeErr(Cl.uint(100)); // ERR_UNAUTHORIZED
    });

    it("should reject milestone claims when target not reached", () => {
      // Create a milestone with very high target
      simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "create-milestone",
        [
          Cl.uint(100000000), // 100 STX target - way higher than current funds
          Cl.uint(5),
          Cl.asciiString("High target milestone")
        ],
        deployerAddress
      );

      const claim = simnet.callPublicFn(
        "Maintenance-Fund-Vault",
        "claim-milestone-reward",
        [Cl.uint(2)],
        address2
      );
      expect(claim.result).toBeErr(Cl.uint(109)); // ERR_MILESTONE_NOT_REACHED
    });
  });
});