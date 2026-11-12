-- =====================================================================
-- MIT 8103 - Portfolio 1
-- File: 03_seed_data.sql  (Realistic sample data for SwiftPay)
-- Run AFTER 01_schema.sql and BEFORE 02_indexes.sql (or after - order
-- only affects load speed, not correctness).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Transaction types (reference / lookup table)
-- ---------------------------------------------------------------------
INSERT INTO transaction_type (type_name, type_code, description) VALUES
('Inter-account Transfer', 'TRF', 'Transfer between two SwiftPay accounts'),
('Deposit',                'DEP', 'Cash deposit into an account'),
('Withdrawal',             'WTH', 'Cash withdrawal from an account'),
('Bill Payment',           'BIL', 'Payment to a biller / merchant'),
('Reversal',               'REV', 'Reversal of a previously failed transaction');

-- ---------------------------------------------------------------------
-- Branches (3 Nigerian branches)
-- ---------------------------------------------------------------------
INSERT INTO branch (branch_name, branch_code, address, city, region, phone) VALUES
('SwiftPay Victoria Island', 'SPV01', '12 Akin Adesola Street', 'Lagos',   'South-West', '+234-1-270-0001'),
('SwiftPay Abuja Central',   'SPV02', '5 Adetokunbo Ademola Crescent', 'Abuja', 'FCT', '+234-9-290-0002'),
('SwiftPay Port Harcourt',   'SPV03', '21 Aba Road, GRA', 'Port Harcourt', 'South-South', '+234-84-260-0003');

-- ---------------------------------------------------------------------
-- Customers (10 KYC-verified retail customers)
-- ---------------------------------------------------------------------
INSERT INTO customer (first_name, last_name, email, phone, date_of_birth, gender, national_id, address, city, kyc_status) VALUES
('Chinwe',   'Okoro',     'chinwe.okoro@example.com',     '+234-803-100-0001', '1992-04-15', 'F', 'NG-NIN-100001', '7 Allen Avenue',       'Lagos',          'VERIFIED'),
('Tunde',    'Adeyemi',   'tunde.adeyemi@example.com',    '+234-803-100-0002', '1988-09-21', 'M', 'NG-NIN-100002', '14 Awolowo Road',       'Lagos',          'VERIFIED'),
('Aisha',    'Bello',     'aisha.bello@example.com',      '+234-803-100-0003', '1995-01-30', 'F', 'NG-NIN-100003', '42 Wuse 2 Crescent',    'Abuja',          'VERIFIED'),
('Emeka',    'Nwosu',     'emeka.nwosu@example.com',      '+234-803-100-0004', '1990-07-04', 'M', 'NG-NIN-100004', '9 Independence Avenue',  'Abuja',          'VERIFIED'),
('Grace',    'Eze',       'grace.eze@example.com',        '+234-803-100-0005', '1993-12-12', 'F', 'NG-NIN-100005', '18 Aba Road',           'Port Harcourt',  'VERIFIED'),
('Ibrahim',  'Musah',     'ibrahim.musah@example.com',    '+234-803-100-0006', '1985-03-19', 'M', 'NG-NIN-100006', '5 Garki Market Road',   'Abuja',          'VERIFIED'),
('Funke',    'Olatunji',  'funke.olatunji@example.com',   '+234-803-100-0007', '1996-06-08', 'F', 'NG-NIN-100007', '33 Yaba Road',          'Lagos',          'VERIFIED'),
('Daniel',   'Okafor',    'daniel.okafor@example.com',    '+234-803-100-0008', '1989-11-25', 'M', 'NG-NIN-100008', '2 Market Road',         'Port Harcourt',  'VERIFIED'),
('Blessing', 'Audu',      'blessing.audu@example.com',    '+234-803-100-0009', '1994-02-14', 'F', 'NG-NIN-100009', '8 Kaduna Road',         'Abuja',          'PENDING'),
('Samuel',   'Obi',       'samuel.obi@example.com',       '+234-803-100-0010', '1991-08-17', 'M', 'NG-NIN-100010', '27 Onitsha Road',       'Lagos',          'VERIFIED');

-- ---------------------------------------------------------------------
-- Accounts (12 accounts across the 3 branches)
-- The balances below are OPENING balances at go-live (2026-09-01).
-- After the transactions are loaded, balance is recomputed from them.
-- ---------------------------------------------------------------------
INSERT INTO account (account_number, customer_id, branch_id, account_type, balance, status, opened_at) VALUES
('SP0001110001', 1, 1, 'SAVINGS',  250000.00, 'ACTIVE',  '2022-03-10 09:00:00+01'),
('SP0001110002', 1, 1, 'CURRENT',   85000.00, 'ACTIVE',  '2022-03-10 09:05:00+01'),
('SP0001110003', 2, 1, 'SAVINGS',  430000.00, 'ACTIVE',  '2021-11-22 10:30:00+01'),
('SP0001110004', 3, 2, 'SAVINGS',  120000.00, 'ACTIVE',  '2023-01-15 11:20:00+01'),
('SP0001110005', 4, 2, 'CURRENT',  670000.00, 'ACTIVE',  '2020-08-05 14:00:00+01'),
('SP0001110006', 5, 3, 'SAVINGS',   95000.00, 'ACTIVE',  '2023-06-08 09:45:00+01'),
('SP0001110007', 6, 2, 'FIXED',   1500000.00, 'ACTIVE',  '2022-09-01 08:00:00+01'),
('SP0001110008', 7, 1, 'SAVINGS',  310000.00, 'ACTIVE',  '2022-12-19 13:15:00+01'),
('SP0001110009', 8, 3, 'CURRENT',  -15000.00, 'ACTIVE',  '2021-04-02 10:10:00+01'),  -- overdraft
('SP0001110010', 9, 2, 'SAVINGS',   10000.00, 'DORMANT', '2023-02-28 16:00:00+01'),
('SP0001110011',10, 1, 'SAVINGS',  520000.00, 'ACTIVE',  '2021-07-13 09:30:00+01'),
('SP0001110012',10, 1, 'CURRENT',  180000.00, 'ACTIVE',  '2021-07-13 09:35:00+01');

-- ---------------------------------------------------------------------
-- Transactions (35 transactions across all 5 types)
-- ---------------------------------------------------------------------
INSERT INTO transaction (reference_no, from_account_id, to_account_id, amount, type_id, status, channel, description, initiated_at, completed_at) VALUES
('TXN-20260901-001', 2, 1,    50000.00, 1, 'COMPLETED', 'WEB',    'Salary split',            '2026-09-01 08:15:00+01', '2026-09-01 08:15:02+01'),
('TXN-20260901-002', 3, 1,    20000.00, 1, 'COMPLETED', 'MOBILE', 'Rent share',              '2026-09-02 19:40:00+01', '2026-09-02 19:40:03+01'),
('TXN-20260903-003', NULL, 1, 30000.00, 2, 'COMPLETED', 'BRANCH', 'Cash deposit - VI',       '2026-09-03 10:00:00+01', '2026-09-03 10:00:05+01'),
('TXN-20260903-004', 1, NULL, 10000.00, 3, 'COMPLETED', 'ATM',    'ATM withdrawal VI',       '2026-09-03 11:20:00+01', '2026-09-03 11:20:04+01'),
('TXN-20260904-005', 5, 4,   100000.00, 1, 'COMPLETED', 'WEB',    'Business payment',        '2026-09-04 14:05:00+01', '2026-09-04 14:05:03+01'),
('TXN-20260905-006', 8, 7,    25000.00, 1, 'COMPLETED', 'MOBILE', 'Family support',          '2026-09-05 17:30:00+01', '2026-09-05 17:30:02+01'),
('TXN-20260906-007', NULL, 6, 15000.00, 2, 'COMPLETED', 'BRANCH', 'Cash deposit PH',         '2026-09-06 09:15:00+01', '2026-09-06 09:15:05+01'),
('TXN-20260907-008', 11,12,   80000.00, 1, 'COMPLETED', 'WEB',    'Transfer to current acct','2026-09-07 13:00:00+01', '2026-09-07 13:00:03+01'),
('TXN-20260908-009', 12,11,   20000.00, 1, 'COMPLETED', 'API',    'Refund',                  '2026-09-08 16:45:00+01', '2026-09-08 16:45:02+01'),
('TXN-20260909-010', 9, NULL, 5000.00,  3, 'COMPLETED', 'POS',    'POS purchase Shoprite',   '2026-09-09 12:10:00+01', '2026-09-09 12:10:03+01'),
('TXN-20260910-011', 5, 1,    12000.00, 4, 'COMPLETED', 'MOBILE', 'DSTV subscription',       '2026-09-10 20:00:00+01', '2026-09-10 20:00:02+01'),
('TXN-20260911-012', 3, 8,    45000.00, 1, 'COMPLETED', 'WEB',    'Gift',                    '2026-09-11 18:30:00+01', '2026-09-11 18:30:03+01'),
('TXN-20260912-013', NULL, 5, 75000.00, 2, 'COMPLETED', 'BRANCH', 'Cash deposit Abuja',      '2026-09-12 10:45:00+01', '2026-09-12 10:45:05+01'),
('TXN-20260913-014', 1, 4,    8000.00,  1, 'COMPLETED', 'MOBILE', 'Airline ticket refund',   '2026-09-13 15:20:00+01', '2026-09-13 15:20:02+01'),
('TXN-20260914-015', 5, NULL, 22000.00, 3, 'COMPLETED', 'ATM',    'ATM withdrawal Abuja',    '2026-09-14 09:00:00+01', '2026-09-14 09:00:04+01'),
('TXN-20260915-016', 12,3,    50000.00, 1, 'COMPLETED', 'WEB',    'Loan repayment',          '2026-09-15 11:30:00+01', '2026-09-15 11:30:03+01'),
('TXN-20260916-017', 1, 8,    35000.00, 1, 'COMPLETED', 'API',    'Transfer',                '2026-09-16 19:10:00+01', '2026-09-16 19:10:02+01'),
('TXN-20260917-018', 8, NULL, 4000.00,  3, 'COMPLETED', 'POS',    'POS purchase SPAR',       '2026-09-17 13:45:00+01', '2026-09-17 13:45:03+01'),
('TXN-20260918-019', NULL, 7, 50000.00, 2, 'COMPLETED', 'BRANCH', 'Fixed deposit topup',     '2026-09-18 08:30:00+01', '2026-09-18 08:30:05+01'),
('TXN-20260919-020', 11,1,    10000.00, 1, 'COMPLETED', 'MOBILE', 'Transfer to Chinwe',      '2026-09-19 22:00:00+01', '2026-09-19 22:00:02+01'),
('TXN-20260920-021', 5, 4,    60000.00, 1, 'COMPLETED', 'WEB',    'Consulting fee',          '2026-09-20 14:50:00+01', '2026-09-20 14:50:03+01'),
('TXN-20260921-022', 3, NULL, 90000.00, 3, 'COMPLETED', 'ATM',    'ATM withdrawal VI',       '2026-09-21 09:30:00+01', '2026-09-21 09:30:04+01'),
('TXN-20260922-023', 12,11,   30000.00, 1, 'COMPLETED', 'API',    'Transfer',                '2026-09-22 17:15:00+01', '2026-09-22 17:15:02+01'),
('TXN-20260923-024', 1, 4,    5000.00,  4, 'COMPLETED', 'MOBILE', 'EKEDC prepaid meter',     '2026-09-23 08:00:00+01', '2026-09-23 08:00:02+01'),
('TXN-20260924-025', 8, 7,    15000.00, 1, 'COMPLETED', 'WEB',    'Family support',          '2026-09-24 21:00:00+01', '2026-09-24 21:00:03+01'),
('TXN-20260925-026', 11,6,    20000.00, 1, 'COMPLETED', 'MOBILE', 'Transfer',                '2026-09-25 16:30:00+01', '2026-09-25 16:30:02+01'),
('TXN-20260926-027', 5, NULL, 100000.00,3, 'COMPLETED', 'ATM',    'ATM withdrawal VI',       '2026-09-26 12:00:00+01', '2026-09-26 12:00:04+01'),
('TXN-20260927-028', NULL, 1, 25000.00, 2, 'COMPLETED', 'BRANCH', 'Cash deposit VI',         '2026-09-27 10:30:00+01', '2026-09-27 10:30:05+01'),
('TXN-20260928-029', 3, 1,    18000.00, 1, 'COMPLETED', 'WEB',    'Loan contribution',       '2026-09-28 14:15:00+01', '2026-09-28 14:15:03+01'),
('TXN-20260929-030', 1, NULL, 7500.00,  3, 'COMPLETED', 'POS',    'POS purchase',            '2026-09-29 18:45:00+01', '2026-09-29 18:45:03+01'),
('TXN-20260930-031', 12,3,    22000.00, 1, 'COMPLETED', 'MOBILE', 'Transfer',                '2026-09-30 20:30:00+01', '2026-09-30 20:30:02+01'),
('TXN-20261001-032', 5, 4,    45000.00, 1, 'COMPLETED', 'WEB',    'Consulting fee',          '2026-10-01 11:00:00+01', '2026-10-01 11:00:03+01'),
('TXN-20261002-033', 1, 8,    9000.00,  1, 'REVERSED',  'WEB',    'Sent in error - reversed','2026-10-02 13:00:00+01', '2026-10-02 13:00:02+01'),
('TXN-20261003-034', 8, 7,    12000.00, 1, 'COMPLETED', 'MOBILE', 'Transfer',                '2026-10-03 09:20:00+01', '2026-10-03 09:20:02+01'),
('TXN-20261004-035', NULL, 1, 18000.00, 2, 'COMPLETED', 'BRANCH', 'Cash deposit VI',         '2026-10-04 10:00:00+01', '2026-10-04 10:00:05+01');

-- ---------------------------------------------------------------------
-- Reversal of TXN-20261002-033 (completed, then reported as sent in error).
-- A reversal moves the same amount back in the opposite direction (8 -> 1).
-- trg_reversal_valid rejects reversals of FAILED/PENDING transactions.
-- ---------------------------------------------------------------------
INSERT INTO transaction (reference_no, from_account_id, to_account_id, amount, type_id, status, channel, description, initiated_at, completed_at, reversal_of)
VALUES ('TXN-20261002-033R', 8, 1, 9000.00, 5, 'COMPLETED', 'SYSTEM', 'Reversal: sent in error', '2026-10-02 13:01:00+01', '2026-10-02 13:01:02+01',
        (SELECT transaction_id FROM transaction WHERE reference_no = 'TXN-20261002-033'));

-- ---------------------------------------------------------------------
-- Transaction log entries (audit trail for ~5 sample transactions)
-- ---------------------------------------------------------------------
INSERT INTO transaction_log (transaction_id, event_type, event_data, actor, occurred_at) VALUES
(1, 'INITIATED',  '{"channel":"WEB","amount":50000,"from":2,"to":1}'::jsonb, 'mobile_app_user_1', '2026-09-01 08:15:00+01'),
(1, 'AUTHORIZED', '{"auth":"pin"}'::jsonb,                              'auth_service',      '2026-09-01 08:15:01+01'),
(1, 'COMPLETED',  '{"balance_after_from":35000,"balance_after_to":300000}'::jsonb, 'txn_engine','2026-09-01 08:15:02+01'),
(33,'INITIATED',  '{"channel":"WEB","amount":9000,"from":1,"to":8}'::jsonb,'mobile_app_user_1','2026-10-02 13:00:00+01'),
(33,'COMPLETED',  '{"amount":9000}'::jsonb,                            'txn_engine',         '2026-10-02 13:00:02+01'),
(33,'REVERSED',   '{"reason":"sent_in_error","reversal_ref":"TXN-20261002-033R"}'::jsonb,'customer_care_agent_4','2026-10-02 13:01:00+01'),
(36,'INITIATED',  '{"channel":"SYSTEM","reversal_of":33}'::jsonb,         'txn_engine',         '2026-10-02 13:01:00+01'),
(36,'COMPLETED',  '{"reversal_reason":"sent_in_error"}'::jsonb,            'txn_engine',         '2026-10-02 13:01:02+01');

-- ---------------------------------------------------------------------
-- Beneficiaries (saved payees)
-- ---------------------------------------------------------------------
INSERT INTO beneficiary (customer_id, beneficiary_account_id, beneficiary_name, bank_code, nickname) VALUES
(1, 3, 'Tunde Adeyemi',   'SPV01', 'Tunde - rent'),
(1, 8, 'Funke Olatunji',  'SPV01', 'Funke - gift'),
(2, 1, 'Chinwe Okoro',    'SPV01', 'Chinwe'),
(5, 4, 'Aisha Bello',     'SPV02', 'Aisha - business'),
(7, 1, 'Chinwe Okoro',    'SPV01', 'Mum');

-- ---------------------------------------------------------------------
-- Cards (hash columns filled with placeholder SHA-256-like strings)
-- ---------------------------------------------------------------------
INSERT INTO card (card_number_hash, customer_id, account_id, card_type, expiry_date) VALUES
('5f4dcc3b5aa765d61d8327deb882cf99a8c7e5b1d1e6b4c2f9a3e7d8b1c5a9f0', 1, 1, 'DEBIT',  '2028-12-31'),
('e10adc3949ba59abbe56e057f20f883e67c3b8e5b1d1e6b4c2f9a3e7d8b1c5a9', 2, 3, 'DEBIT',  '2027-06-30'),
('25d55ad283aa400af464c76d713c07ad08e7b8e5b1d1e6b4c2f9a3e7d8b1c5a9', 3, 4, 'DEBIT',  '2028-03-31'),
('d8578edf8458ce06fbc5bb76a58c5ca42e8a7e3c9b2d1f0a3e5b7c8d9e0f1a2b', 4, 5, 'CREDIT', '2029-01-31'),
('48264c2fa9b75e7c6e6b8e5d1c2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a', 5, 5, 'DEBIT',  '2028-09-30');

-- ---------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------
INSERT INTO notification (customer_id, message, channel, status, created_at, sent_at) VALUES
(1, 'Credit alert: NGN 50,000 from SP0001110002',                'SMS',   'DELIVERED', '2026-09-01 08:15:03+01', '2026-09-01 08:15:05+01'),
(1, 'Credit alert: NGN 20,000 from SP0001110003',                'PUSH',  'DELIVERED', '2026-09-02 19:40:03+01', '2026-09-02 19:40:04+01'),
(1, 'Credit alert: NGN 30,000 cash deposit',                     'EMAIL', 'DELIVERED', '2026-09-03 10:00:06+01', '2026-09-03 10:00:30+01'),
(2, 'Debit alert: NGN 20,000 to SP0001110001',                   'SMS',   'DELIVERED', '2026-09-02 19:40:04+01', '2026-09-02 19:40:06+01'),
(4, 'Credit alert: NGN 100,000 from SP0001110005',               'SMS',   'DELIVERED', '2026-09-04 14:05:04+01', '2026-09-04 14:05:06+01'),
(1, 'Debit alert: NGN 9,000 to SP0001110008 (TXN-20261002-033)',   'SMS',   'DELIVERED', '2026-10-02 13:00:02+01', '2026-10-02 13:00:04+01'),
(1, 'Reversal TXN-20261002-033R: NGN 9,000 returned to your account',           'PUSH',  'DELIVERED', '2026-10-02 13:01:03+01', '2026-10-02 13:01:04+01');

-- ---------------------------------------------------------------------
-- Derive current balances from the ledger of COMPLETED movements:
--   balance = opening_balance + credits - debits
-- (REVERSED originals and their reversal rows both count, so they net to 0.)
-- ---------------------------------------------------------------------
UPDATE account SET opening_balance = balance;
UPDATE account a
   SET balance = a.opening_balance
               + COALESCE((SELECT SUM(amount) FROM transaction t
                            WHERE t.to_account_id = a.account_id
                              AND t.status IN ('COMPLETED','REVERSED')), 0)
               - COALESCE((SELECT SUM(amount) FROM transaction t
                            WHERE t.from_account_id = a.account_id
                              AND t.status IN ('COMPLETED','REVERSED')), 0);

COMMIT;

-- Integrity check: must return 0 rows
SELECT a.account_number, a.balance,
       a.opening_balance
     + COALESCE((SELECT SUM(amount) FROM transaction t WHERE t.to_account_id   = a.account_id AND t.status IN ('COMPLETED','REVERSED')),0)
     - COALESCE((SELECT SUM(amount) FROM transaction t WHERE t.from_account_id = a.account_id AND t.status IN ('COMPLETED','REVERSED')),0)
       AS expected
FROM account a
WHERE a.balance <> a.opening_balance
     + COALESCE((SELECT SUM(amount) FROM transaction t WHERE t.to_account_id   = a.account_id AND t.status IN ('COMPLETED','REVERSED')),0)
     - COALESCE((SELECT SUM(amount) FROM transaction t WHERE t.from_account_id = a.account_id AND t.status IN ('COMPLETED','REVERSED')),0);

-- =====================================================================
-- End of seed data
-- =====================================================================
