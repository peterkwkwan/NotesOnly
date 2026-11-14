#!/usr/bin/env node
// Import clients into orgs/<org>/clients. Shape matches _pushClients.
// Auth is `firebase login` (Cloud IAM). Security rules do not apply.
// Does not write users/{uid}. Client docs have no practitionerUid.
//
//   node tool/import_clients.js <clients.csv>
//   node tool/import_clients.js --dry-run [--wipe] <clients.csv>
//   node tool/import_clients.js --wipe <clients.csv>
//   node tool/import_clients.js --check
//
// --wipe deletes every doc under orgs/<org>/clients, then creates from CSV.
// It does not touch appointments or notes; their clientId values become orphans.
// shortcut: one project and one org, upgrade if a second clinic needs this

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT = 'notesonly-e4829';
const ORG = '3zQ3VVBA2ZssRYltwpwR';
// Public Firebase CLI OAuth client. Not a user credential.
const CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';
const KEEP = ['First Name', 'Last Name', 'Phone', 'Email'];

function parseCsv(text) {
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell += c;
      }
    } else if (c === '"') {
      quoted = true;
    } else if (c === ',') {
      row.push(cell);
      cell = '';
    } else if (c === '\n') {
      row.push(cell);
      rows.push(row);
      row = [];
      cell = '';
    } else if (c !== '\r') {
      cell += c;
    }
  }
  if (cell.length > 0 || row.length > 0) {
    row.push(cell);
    rows.push(row);
  }
  return rows;
}

function normEmail(value) {
  const trimmed = (value || '').trim().toLowerCase();
  return trimmed || null;
}

function blankToNull(value) {
  const trimmed = (value || '').trim();
  return trimmed || null;
}

function parseClients(text) {
  const table = parseCsv(text);
  if (table.length === 0) throw new Error('CSV is empty');
  const header = table[0];
  const index = {};
  header.forEach((name, i) => {
    index[name.trim()] = i;
  });
  for (const name of KEEP) {
    if (index[name] === undefined) throw new Error(`CSV missing column ${name}`);
  }
  const clients = [];
  for (let r = 1; r < table.length; r++) {
    const line = table[r];
    if (line.every((cell) => cell.trim() === '')) continue;
    const cell = (name) => (line[index[name]] || '').trim();
    const firstName = cell('First Name');
    const lastName = cell('Last Name');
    const email = cell('Email');
    if (!firstName || !lastName || !email) {
      throw new Error(`CSV row ${r + 1} is missing a name or email`);
    }
    clients.push({
      firstName,
      lastName,
      phone: blankToNull(cell('Phone')),
      email,
    });
  }
  return clients;
}

function planImport(clients, existingEmails) {
  const seen = new Set(existingEmails);
  const creates = [];
  let skipped = 0;
  let missingPhone = 0;
  for (const client of clients) {
    if (client.phone == null) missingPhone++;
    const key = normEmail(client.email);
    if (seen.has(key)) {
      skipped++;
      continue;
    }
    seen.add(key);
    creates.push(client);
  }
  return { creates, skipped, missingPhone };
}

function fieldsOf(client, now) {
  const str = (value) => ({ stringValue: value });
  const nil = { nullValue: null };
  const stamp = { timestampValue: now.toISOString() };
  return {
    firstName: str(client.firstName),
    lastName: str(client.lastName),
    phone: client.phone == null ? nil : str(client.phone),
    email: str(client.email),
    joinDate: nil,
    birthday: nil,
    emergencyContact: nil,
    emergencyContactPhone: nil,
    notes: nil,
    createdAt: stamp,
    updatedAt: stamp,
    deletedAt: nil,
  };
}

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

function docName(id) {
  return `projects/${PROJECT}/databases/(default)/documents/orgs/${ORG}/clients/${id}`;
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

function liveEmail(doc) {
  const fields = doc.fields || {};
  const deleted = fields.deletedAt;
  if (deleted && deleted.timestampValue) return null;
  const email = fields.email && fields.email.stringValue;
  return normEmail(email);
}

async function listClientDocs(token) {
  const docs = [];
  let pageToken = '';
  do {
    const url = new URL(
      `https://firestore.googleapis.com/v1/${databaseRoot()}/documents/orgs/${ORG}/clients`,
    );
    url.searchParams.set('pageSize', '300');
    url.searchParams.append('mask.fieldPaths', 'email');
    url.searchParams.append('mask.fieldPaths', 'deletedAt');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const page = await firestore(url, token);
    for (const doc of page.documents || []) docs.push(doc);
    pageToken = page.nextPageToken || '';
  } while (pageToken);
  return docs;
}

async function existingEmails(token) {
  const found = new Set();
  for (const doc of await listClientDocs(token)) {
    const email = liveEmail(doc);
    if (email) found.add(email);
  }
  return found;
}

async function commitDeletes(token, names) {
  let deleted = 0;
  for (let i = 0; i < names.length; i += 400) {
    const chunk = names.slice(i, i + 400);
    const writes = chunk.map((name) => ({ delete: name }));
    try {
      await firestore(
        `https://firestore.googleapis.com/v1/${databaseRoot()}/documents:commit`,
        token,
        { method: 'POST', body: JSON.stringify({ writes }) },
      );
    } catch (err) {
      err.deleted = deleted;
      throw err;
    }
    deleted += chunk.length;
  }
  return deleted;
}

async function commitCreates(token, creates) {
  const now = new Date();
  let created = 0;
  for (let i = 0; i < creates.length; i += 400) {
    const chunk = creates.slice(i, i + 400);
    const writes = chunk.map((client) => ({
      update: {
        name: docName(crypto.randomUUID()),
        fields: fieldsOf(client, now),
      },
    }));
    try {
      await firestore(
        `https://firestore.googleapis.com/v1/${databaseRoot()}/documents:commit`,
        token,
        { method: 'POST', body: JSON.stringify({ writes }) },
      );
    } catch (err) {
      err.created = created;
      throw err;
    }
    created += chunk.length;
  }
  return created;
}

function report(stats) {
  for (const key of ['deleted', 'created', 'skipped', 'missingPhone', 'existing', 'csv']) {
    if (stats[key] !== undefined) console.log(`${key}: ${stats[key]}`);
  }
}

function parseArgs(argv) {
  let dryRun = false;
  let wipe = false;
  let check = false;
  let csvPath = null;
  for (const arg of argv) {
    if (arg === '--dry-run') dryRun = true;
    else if (arg === '--wipe') wipe = true;
    else if (arg === '--check') check = true;
    else if (arg.startsWith('-')) {
      throw new Error(`unknown flag ${arg}`);
    } else if (csvPath) {
      throw new Error('usage: node tool/import_clients.js [--dry-run] [--wipe] <clients.csv>');
    } else csvPath = arg;
  }
  return { dryRun, wipe, check, csvPath };
}

function selfCheck() {
  const csv = [
    'Member ID,First Name,Last Name,Full Name,Email,Phone,First Seen',
    '1,Ann,Bee,Ann Bee,Ann@Clinic.test,',
    '2,Ann,Bee,Ann Bee,ann@clinic.test,555',
    '3,"Cy, Dee",Eff,Cy Dee,cy@clinic.test,  ',
    '',
  ].join('\r\n');
  const clients = parseClients(csv);
  assert.strictEqual(clients.length, 3);
  assert.strictEqual(clients[0].phone, null);
  assert.strictEqual(clients[1].phone, '555');
  assert.strictEqual(clients[2].firstName, 'Cy, Dee');
  assert.strictEqual(clients[2].phone, null);
  const plan = planImport(clients, new Set(['ann@clinic.test']));
  assert.strictEqual(plan.creates.length, 1);
  assert.strictEqual(plan.creates[0].email, 'cy@clinic.test');
  assert.strictEqual(plan.skipped, 2);
  assert.strictEqual(plan.missingPhone, 2);
  const fields = fieldsOf(plan.creates[0], new Date('2026-11-10T00:00:00.000Z'));
  assert.deepStrictEqual(Object.keys(fields), [
    'firstName',
    'lastName',
    'phone',
    'email',
    'joinDate',
    'birthday',
    'emergencyContact',
    'emergencyContactPhone',
    'notes',
    'createdAt',
    'updatedAt',
    'deletedAt',
  ]);
  assert.deepStrictEqual(fields.phone, { nullValue: null });
  assert.strictEqual(fields.email.stringValue, 'cy@clinic.test');
  assert.strictEqual(liveEmail({ fields: { email: { stringValue: ' A@B.c ' } } }), 'a@b.c');
  assert.strictEqual(
    liveEmail({
      fields: {
        email: { stringValue: 'a@b.c' },
        deletedAt: { timestampValue: '2026-01-01T00:00:00Z' },
      },
    }),
    null,
  );
  const wipePlan = planImport(clients, new Set());
  assert.strictEqual(wipePlan.creates.length, 2);
  assert.strictEqual(wipePlan.skipped, 1);
  const args = parseArgs(['--dry-run', '--wipe', 'x.csv']);
  assert.strictEqual(args.dryRun, true);
  assert.strictEqual(args.wipe, true);
  assert.strictEqual(args.csvPath, 'x.csv');
  console.log('check ok');
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error(err.message);
    process.exit(2);
  }
  if (opts.check) {
    selfCheck();
    return;
  }
  if (!opts.csvPath) {
    console.error('usage: node tool/import_clients.js [--dry-run] [--wipe] <clients.csv>');
    process.exit(2);
  }
  const clients = parseClients(fs.readFileSync(opts.csvPath, 'utf8'));
  const login = loadTokens();
  if (!login) {
    if (opts.dryRun) {
      const plan = planImport(clients, new Set());
      report({
        csv: clients.length,
        created: plan.creates.length,
        skipped: 0,
        missingPhone: plan.missingPhone,
        deleted: opts.wipe ? '(unknown — no firebase login)' : undefined,
        existing: '(unknown — no firebase login)',
      });
      console.log('dry-run: no writes');
      return;
    }
    console.error('No firebase login. Run `firebase login`, then rerun this command.');
    process.exit(1);
  }
  const token = await accessToken(login);
  let created = 0;
  let deleted = 0;
  try {
    if (opts.wipe) {
      const docs = await listClientDocs(token);
      const names = docs.map((doc) => doc.name);
      const plan = planImport(clients, new Set());
      if (opts.dryRun) {
        report({
          csv: clients.length,
          existing: names.length,
          deleted: names.length,
          created: plan.creates.length,
          skipped: 0,
          missingPhone: plan.missingPhone,
        });
        console.log('dry-run: no writes');
        return;
      }
      deleted = await commitDeletes(token, names);
      created = await commitCreates(token, plan.creates);
      const after = await listClientDocs(token);
      report({
        deleted,
        created,
        skipped: 0,
        missingPhone: plan.missingPhone,
        existing: after.length,
      });
      return;
    }
    const existing = await existingEmails(token);
    const plan = planImport(clients, existing);
    if (opts.dryRun) {
      report({
        csv: clients.length,
        existing: existing.size,
        created: plan.creates.length,
        skipped: plan.skipped,
        missingPhone: plan.missingPhone,
      });
      console.log('dry-run: no writes');
      return;
    }
    created = await commitCreates(token, plan.creates);
    report({ created, skipped: plan.skipped, missingPhone: plan.missingPhone });
  } catch (err) {
    if (err.deleted > 0) console.error(`deleted before error: ${err.deleted}`);
    if (err.created > 0) console.error(`created before error: ${err.created}`);
    if (err.status === 403) {
      console.error(
        'Firestore returned 403. This uses the firebase login Google account (Cloud IAM), so security rules did not block it. Run `firebase login` as an owner of notesonly-e4829 and rerun this command. Do not deploy rules.',
      );
    }
    throw err;
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = { parseClients, planImport, fieldsOf, liveEmail, parseArgs };
