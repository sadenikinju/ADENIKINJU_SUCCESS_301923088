// P4 - bulk data (40,000 transactions) + COLLSCAN -> IXSCAN index demo. Run: mongosh swiftpay --quiet 03_bulk_and_index_demo.js
db = db.getSiblingDB('swiftpay');
const TARGET = 40000;
if (db.transactions.countDocuments() < TARGET) {
  const types = ['TRF','TRF','TRF','DEP','WTH','BIL'], chans = ['WEB','MOBILE','ATM','POS','BRANCH'];
  const statuses = ['COMPLETED','COMPLETED','COMPLETED','COMPLETED','PENDING','FAILED'];
  const base = new Date('2026-09-01T06:00:00Z').getTime();
  let batch = [];
  for (let i = 1; i <= TARGET; i++) {
    const from = 'SP' + String(1000000 + (i * 7919) % 2000).padStart(8, '0');
    const to   = 'SP' + String(1000000 + (i * 104729) % 2000).padStart(8, '0');
    const t = new Date(base + (i * 61000) % (90 * 86400000));
    batch.push({
      reference_no: 'TXN-BULK-' + String(i).padStart(6, '0'),
      from_account: { account_no: from }, to_account: { account_no: to },
      amount: NumberDecimal(String(500 + (i * 37) % 250000) + '.00'), currency: 'NGN',
      type: types[i % types.length], status: statuses[i % statuses.length], channel: chans[i % chans.length],
      initiated_at: t, completed_at: new Date(t.getTime() + 2000),
      audit_events: [{ event_type: 'INITIATED', occurred_at: t, actor: 'bulk_loader' }]
    });
    if (batch.length === 5000) { db.transactions.insertMany(batch, { ordered: false }); batch = []; }
  }
  if (batch.length) db.transactions.insertMany(batch);
}
print('transactions in collection : ' + db.transactions.countDocuments());
const FILTER = { 'from_account.account_no': 'SP01001500', status: 'COMPLETED' };
const IDX = { 'from_account.account_no': 1, status: 1 };
try { db.transactions.dropIndex('idx_from_status_demo'); } catch (e) { /* not there yet */ }
const show = (label, ex) => {
  const s = ex.executionStats;
  const st = ex.queryPlanner.winningPlan.stage + (ex.queryPlanner.winningPlan.inputStage ? ' / ' + ex.queryPlanner.winningPlan.inputStage.stage : '');
  print(label + ' plan: ' + st + ' | totalDocsExamined: ' + s.totalDocsExamined + ' | nReturned: ' + s.nReturned + ' | executionTimeMillis: ' + s.executionTimeMillis);
  return st;
};
// the existing index on from_account.account_no would hide the scan, so hint a collection scan for a fair BEFORE
const before = db.transactions.find(FILTER).hint({ $natural: 1 }).explain('executionStats');
const sb = show('BEFORE (no usable index)', before);
db.transactions.createIndex(IDX, { name: 'idx_from_status_demo' });
const after = db.transactions.find(FILTER).hint('idx_from_status_demo').explain('executionStats');
const sa = show('AFTER  (compound index) ', after);
print('Stage    BEFORE: ' + sb + ' | AFTER: ' + sa);
print('Docs     BEFORE: ' + before.executionStats.totalDocsExamined + ' | AFTER: ' + after.executionStats.totalDocsExamined);
print('Time ms  BEFORE: ' + before.executionStats.executionTimeMillis + ' | AFTER: ' + after.executionStats.executionTimeMillis);
