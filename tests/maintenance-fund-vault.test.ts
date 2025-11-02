import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("Maintenance Fund Vault Tests", () => {
  it("should get initial total funds", () => {
    const result = simnet.callReadOnlyFn(
      "Maintenance-Fund-Vault",
      "get-total-funds",
      [],
      deployer
    );
    expect(result.result).toBeUint(0);
  });

  it("should allow contributions", () => {
    const result = simnet.callPublicFn(
      "Maintenance-Fund-Vault",
      "contribute",
      [Cl.uint(1000000)],
      deployer
    );
    expect(result.result).toBeOk(Cl.uint(1000000));
  });

  it("should create milestones", () => {
    const result = simnet.callPublicFn(
      "Maintenance-Fund-Vault",
      "create-milestone",
      [Cl.uint(5000000), Cl.uint(5), Cl.stringAscii("Test milestone")],
      deployer
    );
    expect(result.result).toBeOk(Cl.uint(1));
  });

  it("should verify new contract compiles", () => {
    const result = simnet.callReadOnlyFn(
      "Maintenance-Campaigns",
      "get-campaign",
      [Cl.uint(1)],
      deployer
    );
    expect(result.result).toBeNone();
  });
});
