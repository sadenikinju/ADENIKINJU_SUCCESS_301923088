// =====================================================================
// MIT 8103 - Portfolio 4: NoSQL MongoDB - seed data & queries
// File: 02_mongodb_data_and_queries.js
// =====================================================================

db = db.getSiblingDB('swiftpay');

// ---------------------------------------------------------------------
// Seed: transaction types (small reference collection)
// ---------------------------------------------------------------------
db.transaction_types.insertMany([
    { type_code: "TRF", type_name: "Inter-account Transfer" },
    { type_code: "DEP", type_name: "Deposit" },
    { type_code: "WTH", type_name: "Withdrawal" },
    { type_code: "BIL", type_name: "Bill Payment" },
    { type_code: "REV", type_name: "Reversal" }
]);

// ---------------------------------------------------------------------
// Seed: customers (with embedded KYC + embedded address)
// ---------------------------------------------------------------------
db.customers.insertMany([
    {
        first_name: "Chinwe", last_name: "Okoro",
        email: "chinwe.okoro@example.com",
        phone: "+234-803-100-0001",
        date_of_birth: ISODate("1992-04-15"),
        gender: "F",
        national_id: "NG-NIN-100001",
        address: { line1: "7 Allen Avenue", city: "Lagos", country: "Nigeria" },
        kyc: { status: "VERIFIED", verified_at: ISODate("2022-03-09"), verified_by: "ops_user_3" },
        created_at: ISODate("2022-03-10T08:00:00Z")
    },
    {
        first_name: "Tunde", last_name: "Adeyemi",
        email: "tunde.adeyemi@example.com",
        phone: "+234-803-100-0002",
        date_of_birth: ISODate("1988-09-21"),
        gender: "M",
        national_id: "NG-NIN-100002",
        address: { line1: "14 Awolowo Road", city: "Lagos", country: "Nigeria" },
        kyc: { status: "VERIFIED", verified_at: ISODate("2021-11-21"), verified_by: "ops_user_2" },
        created_at: ISODate("2021-11-22T10:00:00Z")
    },
    {
        first_name: "Aisha", last_name: "Bello",
        email: "aisha.bello@example.com",
        phone: "+234-803-100-0003",
        date_of_birth: ISODate("1995-01-30"),
        gender: "F",
        national_id: "NG-NIN-100003",
        address: { line1: "42 Wuse 2 Crescent", city: "Abuja", country: "Nigeria" },
        kyc: { status: "VERIFIED", verified_at: ISODate("2023-01-14"), verified_by: "ops_user_1" },
        created_at: ISODate("2023-01-15T11:00:00Z")
    },
    {
        first_name: "Emeka", last_name: "Nwosu",
        email: "emeka.nwosu@example.com",
        phone: "+234-803-100-0004",
        date_of_birth: ISODate("1990-07-04"),
        gender: "M",
        national_id: "NG-NIN-100004",
        address: { line1: "9 Independence Avenue", city: "Abuja", country: "Nigeria" },
        kyc: { status: "VERIFIED", verified_at: ISODate("2020-08-04"), verified_by: "ops_user_2" },
        created_at: ISODate("2020-08-05T13:00:00Z")
    }
]);

// Cache the inserted customer _ids so we can reference them below.
const c1 = db.customers.findOne({ email: "chinwe.okoro@example.com" })._id;
const c2 = db.customers.findOne({ email: "tunde.adeyemi@example.com" })._id;
const c3 = db.customers.findOne({ email: "aisha.bello@example.com" })._id;
const c4 = db.customers.findOne({ email: "emeka.nwosu@example.com" })._id;

// ---------------------------------------------------------------------
// Seed: accounts (referencing customers by _id, embedding branch info)
// ---------------------------------------------------------------------
db.accounts.insertMany([
    {
        account_number: "SP0001110001", customer_id: c1, account_type: "SAVINGS",
        balance: NumberDecimal("225500.00"), currency: "NGN", status: "ACTIVE",
        branch: { branch_id: NumberLong(1), branch_name: "SwiftPay Victoria Island", branch_code: "SPV01" },
        opened_at: ISODate("2022-03-10T08:00:00Z"), closed_at: null
    },
    {
        account_number: "SP0001110002", customer_id: c1, account_type: "CURRENT",
        balance: NumberDecimal("85000.00"), currency: "NGN", status: "ACTIVE",
        branch: { branch_id: NumberLong(1), branch_name: "SwiftPay Victoria Island", branch_code: "SPV01" },
        opened_at: ISODate("2022-03-10T08:05:00Z"), closed_at: null
    },
    {
        account_number: "SP0001110003", customer_id: c2, account_type: "SAVINGS",
        balance: NumberDecimal("437500.00"), currency: "NGN", status: "ACTIVE",
        branch: { branch_id: NumberLong(1), branch_name: "SwiftPay Victoria Island", branch_code: "SPV01" },
        opened_at: ISODate("2021-11-22T09:30:00Z"), closed_at: null
    },
    {
        account_number: "SP0001110004", customer_id: c3, account_type: "SAVINGS",
        balance: NumberDecimal("120000.00"), currency: "NGN", status: "ACTIVE",
        branch: { branch_id: NumberLong(2), branch_name: "SwiftPay Abuja Central", branch_code: "SPV02" },
        opened_at: ISODate("2023-01-15T11:20:00Z"), closed_at: null
    },
    {
        account_number: "SP0001110005", customer_id: c4, account_type: "CURRENT",
        balance: NumberDecimal("670000.00"), currency: "NGN", status: "ACTIVE",
        branch: { branch_id: NumberLong(2), branch_name: "SwiftPay Abuja Central", branch_code: "SPV02" },
        opened_at: ISODate("2020-08-05T14:00:00Z"), closed_at: null
    }
]);

const a1 = db.accounts.findOne({ account_number: "SP0001110001" });
const a2 = db.accounts.findOne({ account_number: "SP0001110003" });
const a4 = db.accounts.findOne({ account_number: "SP0001110004" });
const a5 = db.accounts.findOne({ account_number: "SP0001110005" });

// ---------------------------------------------------------------------
// Seed: transactions
// NOTE: We DENORMALISE by embedding a small snapshot of the from/to
// account inside each transaction. This is the classic "snapshot pattern"
// described in MongoDB Applied Design Patterns (K. Banker, O'Reilly 2020):
// freeze the parties' identifying fields at txn time so that even if the
// account is later closed or renamed, the historical transaction remains
// self-describing.
// ---------------------------------------------------------------------
db.transactions.insertMany([
    {
        reference_no: "TXN-20260901-001",
        from_account: { account_id: a2._id, account_no: a2.account_number, customer_name: "Tunde Adeyemi" },
        to_account:   { account_id: a1._id, account_no: a1.account_number, customer_name: "Chinwe Okoro" },
        amount: NumberDecimal("50000.00"), currency: "NGN",
        type: "TRF", status: "COMPLETED", channel: "WEB",
        description: "Salary split",
        initiated_at: ISODate("2026-09-01T07:15:00Z"),
        completed_at: ISODate("2026-09-01T07:15:02Z"),
        audit_events: [
            { event_type: "INITIATED",  occurred_at: ISODate("2026-09-01T07:15:00Z"), actor: "mobile_app_user_2" },
            { event_type: "AUTHORIZED", occurred_at: ISODate("2026-09-01T07:15:01Z"), actor: "auth_service",
              event_data: { auth_method: "pin" } },
            { event_type: "COMPLETED",  occurred_at: ISODate("2026-09-01T07:15:02Z"), actor: "txn_engine",
              event_data: { balance_after_from: 380000, balance_after_to: 275500 } }
        ]
    },
    {
        reference_no: "TXN-20260904-005",
        from_account: { account_id: a5._id, account_no: a5.account_number, customer_name: "Emeka Nwosu" },
        to_account:   { account_id: a4._id, account_no: a4.account_number, customer_name: "Aisha Bello" },
        amount: NumberDecimal("100000.00"), currency: "NGN",
        type: "TRF", status: "COMPLETED", channel: "WEB",
        description: "Business payment",
        initiated_at: ISODate("2026-09-04T13:05:00Z"),
        completed_at: ISODate("2026-09-04T13:05:03Z"),
        audit_events: [
            { event_type: "INITIATED", occurred_at: ISODate("2026-09-04T13:05:00Z"), actor: "web_user_4" },
            { event_type: "COMPLETED", occurred_at: ISODate("2026-09-04T13:05:03Z"), actor: "txn_engine" }
        ]
    },
    {
        reference_no: "TXN-20261002-033",
        from_account: { account_id: a1._id, account_no: a1.account_number, customer_name: "Chinwe Okoro" },
        to_account:   { account_id: a2._id, account_no: a2.account_number, customer_name: "Tunde Adeyemi" },
        amount: NumberDecimal("9000.00"), currency: "NGN",
        type: "TRF", status: "FAILED", channel: "WEB",
        description: "Failed - insufficient",
        initiated_at: ISODate("2026-10-02T12:00:00Z"),
        completed_at: null,
        audit_events: [
            { event_type: "INITIATED", occurred_at: ISODate("2026-10-02T12:00:00Z"), actor: "mobile_app_user_1" },
            { event_type: "FAILED",    occurred_at: ISODate("2026-10-02T12:00:01Z"), actor: "txn_engine",
              event_data: { reason: "insufficient_funds", balance: 4500 } }
        ]
    }
]);

print("Seed data inserted.");
print("customers:    " + db.customers.countDocuments());
print("accounts:     " + db.accounts.countDocuments());
print("transactions: " + db.transactions.countDocuments());

// =====================================================================
// Indexes  (mirrors the rationale from Portfolio 1 / 2)
// =====================================================================
db.customers.createIndex({ email: 1 }, { unique: true });
db.customers.createIndex({ phone: 1 }, { unique: true });
db.customers.createIndex({ "kyc.status": 1 });

db.accounts.createIndex({ account_number: 1 }, { unique: true });
db.accounts.createIndex({ customer_id: 1 });
db.accounts.createIndex({ status: 1 });

// Compound index on the embedded from_account sub-doc fields.
// Supports the "statement for account X in date range" query.
db.transactions.createIndex({ "from_account.account_no": 1, initiated_at: -1 });
db.transactions.createIndex({ "to_account.account_no": 1,   initiated_at: -1 });
db.transactions.createIndex({ reference_no: 1 }, { unique: true });
db.transactions.createIndex({ status: 1, initiated_at: -1 });
db.transactions.createIndex({ amount: -1 });

// Time-series-style collection for audit logs (MongoDB 5+ timeseries)
// (alternative to embedding audit_events when audit volume is huge)
db.audit_logs.createIndex({ transaction_id: 1, occurred_at: 1 });
db.audit_logs.createIndex({ event_type: 1, occurred_at: -1 });

print("Indexes created.");

// =====================================================================
// Queries - the MongoDB equivalent of Portfolio 2's SQL queries
// =====================================================================

print("\n--- Q1. Account statement (account SP0001110001, Sep 2026) ---");
db.transactions.find({
    $or: [
        { "from_account.account_no": "SP0001110001" },
        { "to_account.account_no":   "SP0001110001" }
    ],
    status: "COMPLETED",
    initiated_at: { $gte: ISODate("2026-09-01"), $lt: ISODate("2026-10-05") }
}).sort({ initiated_at: -1 }).pretty();

print("\n--- Q2. Top 3 customers by transaction volume ---");
db.transactions.aggregate([
    { $match: { status: "COMPLETED" } },
    { $group: {
        _id: "$from_account.customer_name",
        transaction_count: { $sum: 1 },
        total_volume: { $sum: { $toDecimal: "$amount" } }
    }},
    { $sort: { total_volume: -1 } },
    { $limit: 3 }
]).pretty();

print("\n--- Q3. Daily totals by transaction type ---");
db.transactions.aggregate([
    { $match: { status: "COMPLETED", initiated_at: { $gte: ISODate("2026-09-01") } } },
    { $group: {
        _id: { day: { $dateToString: { format: "%Y-%m-%d", date: "$initiated_at" } },
               type: "$type" },
        count: { $sum: 1 },
        total: { $sum: { $toDecimal: "$amount" } }
    }},
    { $sort: { "_id.day": -1, total: -1 } }
]).pretty();

print("\n--- Q4. Suspicious transactions: amount > 100000 OR off-hours ---");
db.transactions.find({
    status: "COMPLETED",
    $or: [
        { amount: { $gt: NumberDecimal("100000") } },
        { initiated_at: { $not: { $gte: ISODate("2026-09-01T06:00:00Z") } } }
    ]
}).sort({ amount: -1 }).pretty();

print("\n--- Q5. Lookup by reference number ---");
db.transactions.findOne({ reference_no: "TXN-20260901-001" });

print("\n--- Q6. Customer with embedded accounts summary (single query) ---");
// We embed a tiny summary inside the customer document via $lookup.
db.customers.aggregate([
    { $match: { email: "chinwe.okoro@example.com" } },
    { $lookup: {
        from: "accounts",
        localField: "_id",
        foreignField: "customer_id",
        as: "accounts"
    }},
    { $project: {
        name: { $concat: ["$first_name", " ", "$last_name"] },
        email: 1,
        kyc_status: "$kyc.status",
        account_count: { $size: "$accounts" },
        total_balance: { $sum: "$accounts.balance" }
    }}
]).pretty();

// =====================================================================
// End of 02_mongodb_data_and_queries.js
// =====================================================================
