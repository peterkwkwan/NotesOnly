'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  buildUserPrompt,
  normalizePayload,
  inputHashFor,
  truncate,
  MAX_NOTES,
  SYSTEM_PROMPT,
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
});
