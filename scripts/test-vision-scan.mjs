#!/usr/bin/env node
/**
 * Live vision scan smoke test against real room photos (feedback 53a501e6-018).
 * Usage:
 *   ROOMCRAFT_GROQ_API_KEY=gsk_... node scripts/test-vision-scan.mjs [image...]
 *   Or CI: images from /tmp/roomcraft-feedback/53a501e6-018_preview_*.jpg
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
  if (fs.existsSync(dir)) {
    images = fs
      .readdirSync(dir)
      .filter((f) => f.startsWith('53a501e6-018_preview_') && f.endsWith('.jpg'))
      .map((f) => path.join(dir, f));
  }
}
if (images.length === 0) {
  console.error('No images');
  process.exit(1);
}

const system = `You map real rooms from phone photos for a floor-plan app.
Estimate a realistic top-down plan in feet. LIST every clearly visible major piece
(wardrobe, desk/table, chairs). Missing visible furniture is a failure.
Use wall + fromLeft + depth for EVERY furniture/opening (not free XY). JSON only.`;

const prompt = `Map this room from the photos. Same room, multiple angles.
Scale: door ~2.8 ft, wardrobe depth ~2 ft.

CRITICAL: use wall-anchored fields only:
- wall: south|north|east|west
- fromLeft: feet from left corner while facing that wall from inside
- depth: feet into room from wall (furniture only)

Return ONLY JSON:
{
  "roomWidth": 12.0,
  "roomLength": 14.0,
  "sizeConfidence": 0.65,
  "openings": [
    {"type": "door", "wall": "south", "fromLeft": 1.0, "width": 2.8, "confidence": 0.9, "evidence": "entry door"},
    {"type": "balcony", "wall": "east", "fromLeft": 0.5, "width": 7.0, "confidence": 0.85, "evidence": "mesh sliding doors"}
  ],
  "furniture": [
    {"type": "WARDROBE", "wall": "north", "fromLeft": 4.0, "depth": 1.2, "dim": {"w": 8.0, "l": 2.0}, "confidence": 0.9, "evidence": "pink/white sliding wardrobe"},
    {"type": "TABLE", "wall": "east", "fromLeft": 3.0, "depth": 1.5, "dim": {"w": 4.0, "l": 2.0}, "confidence": 0.85, "evidence": "desk with monitors"}
  ]
}
Types: BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND`;

// Human expected plan for feedback photos (study + wardrobe room)
const expected = {
  mustHaveTypes: ['WARDROBE', 'TABLE'],
  niceTypes: ['CHAIR', 'DOOR'],
  description:
    'Small room: long pink/white sliding wardrobe, mesh sliding doors/balcony, desk with monitors/laptops, 1–2 interior doors, AC. No sofa/bed required if not visible.',
};

const content = [{ type: 'text', text: prompt }];
for (const p of images) {
  const b64 = fs.readFileSync(p).toString('base64');
  content.push({
    type: 'image_url',
    image_url: { url: `data:image/jpeg;base64,${b64}` },
  });
}

const body = {
  model: 'meta-llama/llama-4-scout-17b-16e-instruct',
  temperature: 0.1,
  response_format: { type: 'json_object' },
  messages: [
    { role: 'system', content: system },
    { role: 'user', content },
  ],
};

console.log('Images:', images.map((p) => path.basename(p)).join(', '));
console.log('Calling Groq Llama 4 Scout…');

const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify(body),
});

const json = await res.json();
if (!res.ok) {
  console.error('API error', res.status, JSON.stringify(json).slice(0, 500));
  process.exit(1);
}

const text = json.choices?.[0]?.message?.content || '';
let plan;
try {
  plan = JSON.parse(text);
} catch {
  console.error('Bad JSON', text.slice(0, 800));
  process.exit(1);
}

const outPath = '/tmp/roomcraft-feedback/live_scan_result.json';
fs.writeFileSync(outPath, JSON.stringify(plan, null, 2));
console.log('\n=== MODEL OUTPUT ===');
console.log(JSON.stringify(plan, null, 2));
console.log('\nWrote', outPath);

const furn = Array.isArray(plan.furniture) ? plan.furniture : [];
const types = furn.map((f) => String(f.type || '').toUpperCase());
const openings = plan.openings || plan.walls || [];
console.log('\n=== EXPECTED (human, from photos) ===');
console.log(expected.description);
console.log('Must have types:', expected.mustHaveTypes.join(', '));

const missing = expected.mustHaveTypes.filter((t) => !types.includes(t));
const score = {
  roomSize: plan.roomWidth && plan.roomLength ? 'ok' : 'missing',
  furnitureCount: furn.length,
  types,
  missingMustHave: missing,
  openingsCount: Array.isArray(openings) ? openings.length : 0,
  pass: missing.length === 0 && furn.length >= 2,
};
console.log('\n=== SCORE ===');
console.log(JSON.stringify(score, null, 2));
process.exit(score.pass ? 0 : 2);
