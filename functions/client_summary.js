'use strict';

const crypto = require('crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { loadMembership } = require('./invite_authz');

const MAX_NOTES = 5;
const MAX_APPTS = 5;
const MAX_SECTION_CHARS = 1500;
const MAX_OUTPUT_TOKENS = 256;
const RATE_MAX = 5;
const RATE_WINDOW_MS = 60 * 60 * 1000;
const DEFAULT_MODEL = 'gemini-2.0-flash';

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
      'Admins cannot generate SOAP-based summaries',
    );
  }
  if (!owner && practitioner) {
    for (const n of notes) {
      if (n.practitionerUid && n.practitionerUid !== auth.uid) {
        throw new HttpsError(
          'permission-denied',
          'Cannot summarize another practitioner’s notes',
        );
      }
    }
  }
  return member;
}

async function assertSummaryRateLimit(db, uid, clientId) {
  const id = `summary_${uid}_${clientId}`;
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
        count: 1,
        windowStart: Timestamp.fromMillis(now),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    if (count >= RATE_MAX) {
      throw new HttpsError(
        'resource-exhausted',
        'Too many regenerations; try again later',
      );
    }
    tx.update(ref, {
      count: count + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function callGemini(apiKey, userPrompt, model) {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent` +
    `?key=${encodeURIComponent(apiKey)}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: 'user', parts: [{ text: userPrompt }] }],
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: MAX_OUTPUT_TOKENS,
      },
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = body?.error?.message || `Gemini HTTP ${res.status}`;
    console.error('gemini error', res.status, msg);
    throw new HttpsError('internal', 'Summary generation failed');
  }
  const text = body?.candidates?.[0]?.content?.parts
    ?.map((p) => p.text || '')
    .join('')
    .trim();
  if (!text) {
    throw new HttpsError('internal', 'Empty summary from model');
  }
  return text;
}

/**
 * Auth + ACL + Gemini. Callers inject apiKey from defineSecret.
 */
async function generateClientSummary(db, auth, data, apiKey) {
  if (!auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in required');
  }
  if (!apiKey) {
    throw new HttpsError('failed-precondition', 'GEMINI_API_KEY not configured');
  }
  const payload = normalizePayload(data);
  await assertCanSummarize(db, auth, payload.orgId, payload.notes);
  await assertSummaryRateLimit(db, auth.uid, payload.clientId);

  const userPrompt = buildUserPrompt(payload);
  const hash = inputHashFor(payload);
  const model = process.env.GEMINI_MODEL || DEFAULT_MODEL;
  const summary = await callGemini(apiKey, userPrompt, model);
  const generatedAt = new Date().toISOString();
  console.log(
    JSON.stringify({
      event: 'client_summary',
      orgId: payload.orgId,
      clientId: payload.clientId,
      noteCount: payload.notes.length,
      model,
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

module.exports = {
  MAX_NOTES,
  MAX_APPTS,
  SYSTEM_PROMPT,
  truncate,
  normalizePayload,
  buildUserPrompt,
  inputHashFor,
  assertCanSummarize,
  generateClientSummary,
};
