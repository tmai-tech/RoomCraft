#!/usr/bin/env node
/**
 * Live vision smoke test — feedback room photos (5244fa22 / 53a501e6).
 * Usage: ROOMCRAFT_GROQ_API_KEY=gsk_... node scripts/test-vision-scan.mjs [images...]
 */
import fs from 'fs';
import path from 'path';

const key = process.env.ROOMCRAFT_GROQ_API_KEY || process.env.GROQ_API_KEY;
if (!key) {
  console.error('Set ROOMCRAFT_GROQ_API_KEY');
  process.exit(1);
}

const args = process.argv.slice(2);
let images = args.filter((p) => fs.existsSync(p));
if (images.length === 0) {
  const dir = '/tmp/roomcraft-feedback';
  const fix = 'test/fixtures/room_feedback';
  for (const d of [dir, fix]) {
    if (!fs.existsSync(d)) continue;
    const found = fs
      .readdirSync(d)
      .filter(
        (f) =>
          (f.startsWith('53a501e6-018_preview_') ||
            f.startsWith('5244fa22-4dd_preview_')) &&
          f.endsWith('.jpg'),
      )
      .map((f) => path.join(d, f));
    if (found.length) {
      images = found;
      break;
    }
  }
}
if (images.length === 0) {
  console.error('No images');
  process.exit(1);
}

const expected = {
  mustHaveTypes: ['WARDROBE', 'TABLE'],
  forbidTypes: ['BED', 'SOFA', 'TV_UNIT'],
  minOpenings: 1,
  description:
    'Study room: WARDROBE + TABLE required; no invented BED/SOFA/TV; wall-anchored.',
};

async function callVision(systemMsg, userText) {
  const content = [{ type: 'text', text: userText }];
  for (const p of images) {
    const b64 = fs.readFileSync(p).toString('base64');
    content.push({
      type: 'image_url',
      image_url: { url: `data:image/jpeg;base64,${b64}` },
    });
  }
  const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'meta-llama/llama-4-scout-17b-16e-instruct',
      temperature: 0.05,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: systemMsg },
        { role: 'user', content },
      ],
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(JSON.stringify(json).slice(0, 400));
  return JSON.parse(json.choices?.[0]?.message?.content || '{}');
}

console.log('Images:', images.map((p) => path.basename(p)).join(', '));
console.log('Pass 1 inventory…');
const inv = await callVision(
  'Strict inventory. Do not invent. JSON only.',
  `Same room photos. Return ONLY:
{"hasWardrobe":true,"hasDeskOrTable":true,"hasBed":false,"hasSofa":false,"hasTvUnit":false,"hasChair":false,"doorCount":2,"hasMeshOrSlidingGlass":true,"notes":"..."}
Booleans must match photos.`,
);
console.log('Inventory:', JSON.stringify(inv));

const invHint = [
  inv.hasWardrobe ? 'MUST include WARDROBE' : null,
  inv.hasDeskOrTable ? 'MUST include TABLE' : null,
  !inv.hasBed ? 'NO BED' : null,
  !inv.hasSofa ? 'NO SOFA' : null,
  !inv.hasTvUnit ? 'NO TV_UNIT' : null,
  inv.hasMeshOrSlidingGlass ? 'include balcony for mesh glass' : null,
]
  .filter(Boolean)
  .join('; ');

console.log('Pass 2 layout…');
let plan = await callVision(
  'Map room to top-down plan. Match inventory. wall+fromLeft+depth. Never invent forbidden types. JSON only.',
  `INVENTORY: ${invHint}
Scale door~2.8ft. Return roomWidth, roomLength, openings[{type,wall,fromLeft,width,confidence,evidence}], furniture[{type,wall,fromLeft,depth,dim:{w,l},confidence,evidence}].
Types: BED,WARDROBE,SOFA,TABLE,CHAIR,TV_UNIT,BOOKSHELF,NIGHTSTAND`,
);

const forbid = [];
if (!inv.hasBed) forbid.push('BED');
if (!inv.hasSofa) forbid.push('SOFA');
if (!inv.hasTvUnit) forbid.push('TV_UNIT');
if (Array.isArray(plan.furniture)) {
  plan.furniture = plan.furniture.filter((f) => {
    const t = String(f.type || '').toUpperCase();
    return !forbid.some((x) => t.includes(x));
  });
}

const outPath = '/tmp/roomcraft-feedback/live_scan_result.json';
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify({ inventory: inv, plan }, null, 2));
console.log('\n=== MODEL OUTPUT ===');
console.log(JSON.stringify(plan, null, 2));
console.log('\nWrote', outPath);

const furn = Array.isArray(plan.furniture) ? plan.furniture : [];
const types = furn.map((f) => String(f.type || '').toUpperCase());
const openings = plan.openings || plan.walls || [];
const missing = expected.mustHaveTypes.filter((t) => !types.includes(t));
const invented = expected.forbidTypes.filter((t) =>
  types.some((x) => x.includes(t)),
);
const wallAnchored =
  furn.length > 0 && furn.every((f) => f.wall && f.fromLeft != null);
const score = {
  furnitureCount: furn.length,
  types,
  missingMustHave: missing,
  inventedForbidden: invented,
  openingsCount: Array.isArray(openings) ? openings.length : 0,
  wallAnchored,
  pass:
    missing.length === 0 &&
    invented.length === 0 &&
    furn.length >= 2 &&
    wallAnchored &&
    (Array.isArray(openings) ? openings.length : 0) >= expected.minOpenings,
};
console.log('\n=== SCORE ===');
console.log(JSON.stringify(score, null, 2));
process.exit(score.pass ? 0 : 2);
