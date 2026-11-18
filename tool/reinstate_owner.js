#!/usr/bin/env node
// Reinstate Owner on a membership (and keep admin/practitioner already present).
// Soft-remove strips owner + sets active:false; this reverses that for one email.
// Auth is `firebase login` / FIREBASE_TOKEN (Cloud IAM). Security rules do not apply.
//
//   node tool/reinstate_owner.js --check
//   node tool/reinstate_owner.js --dry-run
//   node tool/reinstate_owner.js --live
//
// Defaults: project notesonly-e4829, org Amber Health (3zQ3VVBA2ZssRYltwpwR),
// email peterkwkwan@gmail.com. Override with --org / --email.
// shortcut: one known clinic + platform-admin email, upgrade if multi-clinic restore needed

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT = 'notesonly-e4829';
const DEFAULT_ORG = '3zQ3VVBA2ZssRYltwpwR';
const DEFAULT_EMAIL = 'peterkwkwan@gmail.com';
const ROLE_ORDER = ['owner', 'admin', 'practitioner'];
// Public Firebase CLI OAuth client. Not a user credential.
const CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

const HELP =
  'Reinstate Owner on a NotesOnly membership (Amber org by default).\n' +
  '\n' +
  'Usage:\n' +
  '  node tool/reinstate_owner.js --check\n' +
  '  node tool/reinstate_owner.js --dry-run [--org <id>] [--email <addr>]\n' +
  '  node tool/reinstate_owner.js --live [--org <id>] [--email <addr>]\n' +
  '\n' +
  'Finds memberships/{orgId}_{uid} for the email in the org, sets active:true,\n' +
  'ensures roles include owner (keeps admin/practitioner; adds practitioner if\n' +
  'roles would otherwise be owner-only), and adds uid to orgs/{orgId}.ownerUids.\n' +
  '\n' +
  'Requires: firebase login (project owner of notesonly-e4829), or FIREBASE_TOKEN.\n';

function tokenPaths() {
  const home = os.homedir();
  const xdg = process.env.XDG_CONFIG_HOME || path.join(home, '.config');
  const paths = [path.join(xdg, 'configstore', 'firebase-tools.json')];
  if (process.env.APPDATA) {
    paths.push(path.join(process.env.APPDATA, 'configstore', 'firebase-tools.json'));
  }
  return paths;
}

function projectDir(start) {
  let dir = path.resolve(start);
  for (;;) {
    if (fs.existsSync(path.join(dir, 'firebase.json'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return path.resolve(start);
    dir = parent;
  }
}

function loadTokens() {
  if (process.env.FIREBASE_TOKEN) {
    return { refreshToken: process.env.FIREBASE_TOKEN, ci: true };
  }
  const file = tokenPaths().find((p) => fs.existsSync(p));
  if (!file) return null;
  const config = JSON.parse(fs.readFileSync(file, 'utf8'));
  const accounts = [];
  if (config.user && config.tokens) {
    accounts.push({ user: config.user, tokens: config.tokens });
  }
  for (const account of config.additionalAccounts || []) accounts.push(account);
  const pinned = (config.activeAccounts || {})[projectDir(process.cwd())];
  const chosen = accounts.find((account) => account.user && account.user.email === pinned);
  const tokens = (chosen || accounts[0] || {}).tokens;
  if (!tokens || !tokens.refresh_token) return null;
  const fresh =
    tokens.access_token &&
    tokens.expires_at &&
    tokens.expires_at > Date.now() + 60 * 1000;
  return {
    refreshToken: tokens.refresh_token,
    accessToken: fresh ? tokens.access_token : null,
  };
}

async function accessToken(login) {
  if (login.accessToken) return login.accessToken;
  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    refresh_token: login.refreshToken,
    grant_type: 'refresh_token',
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    body,
  });
  const json = await res.json().catch(() => ({}));
  if (res.ok && json.access_token) return json.access_token;
  if (login.ci && (res.status === 400 || res.status === 401)) return login.refreshToken;
  throw new Error('Firebase login expired. Run `firebase login`, then rerun this command.');
}

function databaseRoot() {
  return `projects/${PROJECT}/databases/${encodeURIComponent('(default)')}`;
}

async function firestore(url, token, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const code = json.error && json.error.status;
    const message = json.error && json.error.message;
    const err = new Error(
      `Firestore HTTP ${res.status}${code ? ` ${code}` : ''}${message ? `: ${message}` : ''}`,
    );
    err.status = res.status;
    throw err;
  }
  return json;
}

function stringField(fields, name) {
  const value = fields && fields[name];
  return value && value.stringValue != null ? String(value.stringValue) : '';
}

function boolField(fields, name) {
  const value = fields && fields[name];
  return !!(value && value.booleanValue === true);
}

function stringArrayField(fields, name) {
  const value = fields && fields[name];
  const values = value && value.arrayValue && value.arrayValue.values;
  if (!Array.isArray(values)) return [];
  const out = [];
  for (const item of values) {
    if (item && item.stringValue != null) out.push(String(item.stringValue));
  }
  return out;
}

function normalizeRoles(roles) {
  const set = new Set(roles.filter((role) => ROLE_ORDER.includes(role)));
  return ROLE_ORDER.filter((role) => set.has(role));
}

function planRoles(currentRoles) {
  const next = new Set(normalizeRoles(currentRoles));
  next.add('owner');
  const others = [...next].filter((role) => role !== 'owner');
  // create-org / migrate default is owner+practitioner when nothing else remains
  if (others.length === 0) next.add('practitioner');
  return normalizeRoles([...next]);
}

function planOwnerUids(ownerUids, uid) {
  if (ownerUids.includes(uid)) return [...ownerUids];
  return [...ownerUids, uid];
}

function planReinstate({ email, orgId, uid, active, roles, ownerUids }) {
  const nextRoles = planRoles(roles);
  const nextOwners = planOwnerUids(ownerUids, uid);
  const rolesSame =
    nextRoles.length === roles.length && nextRoles.every((role, i) => role === roles[i]);
  const ownersSame =
    nextOwners.length === ownerUids.length &&
    nextOwners.every((id, i) => id === ownerUids[i]);
  const alreadyOk = active === true && rolesSame && ownersSame;
  return {
    email,
    orgId,
    uid,
    membershipId: `${orgId}_${uid}`,
    before: { active, roles, ownerUids },
    after: { active: true, roles: nextRoles, ownerUids: nextOwners },
    alreadyOk,
    needsWrite: !alreadyOk,
  };
}

function parseArgs(argv) {
  let dryRun = false;
  let live = false;
  let check = false;
  let help = false;
  let orgId = DEFAULT_ORG;
  let email = DEFAULT_EMAIL;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') help = true;
    else if (arg === '--check') check = true;
    else if (arg === '--dry-run') dryRun = true;
    else if (arg === '--live') live = true;
    else if (arg === '--org') {
      orgId = argv[++i];
      if (!orgId) throw new Error('missing --org value');
    } else if (arg === '--email') {
      email = argv[++i];
      if (!email) throw new Error('missing --email value');
    } else if (arg.startsWith('-')) {
      throw new Error(`unknown flag ${arg}`);
    } else {
      throw new Error('unexpected argument; see --help');
    }
  }
  email = email.trim().toLowerCase();
  if (!email) throw new Error('email is empty');
  if (!orgId) throw new Error('org is empty');
  if (!check && !help && !dryRun && !live) {
    throw new Error('pass --dry-run, --live, --check, or --help');
  }
  if (dryRun && live) throw new Error('use either --dry-run or --live');
  return { dryRun, live, check, help, orgId, email };
}

async function runQuery(token, structuredQuery) {
  const rows = await firestore(
    `https://firestore.googleapis.com/v1/${databaseRoot()}/documents:runQuery`,
    token,
    { method: 'POST', body: JSON.stringify({ structuredQuery }) },
  );
  return (rows || []).map((row) => row.document).filter(Boolean);
}

async function findMemberships(token, { orgId, email }) {
  return runQuery(token, {
    from: [{ collectionId: 'memberships' }],
    where: {
      compositeFilter: {
        op: 'AND',
        filters: [
          {
            fieldFilter: {
              field: { fieldPath: 'orgId' },
              op: 'EQUAL',
              value: { stringValue: orgId },
            },
          },
          {
            fieldFilter: {
              field: { fieldPath: 'email' },
              op: 'EQUAL',
              value: { stringValue: email },
            },
          },
        ],
      },
    },
  });
}

async function getOrg(token, orgId) {
  return firestore(
    `https://firestore.googleapis.com/v1/${databaseRoot()}/documents/orgs/${orgId}`,
    token,
  );
}

function arrayValue(strings) {
  return {
    arrayValue: {
      values: strings.map((value) => ({ stringValue: value })),
    },
  };
}

async function commitReinstate(token, plan) {
  const now = new Date().toISOString();
  const memberName = `${databaseRoot()}/documents/memberships/${plan.membershipId}`;
  const orgName = `${databaseRoot()}/documents/orgs/${plan.orgId}`;
  await firestore(
    `https://firestore.googleapis.com/v1/${databaseRoot()}/documents:commit`,
    token,
    {
      method: 'POST',
      body: JSON.stringify({
        writes: [
          {
            update: {
              name: memberName,
              fields: {
                active: { booleanValue: true },
                roles: arrayValue(plan.after.roles),
                updatedAt: { timestampValue: now },
              },
            },
            updateMask: {
              fieldPaths: ['active', 'roles', 'updatedAt'],
            },
          },
          {
            update: {
              name: orgName,
              fields: {
                ownerUids: arrayValue(plan.after.ownerUids),
                updatedAt: { timestampValue: now },
              },
            },
            updateMask: {
              fieldPaths: ['ownerUids', 'updatedAt'],
            },
          },
        ],
      }),
    },
  );
}

function printPlan(plan) {
  console.log(`org: ${plan.orgId}`);
  console.log(`email: ${plan.email}`);
  console.log(`uid: ${plan.uid}`);
  console.log(`membership: ${plan.membershipId}`);
  console.log(`before.active: ${plan.before.active}`);
  console.log(`before.roles: ${plan.before.roles.join(',') || '(none)'}`);
  console.log(`before.ownerUids: ${plan.before.ownerUids.join(',') || '(none)'}`);
  console.log(`after.active: ${plan.after.active}`);
  console.log(`after.roles: ${plan.after.roles.join(',')}`);
  console.log(`after.ownerUids: ${plan.after.ownerUids.join(',')}`);
  console.log(`needsWrite: ${plan.needsWrite}`);
}

function selfCheck() {
  assert.deepStrictEqual(planRoles(['practitioner']), ['owner', 'practitioner']);
  assert.deepStrictEqual(planRoles(['admin', 'practitioner']), [
    'owner',
    'admin',
    'practitioner',
  ]);
  assert.deepStrictEqual(planRoles([]), ['owner', 'practitioner']);
  assert.deepStrictEqual(planRoles(['owner', 'practitioner']), [
    'owner',
    'practitioner',
  ]);
  assert.deepStrictEqual(planOwnerUids(['a'], 'b'), ['a', 'b']);
  assert.deepStrictEqual(planOwnerUids(['a', 'b'], 'b'), ['a', 'b']);
  const plan = planReinstate({
    email: DEFAULT_EMAIL,
    orgId: DEFAULT_ORG,
    uid: 'u1',
    active: false,
    roles: ['practitioner'],
    ownerUids: ['u2'],
  });
  assert.strictEqual(plan.needsWrite, true);
  assert.deepStrictEqual(plan.after.roles, ['owner', 'practitioner']);
  assert.deepStrictEqual(plan.after.ownerUids, ['u2', 'u1']);
  const ok = planReinstate({
    email: DEFAULT_EMAIL,
    orgId: DEFAULT_ORG,
    uid: 'u1',
    active: true,
    roles: ['owner', 'practitioner'],
    ownerUids: ['u1'],
  });
  assert.strictEqual(ok.alreadyOk, true);
  assert.strictEqual(ok.needsWrite, false);
  const args = parseArgs(['--dry-run', '--email', 'A@B.c', '--org', 'x']);
  assert.strictEqual(args.email, 'a@b.c');
  assert.strictEqual(args.orgId, 'x');
  assert.strictEqual(args.dryRun, true);
  // Regression: printPlan must read plan.orgId (bare orgId → ReferenceError).
  const lines = [];
  const origLog = console.log;
  console.log = (msg) => lines.push(String(msg));
  try {
    printPlan(plan);
  } finally {
    console.log = origLog;
  }
  assert.strictEqual(lines[0], `org: ${DEFAULT_ORG}`);
  assert.ok(lines.some((line) => line === 'needsWrite: true'));
  console.log('check ok');
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error(err.message);
    console.error(HELP);
    process.exit(2);
  }
  if (opts.help) {
    process.stdout.write(HELP);
    return;
  }
  if (opts.check) {
    selfCheck();
    return;
  }

  const login = loadTokens();
  if (!login) {
    console.error('No firebase login. Run `firebase login`, then rerun this command.');
    process.exit(1);
  }
  const token = await accessToken(login);

  let members;
  let org;
  try {
    members = await findMemberships(token, {
      orgId: opts.orgId,
      email: opts.email,
    });
    org = await getOrg(token, opts.orgId);
  } catch (err) {
    if (err.status === 403) {
      console.error(
        'Firestore returned 403. This uses the firebase login Google account (Cloud IAM), so security rules did not block it. Run `firebase login` as an owner of notesonly-e4829 and rerun this command. Do not deploy rules.',
      );
    }
    throw err;
  }

  if (!org.name) throw new Error(`org ${opts.orgId} not found`);
  const orgName = stringField(org.fields, 'name') || opts.orgId;
  const ownerUids = stringArrayField(org.fields, 'ownerUids');
  console.log(`org.name: ${orgName}`);

  if (members.length === 0) {
    console.error(
      `No membership for ${opts.email} in org ${opts.orgId}. Nothing to reinstate.`,
    );
    process.exit(1);
  }
  if (members.length > 1) {
    console.error(
      `Found ${members.length} memberships for ${opts.email} in org ${opts.orgId}; expected 1.`,
    );
    for (const doc of members) console.error(`- ${doc.name}`);
    process.exit(1);
  }

  const doc = members[0];
  const fields = doc.fields || {};
  const uid = stringField(fields, 'uid');
  if (!uid) throw new Error('membership missing uid');
  const plan = planReinstate({
    email: opts.email,
    orgId: opts.orgId,
    uid,
    active: boolField(fields, 'active'),
    roles: normalizeRoles(stringArrayField(fields, 'roles')),
    ownerUids,
  });
  printPlan(plan);

  if (!plan.needsWrite) {
    console.log('already owner+active; no write');
    return;
  }
  if (opts.dryRun) {
    console.log('dry-run: no writes');
    return;
  }

  await commitReinstate(token, plan);
  console.log('wrote: membership active+roles and org.ownerUids');
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = {
  planRoles,
  planOwnerUids,
  planReinstate,
  parseArgs,
  normalizeRoles,
};
