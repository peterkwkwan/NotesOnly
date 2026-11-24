'use strict';

const crypto = require('crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { loadMembership } = require('./invite_authz');

const MAX_NOTES = 5;
const MAX_APPTS = 5;
const MAX_SECTION_CHARS = 1500;
const MAX_OUTPUT_TOKENS = 256;
const MAX_DIAGNOSIS_OUTPUT_TOKENS = 512;
const RATE_MAX = 5;
const RATE_WINDOW_MS = 60 * 60 * 1000;
// gemini-2.0-flash retired 2026-06-01; new projects get NOT_FOUND on that id.
// 3.5 Flash-Lite PayGo is on the global endpoint (not us-central1).
const DEFAULT_MODEL = 'gemini-3.5-flash-lite';
const DEFAULT_VERTEX_LOCATION = 'global';
const METADATA_TOKEN_URL =
  'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token';

const SYSTEM_PROMPT = [
  'You are a clinical assistant for pelvic / physio SOAP notes.',
  'Output 2–5 sentences of plain language for the treating practitioner.',
  'Emphasize the most recent visit; weave older visits briefly.',
  'Include current/past diagnosis only if provided.',
  'Do not invent findings, dates, or diagnoses.',
  'Do not include patient name or identifiers; refer to “the client”.',
  'If notes are empty, say there is not enough charted information.',
  'Return only the summary sentences — no title, bullets, or chain-of-thought.',
].join(' ');

const DIAGNOSIS_SYSTEM_PROMPT = [
  'You are a clinical assistant for pelvic / physio SOAP notes.',
  'Propose a short ranked list of major diagnoses for the client chart from the notes and existing diagnosis fields provided.',
  'Return 3–5 concise clinical label strings (fewer if fewer are supported by the chart). Rank most likely / primary first.',
  'Each label should be a short phrase suitable for a single diagnosisCurrent chart field — not a paragraph or comma-joined dump.',
  'Do not invent diagnoses unsupported by the charted notes or existing fields.',
  'If there is not enough charted information, return an empty majorDiagnoses array and explain in caveats.',
  'Do not include patient name or identifiers; refer to “the client”.',
  'Return ONLY compact JSON with keys majorDiagnoses (string array), caveats — no markdown fences or chain-of-thought.',
].join(' ');
const MAX_MAJOR_DIAGNOSES = 5;
const MAX_DIAGNOSIS_LABEL_CHARS = 200;

function truncate(text, max) {
  const s = String(text ?? '').trim();
  if (s.length <= max) return s;
  return `${s.slice(0, max - 1)}…`;
}

function hasRole(member, role) {
  const roles = member?.roles;
  return Array.isArray(roles) && roles.includes(role);
}

function ymd(isoOrDate) {
  const raw = String(isoOrDate ?? '').trim();
  if (!raw) return '';
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) return raw.slice(0, 10);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function normalizeNotes(raw) {
  if (!Array.isArray(raw)) {
    throw new HttpsError('invalid-argument', 'notes must be an array');
  }
  if (raw.length > MAX_NOTES) {
    throw new HttpsError('invalid-argument', `At most ${MAX_NOTES} notes`);
  }
  return raw.map((n, i) => {
    if (!n || typeof n !== 'object') {
      throw new HttpsError('invalid-argument', `notes[${i}] invalid`);
    }
    const practitionerUid = String(n.practitionerUid ?? '').trim();
    return {
      noteDate: String(n.noteDate ?? '').trim(),
      subjective: truncate(n.subjective, MAX_SECTION_CHARS),
      objective: truncate(n.objective, MAX_SECTION_CHARS),
      assessment: truncate(n.assessment, MAX_SECTION_CHARS),
      plan: truncate(n.plan, MAX_SECTION_CHARS),
      practitionerUid,
      remoteId: String(n.remoteId ?? '').trim(),
      updatedAt: String(n.updatedAt ?? '').trim(),
    };
  });
}

function normalizeAppts(raw) {
  if (raw == null) return [];
  if (!Array.isArray(raw)) {
    throw new HttpsError('invalid-argument', 'appointments must be an array');
  }
  if (raw.length > MAX_APPTS) {
    throw new HttpsError('invalid-argument', `At most ${MAX_APPTS} appointments`);
  }
  return raw.map((a, i) => {
    if (!a || typeof a !== 'object') {
      throw new HttpsError('invalid-argument', `appointments[${i}] invalid`);
    }
    return {
      startsAt: String(a.startsAt ?? '').trim(),
      status: String(a.status ?? '').trim() || 'scheduled',
    };
  });
}

function normalizePayload(data) {
  const orgId = String(data?.orgId ?? '').trim();
  const clientId = String(data?.clientId ?? '').trim();
  if (!orgId) throw new HttpsError('invalid-argument', 'orgId required');
  if (!clientId) throw new HttpsError('invalid-argument', 'clientId required');
  return {
    orgId,
    clientId,
    diagnosisCurrent: truncate(data?.diagnosisCurrent, MAX_SECTION_CHARS),
    diagnosisPast: truncate(data?.diagnosisPast, MAX_SECTION_CHARS),
    notes: normalizeNotes(data?.notes ?? []),
    appointments: normalizeAppts(data?.appointments),
    force: data?.force === true,
  };
}

function buildUserPrompt(payload) {
  const lines = [
    `Diagnosis (current): ${payload.diagnosisCurrent || '(none)'}`,
    `Diagnosis (past): ${payload.diagnosisPast || '(none)'}`,
  ];
  if (payload.appointments.length === 0) {
    lines.push('Recent appointments: (none)');
  } else {
    lines.push(
      `Recent appointments: ${payload.appointments
        .map((a) => `${ymd(a.startsAt)} ${a.status}`)
        .join('; ')}`,
    );
  }
  lines.push('Notes (newest first):');
  if (payload.notes.length === 0) {
    lines.push('(none)');
  } else {
    for (const n of payload.notes) {
      lines.push(`[${ymd(n.noteDate) || 'unknown date'}]`);
      lines.push(`S: ${n.subjective || ''}`);
      lines.push(`O: ${n.objective || ''}`);
      lines.push(`A: ${n.assessment || ''}`);
      lines.push(`P: ${n.plan || ''}`);
    }
  }
  return lines.join('\n');
}

function inputHashFor(payload) {
  const material = JSON.stringify({
    orgId: payload.orgId,
    clientId: payload.clientId,
    diagnosisCurrent: payload.diagnosisCurrent,
    diagnosisPast: payload.diagnosisPast,
    notes: payload.notes.map((n) => ({
      remoteId: n.remoteId,
      updatedAt: n.updatedAt,
      noteDate: n.noteDate,
      subjective: n.subjective,
      objective: n.objective,
      assessment: n.assessment,
      plan: n.plan,
    })),
    appointments: payload.appointments,
  });
  return crypto.createHash('sha256').update(material).digest('hex').slice(0, 32);
}

async function assertCanSummarize(db, auth, orgId, notes) {
  const member = await loadMembership(db, orgId, auth.uid);
  if (!member) {
    throw new HttpsError('permission-denied', 'Not a member of this clinic');
  }
  const owner = hasRole(member, 'owner');
  const practitioner = hasRole(member, 'practitioner');
  const adminOnly = hasRole(member, 'admin') && !owner && !practitioner;
  if (adminOnly || (!owner && !practitioner)) {
    throw new HttpsError(
      'permission-denied',
      'Admins cannot use SOAP-derived AI features',
    );
  }
  if (!owner && practitioner) {
    for (const n of notes) {
      if (n.practitionerUid && n.practitionerUid !== auth.uid) {
        throw new HttpsError(
          'permission-denied',
          'Cannot use another practitioner’s notes',
        );
      }
    }
  }
  return member;
}

async function assertAiRateLimit(db, uid, clientId, kind) {
  const id = `${kind}_${uid}_${clientId}`;
  const ref = db.collection('summaryRateLimits').doc(id);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const data = snap.exists ? snap.data() : null;
    const windowStart = data?.windowStart?.toMillis?.() ?? 0;
    let count = data?.count ?? 0;
    if (!windowStart || now - windowStart > RATE_WINDOW_MS) {
      tx.set(ref, {
        uid,
        clientId,
        kind,
        count: 1,
        windowStart: Timestamp.fromMillis(now),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    if (count >= RATE_MAX) {
      throw new HttpsError(
        'resource-exhausted',
        'Too many AI requests; try again later',
      );
    }
    tx.update(ref, {
      count: count + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

function assertSummaryRateLimit(db, uid, clientId) {
  return assertAiRateLimit(db, uid, clientId, 'summary');
}

function assertDiagnosisRateLimit(db, uid, clientId) {
  return assertAiRateLimit(db, uid, clientId, 'diagnosis');
}

function gcpProjectId() {
  if (process.env.GCLOUD_PROJECT) return process.env.GCLOUD_PROJECT;
  if (process.env.GCP_PROJECT) return process.env.GCP_PROJECT;
  if (process.env.GOOGLE_CLOUD_PROJECT) return process.env.GOOGLE_CLOUD_PROJECT;
  try {
    return JSON.parse(process.env.FIREBASE_CONFIG || '{}').projectId || '';
  } catch {
    return '';
  }
}

function vertexLocation() {
  return process.env.VERTEX_LOCATION || DEFAULT_VERTEX_LOCATION;
}

/** Regional host is `{loc}-aiplatform…`; global must use bare `aiplatform.googleapis.com`. */
function vertexGenerateUrl(projectId, location, model) {
  const host =
    location === 'global'
      ? 'https://aiplatform.googleapis.com'
      : `https://${location}-aiplatform.googleapis.com`;
  return (
    `${host}/v1/projects/${projectId}/locations/${location}` +
    `/publishers/google/models/${model}:generateContent`
  );
}

/** ADC via Cloud Functions / Cloud Run metadata server (default runtime SA). */
async function getAdcAccessToken() {
  const res = await fetch(METADATA_TOKEN_URL, {
    headers: { 'Metadata-Flavor': 'Google' },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) {
    console.error('adc token error', res.status, body?.error || body);
    throw new HttpsError(
      'failed-precondition',
      'Vertex AI credentials unavailable (ADC)',
    );
  }
  return body.access_token;
}

async function callVertexGemini(userPrompt, model, opts = {}) {
  const systemPrompt = opts.systemPrompt || SYSTEM_PROMPT;
  const maxOutputTokens = opts.maxOutputTokens || MAX_OUTPUT_TOKENS;
  const temperature = opts.temperature ?? 0.3;
  const httpError = opts.httpError || 'Summary generation failed';
  const emptyError = opts.emptyError || 'Empty summary from model';
  const projectId = gcpProjectId();
  if (!projectId) {
    throw new HttpsError('failed-precondition', 'GCP project id not set');
  }
  const location = vertexLocation();
  const token = await getAdcAccessToken();
  const url = vertexGenerateUrl(projectId, location, model);
  const generationConfig = {
    temperature,
    maxOutputTokens,
  };
  if (opts.responseMimeType) {
    generationConfig.responseMimeType = opts.responseMimeType;
  }
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemPrompt }] },
      contents: [{ role: 'user', parts: [{ text: userPrompt }] }],
      generationConfig,
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = body?.error?.message || `Vertex Gemini HTTP ${res.status}`;
    console.error('vertex gemini error', res.status, msg);
    throw new HttpsError('internal', httpError);
  }
  const text = body?.candidates?.[0]?.content?.parts
    ?.map((p) => p.text || '')
    .join('')
    .trim();
  if (!text) {
    throw new HttpsError('internal', emptyError);
  }
  return text;
}

/** Parse model JSON for diagnosis propose; strips optional markdown fences. */
function parseDiagnosisProposal(text) {
  let raw = String(text ?? '').trim();
  const fence = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) raw = fence[1].trim();
  let obj;
  try {
    obj = JSON.parse(raw);
  } catch {
    throw new HttpsError('internal', 'Invalid diagnosis proposal from model');
  }
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
    throw new HttpsError('internal', 'Invalid diagnosis proposal from model');
  }
  const rawList = Array.isArray(obj.majorDiagnoses) ? obj.majorDiagnoses : [];
  const seen = new Set();
  const majorDiagnoses = [];
  for (const item of rawList) {
    const label = truncate(item, MAX_DIAGNOSIS_LABEL_CHARS);
    if (!label) continue;
    const key = label.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    majorDiagnoses.push(label);
    if (majorDiagnoses.length >= MAX_MAJOR_DIAGNOSES) break;
  }
  return {
    majorDiagnoses,
    caveats: truncate(obj.caveats, 500),
  };
}

/**
 * Auth + ACL + Vertex AI Gemini (ADC / runtime service account).
 */
async function generateClientSummary(db, auth, data) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in required');
  }
  const payload = normalizePayload(data);
  await assertCanSummarize(db, auth, payload.orgId, payload.notes);
  await assertSummaryRateLimit(db, auth.uid, payload.clientId);

  const userPrompt = buildUserPrompt(payload);
  const hash = inputHashFor(payload);
  const model = process.env.GEMINI_MODEL || DEFAULT_MODEL;
  const summary = await callVertexGemini(userPrompt, model);
  const generatedAt = new Date().toISOString();
  console.log(
    JSON.stringify({
      event: 'client_summary',
      orgId: payload.orgId,
      clientId: payload.clientId,
      noteCount: payload.notes.length,
      model,
      location: vertexLocation(),
      inputHash: hash,
    }),
  );
  return {
    summary,
    model,
    generatedAt,
    inputHash: hash,
  };
}

/**
 * Propose ranked majorDiagnoses from SOAP history (pill pick → write diagnosisCurrent in app).
 */
async function proposeDiagnosis(db, auth, data) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in required');
  }
  const payload = normalizePayload(data);
  await assertCanSummarize(db, auth, payload.orgId, payload.notes);
  await assertDiagnosisRateLimit(db, auth.uid, payload.clientId);

  if (
    payload.notes.length === 0 &&
    !payload.diagnosisCurrent &&
    !payload.diagnosisPast
  ) {
    return {
      majorDiagnoses: [],
      caveats: 'Not enough published notes to propose a diagnosis yet.',
      model: process.env.GEMINI_MODEL || DEFAULT_MODEL,
      generatedAt: new Date().toISOString(),
      inputHash: inputHashFor(payload),
    };
  }

  const userPrompt = [
    'Propose 3–5 ranked major diagnosis labels from this clinical bundle.',
    'Each label is a short phrase for a single diagnosisCurrent field pick.',
    '',
    buildUserPrompt(payload),
  ].join('\n');
  const hash = inputHashFor(payload);
  const model = process.env.GEMINI_MODEL || DEFAULT_MODEL;
  const raw = await callVertexGemini(userPrompt, model, {
    systemPrompt: DIAGNOSIS_SYSTEM_PROMPT,
    maxOutputTokens: MAX_DIAGNOSIS_OUTPUT_TOKENS,
    temperature: 0.2,
    responseMimeType: 'application/json',
    httpError: 'Diagnosis proposal failed',
    emptyError: 'Empty diagnosis proposal from model',
  });
  const proposal = parseDiagnosisProposal(raw);
  const generatedAt = new Date().toISOString();
  console.log(
    JSON.stringify({
      event: 'propose_diagnosis',
      orgId: payload.orgId,
      clientId: payload.clientId,
      noteCount: payload.notes.length,
      majorCount: proposal.majorDiagnoses.length,
      model,
      location: vertexLocation(),
      inputHash: hash,
    }),
  );
  return {
    ...proposal,
    model,
    generatedAt,
    inputHash: hash,
  };
}

module.exports = {
  MAX_NOTES,
  MAX_APPTS,
  MAX_MAJOR_DIAGNOSES,
  DEFAULT_MODEL,
  DEFAULT_VERTEX_LOCATION,
  SYSTEM_PROMPT,
  DIAGNOSIS_SYSTEM_PROMPT,
  truncate,
  normalizePayload,
  buildUserPrompt,
  inputHashFor,
  parseDiagnosisProposal,
  vertexGenerateUrl,
  assertCanSummarize,
  generateClientSummary,
  proposeDiagnosis,
};
