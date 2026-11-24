'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  buildUserPrompt,
  normalizePayload,
  inputHashFor,
  truncate,
  parseDiagnosisProposal,
  MAX_NOTES,
  SYSTEM_PROMPT,
  DIAGNOSIS_SYSTEM_PROMPT,
  DEFAULT_MODEL,
  DEFAULT_VERTEX_LOCATION,
  vertexGenerateUrl,
} = require('../client_summary');

describe('client_summary prompt', () => {
  it('builds newest-first SOAP user prompt without names', () => {
    const payload = normalizePayload({
      orgId: 'org1',
      clientId: 'cli1',
      diagnosisCurrent: 'PFD',
      diagnosisPast: '',
      notes: [
        {
          noteDate: '2026-11-20T10:00:00.000Z',
          subjective: 'Less pain',
          objective: 'Tone improved',
          assessment: 'Progressing',
          plan: 'HEP',
          practitionerUid: 'u1',
          remoteId: 'n1',
          updatedAt: '2026-11-20T11:00:00.000Z',
        },
      ],
      appointments: [{ startsAt: '2026-11-20T10:00:00.000Z', status: 'completed' }],
    });
    const prompt = buildUserPrompt(payload);
    assert.match(prompt, /Diagnosis \(current\): PFD/);
    assert.match(prompt, /Notes \(newest first\):/);
    assert.match(prompt, /\[2026-11-20\]/);
    assert.match(prompt, /S: Less pain/);
    assert.equal(prompt.includes('Ada'), false);
    assert.ok(SYSTEM_PROMPT.includes('2–5 sentences'));
  });

  it('rejects more than MAX_NOTES', () => {
    const notes = Array.from({ length: MAX_NOTES + 1 }, (_, i) => ({
      noteDate: '2026-01-01',
      subjective: `s${i}`,
      remoteId: `n${i}`,
    }));
    assert.throws(
      () => normalizePayload({ orgId: 'o', clientId: 'c', notes }),
      (err) => err.code === 'invalid-argument',
    );
  });

  it('truncates long SOAP sections', () => {
    const long = 'x'.repeat(2000);
    assert.equal(truncate(long, 10).endsWith('…'), true);
    assert.ok(truncate(long, 10).length <= 10);
  });

  it('hashes stably for identical payloads', () => {
    const data = {
      orgId: 'org1',
      clientId: 'cli1',
      diagnosisCurrent: 'A',
      notes: [
        {
          noteDate: '2026-01-01',
          subjective: 's',
          objective: 'o',
          assessment: 'a',
          plan: 'p',
          remoteId: 'n1',
          updatedAt: 't1',
        },
      ],
    };
    const a = inputHashFor(normalizePayload(data));
    const b = inputHashFor(normalizePayload(data));
    assert.equal(a, b);
    assert.match(a, /^[a-f0-9]{32}$/);
  });

  it('defaults to a current Vertex Flash-Lite on the global host', () => {
    assert.equal(DEFAULT_MODEL, 'gemini-3.5-flash-lite');
    assert.equal(DEFAULT_VERTEX_LOCATION, 'global');
    assert.equal(
      vertexGenerateUrl('notesonly-e4829', 'global', DEFAULT_MODEL),
      'https://aiplatform.googleapis.com/v1/projects/notesonly-e4829/locations/global/publishers/google/models/gemini-3.5-flash-lite:generateContent',
    );
    assert.equal(
      vertexGenerateUrl('notesonly-e4829', 'us-central1', 'gemini-2.5-flash'),
      'https://us-central1-aiplatform.googleapis.com/v1/projects/notesonly-e4829/locations/us-central1/publishers/google/models/gemini-2.5-flash:generateContent',
    );
  });
});

describe('proposeDiagnosis parse', () => {
  it('parses JSON and strips markdown fences', () => {
    const parsed = parseDiagnosisProposal(
      '```json\n{"diagnosisCurrent":"stress UI","diagnosisPast":"PGP","caveats":"Based on latest A"}\n```',
    );
    assert.equal(parsed.diagnosisCurrent, 'stress UI');
    assert.equal(parsed.diagnosisPast, 'PGP');
    assert.equal(parsed.caveats, 'Based on latest A');
    assert.ok(DIAGNOSIS_SYSTEM_PROMPT.includes('diagnosisCurrent'));
  });

  it('rejects non-JSON model output', () => {
    assert.throws(
      () => parseDiagnosisProposal('not json'),
      (err) => err.code === 'internal',
    );
  });
});
