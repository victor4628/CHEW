import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const CHEW_RATE = 10n * 10n ** 18n; // 10 CHEW per 1 mUSDT

export default buildModule("CHEW", (m) => {
  const musdt = m.contract("MockUSDT");

  const chewToken = m.contract("CHEWToken", [musdt]);

  const restaurantAccounts = m.contract("RestaurantAccounts", [musdt, chewToken]);

  const governanceProposal = m.contract("GovernanceProposal", [chewToken, restaurantAccounts]);

  const menuVoting = m.contract("MenuVoting", [chewToken]);

  const crowdsale = m.contract("Crowdsale", [chewToken, musdt, restaurantAccounts, CHEW_RATE]);

  return { musdt, chewToken, restaurantAccounts, governanceProposal, menuVoting, crowdsale };
});
