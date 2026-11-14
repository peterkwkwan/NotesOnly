'use strict';

const INVITE_TTL_DAYS = 14;

function publicWebBase() {
  return (process.env.PUBLIC_WEB_URL || 'https://notesonly-e4829.web.app').replace(
    /\/$/,
    '',
  );
}

function inviteFromAddress() {
  return process.env.INVITE_FROM_EMAIL || 'NotesOnly <onboarding@resend.dev>';
}

function joinUrlForToken(token) {
  return `${publicWebBase()}/join?token=${encodeURIComponent(token)}`;
}

function formatExpiry(expiresAt) {
  return expiresAt.toUTCString();
}

function inviteEmailHtml({ clinicName, roleLabel, joinUrl, expiresAt }) {
  const clinic = clinicName || 'a NotesOnly clinic';
  const role = roleLabel ? ` as ${roleLabel}` : '';
  return `<!doctype html>
<html><body style="font-family:system-ui,sans-serif;line-height:1.5;color:#1a1a1a">
  <p>You have been invited to join <strong>${escapeHtml(clinic)}</strong>${escapeHtml(role)} on NotesOnly.</p>
  <p><a href="${escapeAttr(joinUrl)}" style="display:inline-block;padding:12px 18px;background:#b63c70;color:#fff;text-decoration:none;border-radius:6px">Join clinic</a></p>
  <p style="font-size:13px;color:#555">Or open this link:<br><a href="${escapeAttr(joinUrl)}">${escapeHtml(joinUrl)}</a></p>
  <p style="font-size:13px;color:#555">This invite expires on ${escapeHtml(formatExpiry(expiresAt))}.</p>
  <p style="font-size:13px;color:#555">Ignore this email if you did not expect it.</p>
</body></html>`;
}

function inviteEmailText({ clinicName, roleLabel, joinUrl, expiresAt }) {
  const clinic = clinicName || 'a NotesOnly clinic';
  const role = roleLabel ? ` as ${roleLabel}` : '';
  return [
    `You have been invited to join ${clinic}${role} on NotesOnly.`,
    '',
    `Join: ${joinUrl}`,
    '',
    `Expires: ${formatExpiry(expiresAt)}`,
    '',
    'Ignore this email if you did not expect it.',
  ].join('\n');
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function escapeAttr(s) {
  return escapeHtml(s).replace(/'/g, '&#39;');
}

function roleLabel(role) {
  if (role === 'owner') return 'Owner';
  if (role === 'admin') return 'Admin';
  if (role === 'practitioner') return 'Practitioner';
  return role || '';
}

/**
 * Send via Resend HTTP API. Returns { ok, status, error? }.
 * When RESEND_API_KEY is missing, returns failed without throwing (invite still created).
 */
async function sendInviteEmail({ to, clinicName, role, joinUrl, expiresAt }) {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    return { ok: false, status: 'failed', error: 'RESEND_API_KEY not set' };
  }
  const subjectClinic = clinicName || 'NotesOnly';
  const body = {
    from: inviteFromAddress(),
    to: [to],
    subject: `Join ${subjectClinic} on NotesOnly`,
    html: inviteEmailHtml({
      clinicName,
      roleLabel: roleLabel(role),
      joinUrl,
      expiresAt,
    }),
    text: inviteEmailText({
      clinicName,
      roleLabel: roleLabel(role),
      joinUrl,
      expiresAt,
    }),
  };
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    return {
      ok: false,
      status: 'failed',
      error: `Resend ${res.status}: ${text.slice(0, 200)}`,
    };
  }
  return { ok: true, status: 'sent' };
}

module.exports = {
  INVITE_TTL_DAYS,
  publicWebBase,
  joinUrlForToken,
  sendInviteEmail,
  roleLabel,
};
