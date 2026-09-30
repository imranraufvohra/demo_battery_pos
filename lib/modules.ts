/** Feature flags. The demo build hides Pakistan-only and risky screens; the code stays in the repo. */
export const DEMO_MODE = process.env.NEXT_PUBLIC_DEMO_MODE === "true";

export const MODULES = {
  inventory: true, customers: true, sales: true, credit: true,
  suppliers: true, purchases: true, payments: true, expenses: true, reports: true,
  batteryServices: true, // claims + charging = the differentiator
  scrap: true,
  assistant: process.env.NEXT_PUBLIC_AI_ENABLED !== "false",
  team: !DEMO_MODE,
  activityLog: !DEMO_MODE,
  fbr: process.env.NEXT_PUBLIC_FBR_ENABLED === "true", // Pakistan only, OFF by default
};

export const ROUTE_MODULE: Record<string, boolean> = {
  "/team": MODULES.team,
  "/activity": MODULES.activityLog,
  "/fbr": MODULES.fbr,
  "/assistant": MODULES.assistant,
};
