// =====================================================================
// MIT 8103 - Portfolio 4: NoSQL and Advanced Data Models
// Case Study: SwiftPay Fintech Platform (MongoDB document model)
// File: 01_mongodb_setup.js
// Engine: MongoDB 7.0
// =====================================================================
//
// This script creates the MongoDB equivalent of the SwiftPay relational
// schema shown in Portfolio 1. The same business entities (customer,
// account, transaction) are modelled as JSON documents, using:
//
//   * Embedded sub-documents for tightly-coupled 1:few relationships
//     (e.g. a customer's KYC document, a transaction's audit events)
//   * Referencing (by _id) for many:1 relationships that need to be
//     queried independently (e.g. account -> customer)
//   * Arrays for 1:many relationships inside the parent's lifetime
//     (e.g. a customer's saved beneficiaries)
//
// Run with:  mongosh swiftpay 01_mongodb_setup.js
// =====================================================================

db = db.getSiblingDB('swiftpay');

// ---------------------------------------------------------------------
// Drop collections (idempotent re-run)
// ---------------------------------------------------------------------
db.customers.drop();
db.accounts.drop();
db.transactions.drop();
db.beneficiaries.drop();
db.audit_logs.drop();
db.transaction_types.drop();

// ---------------------------------------------------------------------
// Collections & JSON-schema validation
// (MongoDB 7 supports $jsonSchema validators - we use them to enforce
// the same NOT NULL / type / enum rules that the SQL CHECK constraints
// enforced in Portfolio 1.)
// ---------------------------------------------------------------------

db.createCollection("customers", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["first_name", "last_name", "email", "phone",
                       "date_of_birth", "national_id", "kyc"],
            properties: {
                first_name:    { bsonType: "string", maxLength: 50 },
                last_name:     { bsonType: "string", maxLength: 50 },
                email:         { bsonType: "string", pattern: "^.+@.+$" },
                phone:         { bsonType: "string" },
                date_of_birth: { bsonType: "date" },
                gender:        { enum: ["M", "F", "O"] },
                national_id:   { bsonType: "string" },
                address: {
                    bsonType: "object",
                    required: ["line1", "city"],
                    properties: {
                        line1:  { bsonType: "string" },
                        city:   { bsonType: "string" },
                        country:{ bsonType: "string" }
                    }
                },
                // EMBEDDED sub-document - KYC has no independent life
                // outside its customer; embedding avoids a join.
                kyc: {
                    bsonType: "object",
                    required: ["status"],
                    properties: {
                        status: { enum: ["PENDING", "VERIFIED", "REJECTED"] },
                        verified_at: { bsonType: ["date", "null"] },
                        verified_by: { bsonType: ["string", "null"] }
                    }
                },
                created_at: { bsonType: "date" },
                updated_at: { bsonType: "date" }
            }
        }
    }
});

db.createCollection("accounts", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["account_number", "customer_id", "account_type",
                       "balance", "status"],
            properties: {
                account_number: { bsonType: "string" },
                customer_id:    { bsonType: "objectId" },
                account_type:   { enum: ["SAVINGS", "CURRENT", "FIXED"] },
                balance:        { bsonType: "decimal" },
                currency:       { bsonType: "string", minLength: 3, maxLength: 3 },
                status:         { enum: ["ACTIVE", "DORMANT", "CLOSED", "FROZEN"] },
                branch: {
                    bsonType: "object",
                    properties: {
                        branch_id:   { bsonType: "long" },
                        branch_name: { bsonType: "string" },
                        branch_code: { bsonType: "string" }
                    }
                },
                opened_at: { bsonType: "date" },
                closed_at: { bsonType: ["date", "null"] }
            }
        }
    }
});

db.createCollection("transactions", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["reference_no", "amount", "type", "status",
                       "initiated_at"],
            properties: {
                reference_no: { bsonType: "string" },
                from_account: {
                    bsonType: ["object", "null"],
                    properties: {
                        account_id:   { bsonType: "objectId" },
                        account_no:   { bsonType: "string" },
                        customer_name:{ bsonType: "string" }
                    }
                },
                to_account: {
                    bsonType: ["object", "null"],
                    properties: {
                        account_id:   { bsonType: "objectId" },
                        account_no:   { bsonType: "string" },
                        customer_name:{ bsonType: "string" }
                    }
                },
                amount:   { bsonType: "decimal", minimum: 0 },
                currency: { bsonType: "string" },
                type:     { enum: ["TRF", "DEP", "WTH", "BIL", "REV"] },
                status:   { enum: ["PENDING", "COMPLETED", "FAILED", "REVERSED"] },
                channel:  { enum: ["WEB", "MOBILE", "ATM", "POS", "BRANCH", "API", "SYSTEM"] },
                description: { bsonType: "string" },
                initiated_at: { bsonType: "date" },
                completed_at: { bsonType: ["date", "null"] },
                // EMBEDDED audit events - they belong to this transaction
                // only and are always read together with it.
                audit_events: {
                    bsonType: "array",
                    items: {
                        bsonType: "object",
                        required: ["event_type", "occurred_at", "actor"],
                        properties: {
                            event_type: { enum: ["INITIATED", "AUTHORIZED",
                                                 "COMPLETED", "FAILED",
                                                 "REVERSED", "LOCKED", "UNLOCKED"] },
                            occurred_at: { bsonType: "date" },
                            actor:       { bsonType: "string" },
                            event_data:  { bsonType: "object" }
                        }
                    }
                }
            }
        }
    }
});

db.createCollection("beneficiaries");
db.createCollection("audit_logs");
db.createCollection("transaction_types");

print("Collections created with JSON-schema validators.");
printjson(db.getCollectionNames());

// =====================================================================
// End of 01_mongodb_setup.js
// =====================================================================
