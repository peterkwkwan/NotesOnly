#!/usr/bin/env node
// Reassign practitionerUid on mass-import appointments + matching notes.
// Cohort: patient-notes import (importKey / linked appt), else Peter + startsAt
// before 2026-11-14 Asia/Hong_Kong. Auth: firebase login / FIREBASE_TOKEN.
//
//   node tool/reassign_import_practitioner.js --check
//   node tool/reassign_import_practitioner.js --dry-run
//   node tool/reassign_import_practitioner.js --live
//
// Defaults: notesonly-e4829, Amber (3zQ3VVBA2ZssRYltwpwR),
// from peterkwkwan@gmail.com → to shummh19@gmail.com.
// shortcut: one clinic + one import cutover, upgrade if multi-clinic reassign

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT = 'notesonly-e4829';
const DEFAULT_ORG = '3zQ3VVBA2ZssRYltwpwR';
const DEFAULT_FROM_EMAIL = 'peterkwkwan@gmail.com';
const DEFAULT_TO_EMAIL = 'shummh19@gmail.com';
// 2026-11-14 00:00 Asia/Hong_Kong
const DEFAULT_BEFORE = '2026-11-13T16:00:00.000Z';
const ROLE_ORDER = ['owner', 'admin', 'practitioner'];
const CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

const HELP =
  'Reassign practitionerUid on Amber mass-import appointments + notes.\n' +
  '\n' +
  'Usage:\n' +
  '  node tool/reassign_import_practitioner.js --check\n' +
  '  node tool/reassign_import_practitioner.js --dry-run [--org <id>]\n' +
  '      [--from-email <addr>] [--to-email <addr>] [--before <iso>]\n' +
  '  node tool/reassign_import_practitioner.js --live [...same flags]\n' +
  '\n' +
  'Looks up to-email in memberships (+ pending invites). Resolves from-email\n' +
  'uid (fallback org.ownerUids[0]). Prefers patient-notes import cohort\n' +
  '(notes with importKey → their appointments) still owned by from-uid and\n' +
  'startsAt < --before (default 2026-11-14 00:00 Asia/Hong_Kong). If no\n' +
  'importKey notes, falls back to all appointments with practitioner=from\n' +
  'and startsAt < before, plus notes on those appointments.\n' +
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

function docId(name) {
  const parts = (name || '').split('/');
  return parts[parts.length - 1] || '';
}

function stringField(fields, name) {
  const value = fields && fields[name];
  return value && value.stringValue != null ? String(value.stringValue) : '';
}

function boolField(fields, name) {
  const value = fields && fields[name];
  return !!(value && value.booleanValue === true);
}

function timestampField(fields, name) {
  const value = fields && fields[name];
  return value && value.timestampValue ? String(value.timestampValue) : '';
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

function isImportNote(fields) {
  return stringField(fields, 'importKey').length > 0;
}

function parseArgs(argv) {
  let dryRun = false;
  let live = false;
  let check = false;
  let help = false;
  let orgId = DEFAULT_ORG;
  let fromEmail = DEFAULT_FROM_EMAIL;
  let toEmail = DEFAULT_TO_EMAIL;
  let before = DEFAULT_BEFORE;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') help = true;
    else if (arg === '--check') check = true;
    else if (arg === '--dry-run') dryRun = true;
    else if (arg === '--live') live = true;
    else if (arg === '--org') {
      orgId = argv[++i];
      if (!orgId) throw new Error('missing --org value');
    } else if (arg === '--from-email') {
      fromEmail = argv[++i];
      if (!fromEmail) throw new Error('missing --from-email value');
    } else if (arg === '--to-email') {
      toEmail = argv[++i];
      if (!toEmail) throw new Error('missing --to-email value');
    } else if (arg === '--before') {
      before = argv[++i];
      if (!before) throw new Error('missing --before value');
    } else if (arg.startsWith('-')) {
      throw new Error(`unknown flag ${arg}`);
    } else {
      throw new Error('unexpected argument; see --help');
    }
  }
  fromEmail = fromEmail.trim().toLowerCase();
  toEmail = toEmail.trim().toLowerCase();
  if (!fromEmail || !toEmail) throw new Error('from/to email is empty');
  if (!orgId) throw new Error('org is empty');
  const beforeMs = Date.parse(before);
  if (!Number.isFinite(beforeMs)) throw new Error(`bad --before: ${before}`);
  if (!check && !help && !dryRun && !live) {
    throw new Error('pass --dry-run, --live, --check, or --help');
  }
  if (dryRun && live) throw new Error('use either --dry-run or --live');
  return {
    dryRun,
    live,
    check,
    help,
    orgId,
    fromEmail,
    toEmail,
    beforeIso: new Date(beforeMs).toISOString(),
    beforeMs,
  };
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

async function findInvites(token, { orgId, email }) {
  return runQuery(token, {
    from: [{ collectionId: 'invites' }],
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

async function listOrgDocs(token, orgId, collectionId) {
  const docs = [];
  let pageToken = '';
  do {
    const url = new URL(
      `https://firestore.googleapis.com/v1/${databaseRoot()}/documents/orgs/${orgId}/${collectionId}`,
    );
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const page = await firestore(url, token);
    for (const doc of page.documents || []) docs.push(doc);
    pageToken = page.nextPageToken || '';
  } while (pageToken);
  return docs;
}

function membershipSummary(doc) {
  if (!doc) return null;
  const fields = doc.fields || {};
  const uid = stringField(fields, 'uid');
  return {
    id: docId(doc.name),
    uid,
    email: stringField(fields, 'email'),
    active: boolField(fields, 'active'),
    roles: normalizeRoles(stringArrayField(fields, 'roles')),
  };
}

function inviteSummary(doc) {
  const fields = doc.fields || {};
  return {
    id: docId(doc.name),
    email: stringField(fields, 'email'),
    kind: stringField(fields, 'kind'),
    role: stringField(fields, 'role'),
    acceptedAt: timestampField(fields, 'acceptedAt') || null,
    revokedAt: timestampField(fields, 'revokedAt') || null,
    expiresAt: timestampField(fields, 'expiresAt') || null,
  };
}

function selectCohort({ appointments, notes, fromUid, toUid, beforeMs }) {
  const liveAppts = appointments.filter((doc) => {
    const fields = doc.fields || {};
    if (timestampField(fields, 'deletedAt')) return false;
    return stringField(fields, 'practitionerUid') === fromUid;
  });
  const liveNotes = notes.filter((doc) => {
    const fields = doc.fields || {};
    if (timestampField(fields, 'deletedAt')) return false;
    return stringField(fields, 'practitionerUid') === fromUid;
  });

  const importNotes = liveNotes.filter((doc) => isImportNote(doc.fields || {}));
  const importApptIds = new Set(
    importNotes.map((doc) => stringField(doc.fields, 'appointmentId')).filter(Boolean),
  );
  const mode = importNotes.length > 0 ? 'importKey' : 'before+practitioner';

  let selectedAppts;
  if (mode === 'importKey') {
    selectedAppts = liveAppts.filter((doc) => {
      const id = docId(doc.name);
      if (!importApptIds.has(id)) return false;
      const starts = Date.parse(timestampField(doc.fields, 'startsAt'));
      return Number.isFinite(starts) && starts < beforeMs;
    });
  } else {
    selectedAppts = liveAppts.filter((doc) => {
      const starts = Date.parse(timestampField(doc.fields, 'startsAt'));
      return Number.isFinite(starts) && starts < beforeMs;
    });
  }

  const selectedApptIds = new Set(selectedAppts.map((doc) => docId(doc.name)));
  const selectedNotes =
    mode === 'importKey'
      ? importNotes.filter((doc) => {
          const apptId = stringField(doc.fields, 'appointmentId');
          return selectedApptIds.has(apptId);
        })
      : liveNotes.filter((doc) => selectedApptIds.has(stringField(doc.fields, 'appointmentId')));

  const apptWrites = selectedAppts
    .filter((doc) => stringField(doc.fields, 'practitionerUid') !== toUid)
    .map((doc) => ({ id: docId(doc.name), kind: 'appointment' }));
  const noteWrites = selectedNotes
    .filter((doc) => stringField(doc.fields, 'practitionerUid') !== toUid)
    .map((doc) => ({ id: docId(doc.name), kind: 'note' }));

  return {
    mode,
    importNoteCount: importNotes.length,
    selectedAppointmentCount: selectedAppts.length,
    selectedNoteCount: selectedNotes.length,
    alreadyOkAppointments: selectedAppts.length - apptWrites.length,
    alreadyOkNotes: selectedNotes.length - noteWrites.length,
    writes: [...apptWrites, ...noteWrites],
  };
}

function appointmentDocName(orgId, id) {
  return `${databaseRoot()}/documents/orgs/${orgId}/appointments/${id}`;
}

function noteDocName(orgId, id) {
  return `${databaseRoot()}/documents/orgs/${orgId}/notes/${id}`;
}

async function commitWrites(token, orgId, toUid, writes) {
  const now = new Date().toISOString();
  let written = 0;
  for (let i = 0; i < writes.length; i += 400) {
    const chunk = writes.slice(i, i + 400).map((item) => {
      const name =
        item.kind === 'appointment'
          ? appointmentDocName(orgId, item.id)
          : noteDocName(orgId, item.id);
      return {
        update: {
          name,
          fields: {
            practitionerUid: { stringValue: toUid },
            updatedAt: { timestampValue: now },
          },
        },
        updateMask: { fieldPaths: ['practitionerUid', 'updatedAt'] },
      };
    });
    await firestore(
      `https://firestore.googleapis.com/v1/${databaseRoot()}/documents:commit`,
      token,
      { method: 'POST', body: JSON.stringify({ writes: chunk }) },
    );
    written += chunk.length;
  }
  return written;
}

function printMember(label, member) {
  if (!member) {
    console.log(`${label}: (not found)`);
    return;
  }
  console.log(`${label}.uid: ${member.uid}`);
  console.log(`${label}.email: ${member.email}`);
  console.log(`${label}.active: ${member.active}`);
  console.log(`${label}.roles: ${member.roles.join(',') || '(none)'}`);
  console.log(`${label}.membership: ${member.id}`);
}

function selfCheck() {
  const args = parseArgs([
    '--dry-run',
    '--to-email',
    'Shummh19@Gmail.com',
    '--before',
    '2026-11-13T16:00:00.000Z',
  ]);
  assert.strictEqual(args.toEmail, 'shummh19@gmail.com');
  assert.strictEqual(args.beforeIso, DEFAULT_BEFORE);
  assert.strictEqual(args.dryRun, true);

  assert.strictEqual(isImportNote({ importKey: { stringValue: 'A|2024-01-01 10:00' } }), true);
  assert.strictEqual(isImportNote({ importKey: { stringValue: '' } }), false);
  assert.strictEqual(isImportNote({}), false);

  const fromUid = 'peter';
  const toUid = 'shum';
  const beforeMs = Date.parse(DEFAULT_BEFORE);
  const appointments = [
    {
      name: 'x/a1',
      fields: {
        practitionerUid: { stringValue: fromUid },
        startsAt: { timestampValue: '2026-11-13T15:59:00.000Z' },
      },
    },
    {
      name: 'x/a2',
      fields: {
        practitionerUid: { stringValue: fromUid },
        startsAt: { timestampValue: '2026-11-13T16:00:00.000Z' },
      },
    },
    {
      name: 'x/a3',
      fields: {
        practitionerUid: { stringValue: fromUid },
        startsAt: { timestampValue: '2025-01-01T00:00:00.000Z' },
      },
    },
  ];
  const notes = [
    {
      name: 'x/n1',
      fields: {
        practitionerUid: { stringValue: fromUid },
        appointmentId: { stringValue: 'a1' },
        importKey: { stringValue: 'Ann|2026-11-13 23:59' },
      },
    },
    {
      name: 'x/n3',
      fields: {
        practitionerUid: { stringValue: fromUid },
        appointmentId: { stringValue: 'a3' },
        importKey: { stringValue: 'Bee|2025-01-01 08:00' },
      },
    },
    {
      name: 'x/n-other',
      fields: {
        practitionerUid: { stringValue: fromUid },
        appointmentId: { stringValue: 'a1' },
      },
    },
  ];
  const importPlan = selectCohort({ appointments, notes, fromUid, toUid, beforeMs });
  assert.strictEqual(importPlan.mode, 'importKey');
  assert.strictEqual(importPlan.selectedAppointmentCount, 2);
  assert.strictEqual(importPlan.selectedNoteCount, 2);
  assert.strictEqual(importPlan.writes.length, 4);

  const fallback = selectCohort({
    appointments,
    notes: notes.filter((n) => !isImportNote(n.fields)),
    fromUid,
    toUid,
    beforeMs,
  });
  assert.strictEqual(fallback.mode, 'before+practitioner');
  assert.strictEqual(fallback.selectedAppointmentCount, 2); // a1 + a3
  assert.ok(fallback.writes.some((w) => w.id === 'a1' && w.kind === 'appointment'));

  const already = selectCohort({
    appointments: [
      {
        name: 'x/a1',
        fields: {
          practitionerUid: { stringValue: toUid },
          startsAt: { timestampValue: '2025-01-01T00:00:00.000Z' },
        },
      },
    ],
    notes: [
      {
        name: 'x/n1',
        fields: {
          practitionerUid: { stringValue: toUid },
          appointmentId: { stringValue: 'a1' },
          importKey: { stringValue: 'x' },
        },
      },
    ],
    fromUid,
    toUid,
    beforeMs,
  });
  assert.strictEqual(already.writes.length, 0);

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

  let toMembers;
  let fromMembers;
  let invites;
  let org;
  try {
    toMembers = await findMemberships(token, { orgId: opts.orgId, email: opts.toEmail });
    fromMembers = await findMemberships(token, {
      orgId: opts.orgId,
      email: opts.fromEmail,
    });
    invites = await findInvites(token, { orgId: opts.orgId, email: opts.toEmail });
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
  console.log(`org.id: ${opts.orgId}`);
  console.log(`before: ${opts.beforeIso} (exclusive)`);

  const toMember = toMembers.length === 1 ? membershipSummary(toMembers[0]) : null;
  console.log(`shummh19_in_db: ${toMembers.length > 0 ? 'yes' : 'no'}`);
  if (toMembers.length > 1) {
    console.error(
      `Found ${toMembers.length} memberships for ${opts.toEmail} in org ${opts.orgId}; expected 1.`,
    );
    for (const doc of toMembers) console.error(`- ${doc.name}`);
    process.exit(1);
  }
  printMember('to', toMember);
  if (invites.length === 0) {
    console.log('to.invites: (none)');
  } else {
    for (const doc of invites) {
      const inv = inviteSummary(doc);
      console.log(
        `to.invite: ${inv.id} kind=${inv.kind} role=${inv.role || '(none)'} ` +
          `accepted=${inv.acceptedAt || '-'} revoked=${inv.revokedAt || '-'} ` +
          `expires=${inv.expiresAt || '-'}`,
      );
    }
  }

  if (!toMember) {
    console.error(
      `No membership for ${opts.toEmail} in org ${opts.orgId}. Nothing to reassign to.`,
    );
    process.exit(1);
  }
  if (!toMember.uid) throw new Error('to membership missing uid');
  if (!toMember.active) {
    console.error(`Refusing: ${opts.toEmail} membership is inactive.`);
    process.exit(1);
  }
  if (!toMember.roles.includes('practitioner')) {
    console.error(
      `Refusing: ${opts.toEmail} has no practitioner role (${toMember.roles.join(',') || 'none'}).`,
    );
    process.exit(1);
  }

  let fromUid = '';
  if (fromMembers.length === 1) {
    fromUid = membershipSummary(fromMembers[0]).uid;
  } else if (fromMembers.length > 1) {
    console.error(
      `Found ${fromMembers.length} memberships for ${opts.fromEmail}; expected 1.`,
    );
    process.exit(1);
  } else if (ownerUids[0]) {
    fromUid = ownerUids[0];
    console.log(`from.fallback: org.ownerUids[0]=${fromUid}`);
  }
  if (!fromUid) {
    console.error(`Could not resolve from uid for ${opts.fromEmail}.`);
    process.exit(1);
  }
  printMember('from', fromMembers[0] ? membershipSummary(fromMembers[0]) : null);
  console.log(`from.uid.resolved: ${fromUid}`);
  console.log(`to.uid.resolved: ${toMember.uid}`);

  if (fromUid === toMember.uid) {
    console.error('from and to uid are the same; nothing to do.');
    process.exit(1);
  }

  const [appointments, notes] = await Promise.all([
    listOrgDocs(token, opts.orgId, 'appointments'),
    listOrgDocs(token, opts.orgId, 'notes'),
  ]);
  const plan = selectCohort({
    appointments,
    notes,
    fromUid,
    toUid: toMember.uid,
    beforeMs: opts.beforeMs,
  });

  console.log(`cohort.mode: ${plan.mode}`);
  console.log(`cohort.importNotes: ${plan.importNoteCount}`);
  console.log(`cohort.appointments: ${plan.selectedAppointmentCount}`);
  console.log(`cohort.notes: ${plan.selectedNoteCount}`);
  console.log(`writes.appointments: ${plan.writes.filter((w) => w.kind === 'appointment').length}`);
  console.log(`writes.notes: ${plan.writes.filter((w) => w.kind === 'note').length}`);
  console.log(`alreadyOk.appointments: ${plan.alreadyOkAppointments}`);
  console.log(`alreadyOk.notes: ${plan.alreadyOkNotes}`);
  for (const item of plan.writes.slice(0, 10)) {
    console.log(`sample.write: ${item.kind}/${item.id}`);
  }
  if (plan.writes.length > 10) {
    console.log(`sample.write: ... +${plan.writes.length - 10} more`);
  }

  if (plan.writes.length === 0) {
    console.log('nothing to write');
    return;
  }
  if (opts.dryRun) {
    console.log('dry-run: no writes');
    return;
  }

  const written = await commitWrites(token, opts.orgId, toMember.uid, plan.writes);
  console.log(`wrote: ${written} docs (practitionerUid → ${toMember.uid})`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = {
  parseArgs,
  isImportNote,
  selectCohort,
  membershipSummary,
  DEFAULT_BEFORE,
};
