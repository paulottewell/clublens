# ClubLens — CLAUDE.md

## Project overview
ClubLens is a fully offline, single-HTML-file browser-based clubs membership analyser
built for St Matthew's C of E Primary Academy (within St Christopher's Trust).
It reads a Bromcom `.xlsx` clubs export and generates participation analysis across
priority groups. All processing runs locally in the browser — no data ever leaves
the device.

**Current version:** v17
**Key file:** `docs/ClubLens_v17.html` — self-contained, no companion files required.
SheetJS is inlined; no separate `xlsx.full.min.js` is needed.

**Hosted at:** clublens.vercel.app (served from `docs/` in the GitHub repo)
**Repo:** github.com/paulottewell/clublens

**Pilot tester:** Suzie (headteacher, St Matthew's C of E Primary Academy)
**Author / IP owner:** Paul Ottewell

---

## Architecture

- Single HTML file, ~821 KB, with two `<script>` blocks:
  - Block 1: SheetJS `xlsx.full.min.js` v0.20.3 (inlined, ~709 KB as text)
  - Block 2: ClubLens application code (~77.8 KB)
- No build process, no dependencies to install, no server
- CSP: hash-based (no nonce), see Security section below
- No `unsafe-inline` in `script-src`
- All handlers wired via `addEventListener`; no inline event handlers
- `localStorage` used only for Action Plan text (no pupil data), key: `clublens_actionplan_v1`

---

## Brand colours (St Christopher's Trust official palette)
```
--navy:   #19224E
--coral:  #F16069
--teal:   #8BD0C0
--gold:   #FFD372
--purple: #7151A1
--blue:   #5E6EB4
--paper:  #F8F7F4
--cream:  #EEEAE2
--border: #DDD8CE
--muted:  #6B6880
```

---

## Content Security Policy (v16)

**Type:** Hash-based (NOT nonce-based). The static nonce `clublens2026` used in
earlier versions was a security vulnerability and was replaced in v12.

```
default-src 'none';
script-src  'sha256-WsrcBCCiRfW+lhHhqF/lsae5GqgkS3Ns4wNEflZpZSM='
            'sha256-d1ZfdsEywUeZ3DZGVKg/+tUuV7ZdiWk2DXSLs+PpGFI=';
style-src   'unsafe-inline';
img-src     data:;
connect-src 'none';
frame-src   'none';
object-src  'none';
base-uri    'none';
```

Hash 1 = SheetJS block. Hash 2 = ClubLens app block.

**CRITICAL:** Any edit to either `<script>` block invalidates its hash and will
cause the browser to refuse to run the script. After any JS edit, both hashes
must be recomputed and the CSP `<meta>` tag updated. Use this script:

```python
import hashlib, base64, re

with open('ClubLens_v13.html') as f:
    content = f.read()

pattern = re.compile(r'<script>(.*?)</script>', re.DOTALL)
for i, m in enumerate(pattern.finditer(content)):
    digest = hashlib.sha256(m.group(1).encode('utf-8')).digest()
    b64 = base64.b64encode(digest).decode('ascii')
    print(f"Block {i+1}: 'sha256-{b64}'")
```

Then replace the `script-src` line in the CSP `<meta>` tag with the new hashes.

---

## Data parsed from Bromcom export

| Field | Source column |
|-------|--------------|
| Preferred first name | `Preferred First name` |
| Preferred last name | `Preferred Last name` |
| Year group | `Year Group Name` |
| Pupil Premium | `Ever FSM 6 Flag` = Yes |
| SEN status | `SEN Status Code` — E = EHCP, K = SEN Support |
| EAL | `EAL Flag` = Yes |
| Service children | `Service Children In Education Code` (non-empty, non-N) |
| Looked after | `PP Looked After` = Yes |
| Spring clubs | `Club-*` columns (active, no NOT ACTIVE marker) |
| Autumn clubs | `Club-*` columns containing `NOT ACTIVE` |
| Summer clubs | `Club-*` columns (active) — **currently requires naming convention** |
| Special items | Breakfast Club, After School Club, BF Residential, Schools Challenge |
| Always ignored | `Outstanding Lunch Balances` |

---

## Tab structure

**Top-level tabs:** Spring Term | Autumn Term | Summer Term | Action Plan

Summer tab is hidden unless summer clubs are detected.

**Per-term sections:**
Overview | Pupils | Clubs | Breakfast Club | After School Club | Equity | Priority Groups | Special Items

**Priority Groups sub-tabs:**
Pupil Premium | SEN | Service Children | EAL | Looked After

---

## Column parsing — how Bromcom columns become club names

### `colCategory(col)` — determines which term a column belongs to
```javascript
function colCategory(col) {
  if (!col.startsWith('Club-')) return 'demo';
  if (ALWAYS_IGNORE.some(rx => rx.test(col))) return 'ignore';
  if (SPECIAL_ITEM_DEFS.some(si => si.rx.test(col))) return 'special';
  if (AUTUMN_RX.test(col)) return 'autumn';   // contains 'NOT ACTIVE'
  return 'spring';
  // NOTE: never returns 'summer' — see Next Feature below
}
```

### `cleanName(col)` — strips Bromcom boilerplate to get display name
```javascript
function cleanName(col) {
  return col
    .replace(/^Club-/, '')                    // strips 'Club-' prefix
    .replace(/NOT ACTIVE\s*/i, '')            // strips autumn marker
    .replace(/^\*?2[3-6]\/2[4-7]\s*/, '')    // strips year e.g. '24/25 '
    .replace(/-?\s*Member\s*$/i, '')          // strips '-Member' suffix
    .trim().replace(/^[-\s]+|[-\s]+$/g, '');  // strips leading/trailing dashes
}
```

**Year regex coverage:** matches 23/24, 24/25, 25/26, 26/27. Will need updating
for 27/28 onward.

### Special items (tracked separately, not in term club counts)
```
Breakfast Club    — /Breakfast Club/i
After School Club — /After School Club/i
BF Residential    — /BF Residential/i
Schools Challenge — /Schools Challenge/i
```

---

## Naming convention term detection (implemented in v16)

The pilot tester's administrator has been instructed to rename all clubs in Bromcom
using the following suffix convention:

```
Football [Aut]     → Autumn
Chess Club [Spr]   → Spring
Dance [Sum]        → Summer
```

The tags are: `[Spr]`, `[Aut]`, `[Sum]` — exact case, square brackets, space before.
The four special items (Breakfast Club, After School Club, BF Residential, Schools
Challenge) are explicitly excluded from this convention.

### Code changes implemented in v16

**1. `colCategory()`** — add tag detection before the `autumn`/`spring` fallback:
```javascript
function colCategory(col) {
  if (!col.startsWith('Club-')) return 'demo';
  if (ALWAYS_IGNORE.some(rx => rx.test(col))) return 'ignore';
  if (SPECIAL_ITEM_DEFS.some(si => si.rx.test(col))) return 'special';
  // NEW: explicit term tags take priority
  const cleaned = cleanName(col);
  if (/\[Spr\]$/i.test(cleaned)) return 'spring';
  if (/\[Aut\]$/i.test(cleaned)) return 'autumn';
  if (/\[Sum\]$/i.test(cleaned)) return 'summer';
  // Fallback: Bromcom NOT ACTIVE marker
  if (AUTUMN_RX.test(col)) return 'autumn';
  return 'spring';
}
```

**2. `cleanName()`** — strip the tag from the display name:
```javascript
.replace(/\s*\[(Spr|Aut|Sum)\]$/i, '')   // add after existing replaces, before trim
```

**3. Hash recomputation** — required after any JS edit (see CSP section above).

---

## Key functions

| Function | Purpose |
|----------|---------|
| `parse(rows, filename)` | Parses SheetJS row objects into `DATA` state |
| `colCategory(col)` | Classifies a Bromcom column as spring/autumn/summer/special/ignore/demo |
| `cleanName(col)` | Strips Bromcom boilerplate to produce display club name |
| `effectiveClubs(term)` | Returns clubs for a term applying any move/duplicate overrides |
| `effectivePupilClubs(term)` | Returns map of pupil key → club list for a term |
| `updateApp()` | Re-renders all tabs after data load or club override change |
| `wireStaticHandlers()` | IIFE that wires all static HTML event listeners |
| `renderActionPlan()` | Renders Action Plan tab from current DATA + localStorage |
| `apSaveAll()` | Saves action plan textarea values to localStorage |
| `apExport()` | Opens branded print window for PDF export (A4/A3 landscape) |
| `openClubDetail(name, term)` | Navigates to club detail drill-down page |
| `toggleAnon()` | Toggles anonymisation mode globally |
| `esc(v)` | HTML-escapes all spreadsheet-derived values before DOM insertion |
| `displayName(p)` | Returns pupil name or anon token depending on anonMode |
| `setTerm(term)` | Switches active top-level term tab |
| `setSec(term, sec)` | Switches active section tab within a term panel |

---

## Security rules — never violate these

1. **All spreadsheet-derived values** inserted into HTML must pass through `esc()`
2. **No inline event handlers** (`onclick=`, `oninput=`, `onchange=`) anywhere —
   all wiring is done in `wireStaticHandlers()` or via `data-action` delegation
3. **No external URLs** anywhere in the file — no CDN, no fonts, no analytics
4. **No `fetch()`, `XMLHttpRequest`, or `WebSocket`** calls anywhere
5. **Club names injected into HTML attributes** must use `encodeURIComponent()`;
   retrieve with `decodeURIComponent()` in the JS handler — never interpolate
   raw or `esc()`-encoded names into JS string literals inside attributes
6. **The `printHTML` template literal** in `apExport()` contains `</style>`, `</head>`,
   `</body>`, `</html>` — these MUST remain wrapped as `${'</style>'}` etc. to prevent
   the HTML parser from terminating the `<script>` block early. Do not unwrap them.
7. **After any JS edit**, recompute both CSP hashes and update the `<meta>` tag
   (see CSP section). A mismatch causes silent script failure in the browser.
8. **The nonce `clublens2026` must never be reintroduced.** v16 uses hash-based CSP.
   A static nonce provides no security — if you see `nonce=` anywhere in the file,
   that is a regression.

---

## Open data protection risks (from v12 DPO report, April 2026 — pre-dates v16)

All are non-blocking for pilot use. None block distribution.

| # | Summary | Severity | Recommended fix |
|---|---------|----------|-----------------|
| 1 | Data visible on unattended device (inherent to browser tools) | Medium | User training; 30-min session timeout in future version |
| 2 | No automatic session timeout | Low | Implement `setTimeout` to clear `DATA` and return to landing screen |
| 3 | Action plan notes in shared localStorage | Low | Accept; named control in DPIA |
| 4 | No audit log | Low | Maintain access register outside tool |
| 5 | File type validation by extension only | Low | Check magic bytes (50 4B 03 04) before parsing |
| 6 | SheetJS bundled — cannot self-update | Accepted | Monitor SheetJS advisories; reissue if needed |

A formal DPIA is recommended before use beyond the current pilot.
DPO report: `ClubLens_DPO_Report_v12.pdf` (prepared by Paul Ottewell, April 2026).

---

## Bug history (important for debugging)

These bugs have all been hit. Do not reintroduce them.

| Bug | Cause | Fix |
|-----|-------|-----|
| All JS rendered as visible page text | `str_replace` consumed the `<script>` opening tag | Ensure `<script>` tag is present before the JS block |
| File upload silently did nothing | App `<script>` block was positioned before `#club-detail` div in HTML; `btn-back` was `null`, crashing `wireStaticHandlers` before file-input listener attached | Move `<script>` to bottom of `<body>`, after all HTML |
| File upload silently did nothing (2) | SheetJS loaded via external `src=` attribute; CSP `'self'` unreliable on `file://` origin | Inline SheetJS into HTML |
| Clubs tab sort wrong | `data-sort` on sub-category cells used raw counts; Year Groups had no `data-sort` | Sub-category `data-sort` uses percentage value; Year Groups uses member count |
| Move/Duplicate modal broken for names with apostrophes | `esc()` in JS string context: `&#39;` decoded back to `'` by browser | Use `encodeURIComponent` in data attributes, `decodeURIComponent` in handler |
| Print window breaks script execution | Bare `</style>` etc. in template literal visible to HTML parser | Wrap as `${'</style>'}` template expressions |
| `exportClubDetail` missing | `str_replace` anchor consumed the function declaration line | Function body was left as loose statements |
| Tab navigation completely broken | Tab `<div>` elements had no `data-action` attributes and no click listeners after CSP hardening removed inline `onclick` handlers | Added `term-tab`, `sec-tab`, and `pg-tab` delegated listeners in `wireStaticHandlers` |
| CSP blocked all scripts | Static nonce `clublens2026` replaced with hash-based CSP; hash mismatch after subsequent JS edit | Always recompute hashes after any JS change |

---

## Syntax checking

After any edit to a JS block, verify with:
```bash
python3 -c "
with open('docs/ClubLens_v17.html') as f:
    c = f.read()
first_close = c.index('</script>')
second_start = c.index('<script>', first_close)
js = c[second_start+8:c.rindex('</script>')]
open('/tmp/check.js','w').write(js)
"
node --check /tmp/check.js && echo "✓ OK"
```

Then recompute CSP hashes (see CSP section).

---

## Deployment

ClubLens is hosted at **clublens.vercel.app**, served from the `docs/` subfolder.
GitHub repo: **github.com/paulottewell/clublens**
Vercel Root Directory setting: `docs` (configured in Vercel dashboard → Settings → Build and Deployment).

**Standard release process:**
1. Edit `docs/ClubLens_vXX.html`
2. Copy to `docs/ClubLens_v(XX+1).html` for the new version
3. Update `docs/index.html`: both download `href` values, version badge, date, SHA-256 checksum, and add a release notes block
4. Compute SHA-256: `python3 -c "import hashlib; print(hashlib.sha256(open('docs/ClubLens_vXX.html','rb').read()).hexdigest())"`
5. Commit and push:
```bash
git add docs/ClubLens_vXX.html docs/index.html
git commit -m "vXX: description"
git push
```
Vercel deploys automatically within ~1 minute.

---

## Files in this project

| File | Description |
|------|-------------|
| `docs/ClubLens_v17.html` | The application — current version, self-contained |
| `docs/index.html` | Landing/download page served by Vercel |
| `docs/privacy.html` | Data protection information page |
| `docs/ClubLens-logo.png` | Logo asset |
| `ClubLens_DPO_Report_v12.pdf` | Data protection risk assessment for DPO (covers up to v12) |
| `CLAUDE.md` | This file |

The following files are **obsolete** and should be discarded:
`ClubLens_v10.html`, `ClubLens_v11.html`, `ClubLens_v12.html`, `ClubLens_v13.html`,
`ClubLens_v16.html` (root copy — belongs in `docs/` only), `xlsx.full.min.js`,
`README_SETUP.txt`, `ClubLens_DPO_Report.pdf` (v10 report), `ClubLens_DPO_Report_v11.pdf`.

---

## Licence
Paul Ottewell retains full intellectual property rights. St Matthew's C of E Primary
Academy holds a non-exclusive, non-transferable licence to use ClubLens v16 only,
for internal school purposes. The licence is withdrawable in writing and does not
extend to any future version.
