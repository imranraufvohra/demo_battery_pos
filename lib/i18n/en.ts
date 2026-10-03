/*
  English dictionary = the source of truth. Every key here must also exist in ar.ts
  (TypeScript enforces this). Use {name} placeholders for values: t("hello", { name: "Ali" }).
  To translate a new screen: add keys here and in ar.ts, then use t("key").
*/
const en = {
  // ---- common ----
  "common.save": "Save",
  "common.cancel": "Cancel",
  "common.delete": "Delete",
  "common.edit": "Edit",
  "common.close": "Close",
  "common.search": "Search",
  "common.loading": "Loading",
  "common.email": "Email",
  "common.password": "Password",
  "common.language": "Language",

  // ---- navigation ----
  "nav.home": "Home",
  "nav.inventory": "Inventory",
  "nav.customers": "Customers",
  "nav.sales": "Sales",
  "nav.credit": "Credit / Due",
  "nav.suppliers": "Suppliers",
  "nav.purchases": "Purchases",
  "nav.payments": "Payments",
  "nav.expenses": "Expenses",
  "nav.reports": "Reports",
  "nav.batteryServices": "Battery services",
  "nav.scrap": "Scrap",
  "nav.assistant": "Assistant",
  "nav.activity": "Activity log",
  "nav.team": "Team",
  "nav.fbr": "FBR lists",
  "nav.more": "More",
  "nav.main": "Main",
  "nav.shop": "Shop",

  // ---- app shell ----
  "shell.homeAria": "{brand} home",
  "shell.searchPlaceholder": "Search stock, customers or bills",
  "shell.itemShort": "Item",
  "shell.customerShort": "Customer",
  "shell.newBill": "New bill",
  "shell.accountAria": "Account and more",
  "shell.quickActions": "Quick actions",
  "shell.signedIn": "Signed in",
  "shell.signedInRole": "Signed in · {role}",
  "shell.signedInAs": "Signed in as",
  "shell.signOut": "Sign out",
  "shell.signingOut": "Signing out",
  "shell.installApp": "Install app",
  "shell.iosHint": "On iPhone/iPad: tap the Share icon in Safari, then “Add to Home Screen”.",

  // ---- demo ----
  "demo.banner": "Demo with sample data. Resets every hour.",
  "demo.cta": "Get this for my business",

  // ---- roles ----
  "role.owner": "Owner",
  "role.counter_staff": "Counter staff",
  "role.accountant": "Accountant",

  // ---- quick actions ----
  "qa.newBill": "New bill",
  "qa.newBill.hint": "Sell to a customer",
  "qa.receiveStock": "Receive stock",
  "qa.receiveStock.hint": "Buy from a supplier",
  "qa.makePayment": "Make payment",
  "qa.makePayment.hint": "Pay a supplier",
  "qa.addExpense": "Add expense",
  "qa.addExpense.hint": "Log rent, salaries, fuel, etc.",
  "qa.addCustomer": "Add customer",
  "qa.addCustomer.hint": "Save a new customer",

  // ---- more page ----
  "more.assistant": "Assistant",
  "more.assistant.hint": "Ask about stock, sales or customers",
  "more.newBill": "New bill",
  "more.newBill.hint": "Make a sale and take payment",
  "more.credit": "Credit to collect",
  "more.credit.hint": "Who owes you money, and how much",
  "more.receiveStock": "Receive stock",
  "more.receiveStock.hint": "Record a new purchase bill",
  "more.makePayment": "Make payment",
  "more.makePayment.hint": "Pay a supplier, against a bill or on account",
  "more.suppliers": "Suppliers",
  "more.suppliers.hint": "Who you buy from, and what you owe",
  "more.purchaseBills": "Purchase bills",
  "more.purchaseBills.hint": "Stock received, by supplier",
  "more.payments": "Payments",
  "more.payments.hint": "Every payment made to suppliers",
  "more.addExpense": "Add expense",
  "more.addExpense.hint": "Log rent, salaries, fuel, or any other cost",
  "more.expenses": "Expenses",
  "more.expenses.hint": "Every business expense, by category",
  "more.customers": "Customers",
  "more.customers.hint": "Every saved customer",
  "more.reports": "Reports",
  "more.reports.hint": "Sales, cash closing and best sellers",
  "more.addItem": "Add item",
  "more.addItem.hint": "Add a battery, panel or accessory",
  "more.addCustomer": "Add customer",
  "more.addCustomer.hint": "Save a new customer",
  "more.lowStock": "Low stock",
  "more.lowStock.hint": "Items that need reordering",
  "more.batteryServices": "Battery services",
  "more.batteryServices.hint": "Charging slips and battery warranty claims",
  "more.scrap": "Scrap",
  "more.scrap.hint": "Old batteries taken in exchange, sold by weight",
  "more.activity": "Activity log",
  "more.activity.hint": "Who added, changed or deleted what, and when",
  "more.team": "Team",
  "more.team.hint": "Give staff and accountants their own logins",
  "more.fbr": "FBR lists",
  "more.fbr.hint": "Load HS codes, units and provinces for FBR bills",

  // ---- login ----
  "login.title": "Sign in",
  "login.subtitle": "Use the email and password set up for you by the shop owner.",
  "login.submit": "Sign in",
  "login.submitting": "Signing in",
  "login.badCredentials": "The email or password is wrong. Check both and try again.",
  "login.offline": "Could not reach the server. Check your internet and try again.",
} as const;

export type TKey = keyof typeof en;
export default en;
