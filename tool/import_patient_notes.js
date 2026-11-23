#!/usr/bin/env node
// Import latest patient notes into orgs/<org>/{clients,appointments,notes}.
// Modeled on tool/import_clients.js. Auth is `firebase login` (Cloud IAM).
//
//   node tool/import_patient_notes.js --help
//   node tool/import_patient_notes.js --check
//   node tool/import_patient_notes.js --dry-run [path]
//   node tool/import_patient_notes.js [--live] [path]
//
// Default CSV: tool/data/patient_notes.csv
// One note per client (latest Date). Creates name-only clients when missing.
// Creates a Scheduled appointment at the CSV datetime, then a linked note.
// Idempotent: deterministic appointment/note ids — re-run skips existing notes.
// shortcut: HK wall clock (+08) for naive CSV datetimes; upgrade if clinic TZ changes

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT = 'notesonly-e4829';
const ORG = '3zQ3VVBA2ZssRYltwpwR';
const CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';
const DEFAULT_CSV = path.join(__dirname, 'data', 'patient_notes.csv');
const APPT_MINUTES = 60;
const HK_OFFSET = '+08:00';
const COLS = ['Client Name', 'Date', 'Note'];

const HELP = `Import latest patient notes CSV into NotesOnly Firestore (Amber org).

Usage:
  node tool/import_patient_notes.js --help
  node tool/import_patient_notes.js --check
  node tool/import_patient_notes.js --dry-run [csv]
  node tool/import_patient_notes.js --live [csv]

Default csv: tool/data/patient_notes.csv

Behavior:
  - Groups by Client Name; keeps the latest Date only (~one note per client)
  - Matches client by exact full name (firstName + " " + lastName)
  - Creates name-only client when missing
  - Creates Scheduled appointment at CSV datetime (60 min, Asia/Hong_Kong)
  - Parses SOAP (S/O/A/P, else Subjective/Objective/Assessment/Plan, else all → Subjective)
  - Writes note linked to client + appointment; skips if note id already exists

Requires: firebase login (project owner of notesonly-e4829), or FIREBASE_TOKEN.
`;

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

function parseRows(text) {
  const table = parseCsv(text);
  if (table.length === 0) throw new Error('CSV is empty');
  const header = table[0];
  const index = {};
  header.forEach((name, i) => {
    index[name.trim()] = i;
  });
  for (const name of COLS) {
    if (index[name] === undefined) throw new Error(`CSV missing column ${name}`);
  }
  const rows = [];
  for (let r = 1; r < table.length; r++) {
    const line = table[r];
    if (line.every((cell) => (cell || '').trim() === '')) continue;
    const cell = (name) => (line[index[name]] || '').trim();
    const clientName = cell('Client Name');
    const date = cell('Date');
    const note = cell('Note');
    if (!clientName || !date) {
      throw new Error(`CSV row ${r + 1} is missing Client Name or Date`);
    }
    if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(date)) {
      throw new Error(`CSV row ${r + 1} has bad Date: ${date}`);
    }
    rows.push({ clientName, date, note });
  }
  return rows;
}

function latestPerClient(rows) {
  const map = new Map();
  for (const row of rows) {
    const prev = map.get(row.clientName);
    if (!prev || row.date > prev.date) map.set(row.clientName, row);
  }
  return [...map.values()].sort((a, b) =>
    a.clientName < b.clientName ? -1 : a.clientName > b.clientName ? 1 : 0,
  );
}

function parseSoap(raw) {
  const note = raw || '';
  const slash = parseSlashSoap(note);
  if (slash) return { ...slash, mode: 'slash' };
  const words = parseWordSoap(note);
  if (words) return { ...words, mode: 'words' };
  return {
    subjective: note,
    objective: '',
    assessment: '',
    plan: '',
    mode: 'fallback',
  };
}

function parseSlashSoap(note) {
  const order = ['S', 'O', 'A', 'P'];
  const cuts = [];
  let last = -1;
  for (const letter of order) {
    const re = new RegExp(`${letter}/`, 'gi');
    let match;
    let found = null;
    while ((match = re.exec(note)) !== null) {
      if (match.index > last) {
        found = match.index;
        break;
      }
    }
    if (found == null) continue;
    cuts.push({ key: letter, start: found, headerLen: 2 });
    last = found;
  }
  if (!cuts.length || cuts[0].key !== 'S' || cuts.length < 2) return null;
  return cutsToSoap(note, cuts);
}

function parseWordSoap(note) {
  const re = /(?:^|[^A-Za-z])(Subjective|Objective|Assessment|Plan)/gi;
  const map = {
    subjective: 'S',
    objective: 'O',
    assessment: 'A',
    plan: 'P',
  };
  const cuts = [];
  let lastKeyRank = -1;
  let match;
  while ((match = re.exec(note)) !== null) {
    const word = match[1];
    const key = map[word.toLowerCase()];
    const rank = 'SOAP'.indexOf(key);
    const start = match.index + match[0].length - word.length;
    if (rank <= lastKeyRank) continue;
    cuts.push({ key, start, headerLen: word.length });
    lastKeyRank = rank;
  }
  if (!cuts.length || cuts[0].key !== 'S') return null;
  return cutsToSoap(note, cuts);
}

function cutsToSoap(note, cuts) {
  const out = { subjective: '', objective: '', assessment: '', plan: '' };
  const field = { S: 'subjective', O: 'objective', A: 'assessment', P: 'plan' };
  for (let i = 0; i < cuts.length; i++) {
    const { key, start, headerLen } = cuts[i];
    const end = i + 1 < cuts.length ? cuts[i + 1].start : note.length;
    out[field[key]] = note.slice(start + headerLen, end).trim();
  }
  return out;
}

function splitName(full) {
  const parts = full.trim().split(/\s+/);
  return { firstName: parts[0], lastName: parts.slice(1).join(' ') };
}

function fullName(firstName, lastName) {
  return `${firstName} ${lastName}`.trim();
}

function parseHkDate(dateStr) {
  // dateStr: YYYY-MM-DD HH:MM as Asia/Hong_Kong wall clock (no DST).
  const iso = `${dateStr.replace(' ', 'T')}${HK_OFFSET}`;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) throw new Error(`bad date ${dateStr}`);
  return d;
}

function importKey(row) {
  return `${row.clientName}|${row.date}`;
}

function deterministicId(kind, key) {
  const digest = crypto
    .createHash('sha1')
    .update(`patient-notes|${kind}|${key}`)
    .digest();
  const b = Buffer.from(digest.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = b.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
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

function clientDocName(id) {
  return `projects/${PROJECT}/databases/(default)/documents/orgs/${ORG}/clients/${id}`;
}

function appointmentDocName(id) {
  return `projects/${PROJECT}/databases/(default)/documents/orgs/${ORG}/appointments/${id}`;
}

function noteDocName(id) {
  return `projects/${PROJECT}/databases/(default)/documents/orgs/${ORG}/notes/${id}`;
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

function str(value) {
  return { stringValue: value };
}

function nil() {
  return { nullValue: null };
}

function stamp(date) {
  return { timestampValue: date.toISOString() };
}

function intValue(n) {
  return { integerValue: String(n) };
}

function clientFields(firstName, lastName, now) {
  return {
    firstName: str(firstName),
    lastName: str(lastName),
    phone: nil(),
    email: nil(),
    joinDate: nil(),
    birthday: nil(),
    emergencyContact: nil(),
    emergencyContactPhone: nil(),
    notes: nil(),
    diagnosisCurrent: nil(),
    diagnosisPast: nil(),
    createdAt: stamp(now),
    updatedAt: stamp(now),
    deletedAt: nil(),
  };
}

function appointmentFields(clientId, practitionerUid, startsAt, endsAt, now) {
  return {
    clientId: str(clientId),
    practitionerUid: str(practitionerUid),
    startsAt: stamp(startsAt),
    endsAt: stamp(endsAt),
    status: intValue(0), // AppointmentStatus.scheduled
    notes: nil(),
    googleEventId: nil(),
    createdAt: stamp(now),
    updatedAt: stamp(now),
    deletedAt: nil(),
  };
}

function noteFieldsFor(row, clientId, appointmentId, practitionerUid, soap, now) {
  const noteDate = parseHkDate(row.date);
  return {
    clientId: str(clientId),
    appointmentId: str(appointmentId),
    practitionerUid: str(practitionerUid),
    noteDate: stamp(noteDate),
    subjective: str(soap.subjective),
    objective: str(soap.objective),
    assessment: str(soap.assessment),
    plan: str(soap.plan),
    addendum: str(''),
    status: intValue(1),
    finalizedAt: stamp(noteDate),
    createdAt: stamp(now),
    updatedAt: stamp(now),
    deletedAt: nil(),
    importKey: str(importKey(row)),
  };
}

async function listClientDocs(token) {
  const docs = [];
  let pageToken = '';
  do {
    const url = new URL(
      `https://firestore.googleapis.com/v1/${databaseRoot()}/documents/orgs/${ORG}/clients`,
    );
    url.searchParams.set('pageSize', '300');
    url.searchParams.append('mask.fieldPaths', 'firstName');
    url.searchParams.append('mask.fieldPaths', 'lastName');
    url.searchParams.append('mask.fieldPaths', 'deletedAt');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const page = await firestore(url, token);
    for (const doc of page.documents || []) docs.push(doc);
    pageToken = page.nextPageToken || '';
  } while (pageToken);
  return docs;
}

function liveClientName(doc) {
  const fields = doc.fields || {};
  if (fields.deletedAt && fields.deletedAt.timestampValue) return null;
  const first = (fields.firstName && fields.firstName.stringValue) || '';
  const last = (fields.lastName && fields.lastName.stringValue) || '';
  const name = fullName(first, last);
  return name || null;
}

function clientIdOf(doc) {
  const parts = (doc.name || '').split('/');
  return parts[parts.length - 1];
}

async function existingClientsByName(token) {
  const map = new Map();
  for (const doc of await listClientDocs(token)) {
    const name = liveClientName(doc);
    if (!name) continue;
    if (!map.has(name)) map.set(name, clientIdOf(doc));
  }
  return map;
}

async function getOrgOwnerUid(token) {
  const url = `https://firestore.googleapis.com/v1/${databaseRoot()}/documents/orgs/${ORG}`;
  const doc = await firestore(url, token);
  const arr = doc.fields && doc.fields.ownerUids && doc.fields.ownerUids.arrayValue;
  const values = (arr && arr.values) || [];
  const uid = values[0] && values[0].stringValue;
  if (!uid) throw new Error(`org ${ORG} has no ownerUids[0]`);
  return uid;
}

async function noteExists(token, noteId) {
  const url = `https://firestore.googleapis.com/v1/${noteDocName(noteId)}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return false;
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const message = json.error && json.error.message;
    throw new Error(`Firestore HTTP ${res.status}${message ? `: ${message}` : ''}`);
  }
  return true;
}

async function commitWrites(token, writes) {
  let written = 0;
  for (let i = 0; i < writes.length; i += 400) {
    const chunk = writes.slice(i, i + 400);
    try {
      await firestore(
        `https://firestore.googleapis.com/v1/${databaseRoot()}/documents:commit`,
        token,
        { method: 'POST', body: JSON.stringify({ writes: chunk }) },
      );
    } catch (err) {
      err.written = written;
      throw err;
    }
    written += chunk.length;
  }
  return written;
}

function report(stats) {
  for (const key of [
    'csv',
    'clients',
    'latest',
    'soapSlash',
    'soapWords',
    'soapFallback',
    'clientsMatched',
    'clientsCreated',
    'notesCreated',
    'notesSkipped',
    'appointmentsCreated',
  ]) {
    if (stats[key] !== undefined) console.log(`${key}: ${stats[key]}`);
  }
}

function parseArgs(argv) {
  let dryRun = false;
  let live = false;
  let check = false;
  let help = false;
  let csvPath = null;
  for (const arg of argv) {
    if (arg === '--help' || arg === '-h') help = true;
    else if (arg === '--dry-run') dryRun = true;
    else if (arg === '--live') live = true;
    else if (arg === '--check') check = true;
    else if (arg.startsWith('-')) throw new Error(`unknown flag ${arg}`);
    else if (csvPath) throw new Error('too many arguments');
    else csvPath = arg;
  }
  return { dryRun, live, check, help, csvPath: csvPath || DEFAULT_CSV };
}

function selfCheck() {
  const csv = [
    'Client Name,Date,Note',
    'Ann Bee,2024-01-02 10:00,"S/ hi O/ there A/ yes P/ go"',
    'Ann Bee,2024-02-03 11:00,"older should drop"',
    'Cy Dee,2024-03-04 12:00,"Subjectiveone Objective two Assessment three Plan four"',
    'Ed Eff,2024-04-05 09:30,"plain text only"',
  ].join('\n');
  const rows = parseRows(csv);
  assert.strictEqual(rows.length, 4);
  const latest = latestPerClient(rows);
  assert.strictEqual(latest.length, 3);
  const ann = latest.find((r) => r.clientName === 'Ann Bee');
  assert.strictEqual(ann.date, '2024-02-03 11:00');

  const slash = parseSoap('S/ hi O/ there A/ yes P/ go');
  assert.strictEqual(slash.mode, 'slash');
  assert.strictEqual(slash.subjective, 'hi');
  assert.strictEqual(slash.objective, 'there');
  assert.strictEqual(slash.assessment, 'yes');
  assert.strictEqual(slash.plan, 'go');

  const glued = parseSoap('preS/ aaaO/ bbbA/ cccP/ ddd');
  assert.strictEqual(glued.mode, 'slash');
  assert.strictEqual(glued.subjective, 'aaa');
  assert.strictEqual(glued.plan, 'ddd');

  const words = parseSoap('Subjectiveone Objective two Assessment three Plan four');
  assert.strictEqual(words.mode, 'words');
  assert.strictEqual(words.subjective, 'one');
  assert.strictEqual(words.objective, 'two');
  assert.strictEqual(words.assessment, 'three');
  assert.strictEqual(words.plan, 'four');

  const fallback = parseSoap('no markers here');
  assert.strictEqual(fallback.mode, 'fallback');
  assert.strictEqual(fallback.subjective, 'no markers here');
  assert.strictEqual(fallback.objective, '');

  const name = splitName('Shella (Lala) Renton');
  assert.strictEqual(fullName(name.firstName, name.lastName), 'Shella (Lala) Renton');

  const d = parseHkDate('2024-08-01 11:15');
  assert.strictEqual(d.toISOString(), '2024-08-01T03:15:00.000Z');

  const id1 = deterministicId('note', 'Ann Bee|2024-02-03 11:00');
  const id2 = deterministicId('note', 'Ann Bee|2024-02-03 11:00');
  assert.strictEqual(id1, id2);
  assert.match(id1, /^[0-9a-f-]{36}$/);

  const args = parseArgs(['--dry-run', 'x.csv']);
  assert.strictEqual(args.dryRun, true);
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
  if (opts.help) {
    process.stdout.write(HELP);
    return;
  }
  if (opts.check) {
    selfCheck();
    return;
  }
  if (opts.dryRun && opts.live) {
    console.error('use either --dry-run or --live, not both');
    process.exit(2);
  }
  if (!opts.dryRun && !opts.live) {
    console.error('pass --dry-run or --live (see --help)');
    process.exit(2);
  }
  if (!fs.existsSync(opts.csvPath)) {
    console.error(`CSV not found: ${opts.csvPath}`);
    process.exit(2);
  }

  const rows = parseRows(fs.readFileSync(opts.csvPath, 'utf8'));
  const latest = latestPerClient(rows);
  let soapSlash = 0;
  let soapWords = 0;
  let soapFallback = 0;
  const parsed = latest.map((row) => {
    const soap = parseSoap(row.note);
    if (soap.mode === 'slash') soapSlash++;
    else if (soap.mode === 'words') soapWords++;
    else soapFallback++;
    return { row, soap };
  });

  const login = loadTokens();
  if (!login) {
    if (opts.dryRun) {
      report({
        csv: rows.length,
        clients: new Set(rows.map((r) => r.clientName)).size,
        latest: latest.length,
        soapSlash,
        soapWords,
        soapFallback,
      });
      for (const { row, soap } of parsed.slice(0, 3)) {
        console.log(
          `sample: ${row.clientName} @ ${row.date} mode=${soap.mode} S=${soap.subjective.slice(0, 40).replace(/\s+/g, ' ')}`,
        );
      }
      console.log('dry-run: no writes (no firebase login — skipped match counts)');
      return;
    }
    console.error('No firebase login. Run `firebase login`, then rerun this command.');
    process.exit(1);
  }

  const token = await accessToken(login);
  let clientsMatched = 0;
  let clientsCreated = 0;
  let notesCreated = 0;
  let notesSkipped = 0;
  let appointmentsCreated = 0;

  try {
    const practitionerUid = await getOrgOwnerUid(token);
    const byName = await existingClientsByName(token);
    const now = new Date();
    const writes = [];

    for (const { row, soap } of parsed) {
      const key = importKey(row);
      const noteId = deterministicId('note', key);
      const apptId = deterministicId('appt', key);

      let clientId = byName.get(row.clientName);
      if (clientId) {
        clientsMatched++;
      } else {
        const { firstName, lastName } = splitName(row.clientName);
        clientId = deterministicId('client', row.clientName);
        if (!opts.dryRun) {
          writes.push({
            update: {
              name: clientDocName(clientId),
              fields: clientFields(firstName, lastName, now),
            },
          });
        }
        byName.set(row.clientName, clientId);
        clientsCreated++;
      }

      const exists = await noteExists(token, noteId);
      if (exists) {
        notesSkipped++;
        continue;
      }

      const startsAt = parseHkDate(row.date);
      const endsAt = new Date(startsAt.getTime() + APPT_MINUTES * 60 * 1000);
      if (!opts.dryRun) {
        writes.push({
          update: {
            name: appointmentDocName(apptId),
            fields: appointmentFields(clientId, practitionerUid, startsAt, endsAt, now),
          },
        });
        writes.push({
          update: {
            name: noteDocName(noteId),
            fields: noteFieldsFor(row, clientId, apptId, practitionerUid, soap, now),
          },
        });
      }
      appointmentsCreated++;
      notesCreated++;
    }

    report({
      csv: rows.length,
      clients: new Set(rows.map((r) => r.clientName)).size,
      latest: latest.length,
      soapSlash,
      soapWords,
      soapFallback,
      clientsMatched,
      clientsCreated,
      appointmentsCreated,
      notesCreated,
      notesSkipped,
    });

    if (opts.dryRun) {
      for (const { row, soap } of parsed.slice(0, 3)) {
        console.log(
          `sample: ${row.clientName} @ ${row.date} mode=${soap.mode} S=${soap.subjective.slice(0, 40).replace(/\s+/g, ' ')}`,
        );
      }
      console.log('dry-run: no writes');
      return;
    }

    await commitWrites(token, writes);
    console.log('live: writes committed');
  } catch (err) {
    if (err.written > 0) console.error(`writes before error: ${err.written}`);
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

module.exports = {
  parseRows,
  latestPerClient,
  parseSoap,
  splitName,
  fullName,
  parseHkDate,
  deterministicId,
  parseArgs,
};
