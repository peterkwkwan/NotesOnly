'use strict';

const nodemailer = require('nodemailer');

const INVITE_TTL_DAYS = 14;

function publicWebBase() {
  return (process.env.PUBLIC_WEB_URL || 'https://notesonly-e4829.web.app').replace(
    /\/$/,
    '',
  );
}

function inviteFromAddress() {
  return `NotesOnly <${process.env.GMAIL_USER}>`;
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
 * Send via Gmail SMTP (nodemailer). Returns { ok, status, error? }.
 * When GMAIL_USER / GMAIL_APP_PASSWORD are missing, returns failed without
 * throwing (invite still created).
 */
async function sendInviteEmail({ to, clinicName, role, joinUrl, expiresAt }) {
  const user = process.env.GMAIL_USER;
  const pass = process.env.GMAIL_APP_PASSWORD;
  if (!user || !pass) {
    return {
      ok: false,
      status: 'failed',
      error: 'GMAIL_USER / GMAIL_APP_PASSWORD not set',
    };
  }

  const subjectClinic = clinicName || 'NotesOnly';
  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: { user, pass },
  });

  try {
    await transporter.sendMail({
      from: inviteFromAddress(),
      to,
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
    });
    return { ok: true, status: 'sent' };
  } catch (err) {
    return {
      ok: false,
      status: 'failed',
      error: `Gmail SMTP: ${(err && err.message) || String(err)}`.slice(0, 200),
    };
  }
}

module.exports = {
  INVITE_TTL_DAYS,
  publicWebBase,
  joinUrlForToken,
  sendInviteEmail,
  roleLabel,
};
