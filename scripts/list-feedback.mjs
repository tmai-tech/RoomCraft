#!/usr/bin/env node
/**
 * List recent feedback reports from Firestore (for agent/team review).
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=.secrets/*-firebase-adminsdk-*.json node scripts/list-feedback.mjs
 */
import fs from 'fs';
import crypto from 'crypto';
import path from 'path';

const saPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!saPath || !fs.existsSync(saPath)) {
  console.error('Set GOOGLE_APPLICATION_CREDENTIALS to the Firebase SA JSON');
  process.exit(1);
}
const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
function b64url(input) {
  return Buffer.from(input).toString('base64url');
}
async function getToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/cloud-platform',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claim))}`;
  const sign = crypto.createSign('RSA-SHA256');
  sign.update(unsigned);
  sign.end();
  const jwt = `${unsigned}.${sign.sign(sa.private_key, 'base64url')}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }).toString(),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(JSON.stringify(json));
  return json.access_token;
}

const project = 'roomcraft-e1312';
const token = await getToken();
// RunQuery
const body = {
  structuredQuery: {
    from: [{ collectionId: 'feedback' }],
    orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
    limit: 20,
  },
};
const res = await fetch(
  `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:runQuery`,
  {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  },
);
const rows = await res.json();
if (!Array.isArray(rows)) {
  console.log(JSON.stringify(rows, null, 2));
  process.exit(1);
}
for (const row of rows) {
  const doc = row.document;
  if (!doc) continue;
  const f = doc.fields || {};
  const get = (k) => {
    const v = f[k];
    if (!v) return null;
    return v.stringValue ?? v.integerValue ?? v.booleanValue ?? v.timestampValue ?? JSON.stringify(v);
  };
  const urls = f.screenshotUrls?.arrayValue?.values?.map((x) => x.stringValue) || [];
  console.log('---');
  console.log('id:', get('id'));
  console.log('category:', get('category'));
  console.log('version:', get('versionLabel'));
  console.log('platform:', get('platform'));
  console.log('created:', get('createdAt'));
  console.log('screenshots:', get('screenshotCount'), urls);
  console.log('message:', get('message'));
  console.log('contact:', get('contactEmail'));
}
