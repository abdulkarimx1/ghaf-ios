# How a Ghaf release is run (binding — written after 1.30, where ~70% of owner comments failed approval)

## Why 1.30 failed (do not repeat)
1. Comments were turned into themed briefs; individual comments got lost inside them.
2. "Done" meant code + tests passed, not "the owner's screen now looks right".
3. Briefs limited files too narrowly → Codex stopped, extra rounds, lost hours.
4. Redesign requests ("follow the inspo") were treated as small edits (e.g. a 1.5 pt card bob called "animation").
5. Owner questions inside comments were never answered.
6. Server-dependent fixes were reported as fixed while the server was not deployed.

## The process
1. **Intake (Claude).** Owner writes `HANDOFF-<v>/COMMENTS.md` from `design/COMMENTS-TEMPLATE.md`. Claude copies every item, word for word, into `HANDOFF-<v>/ACCEPTANCE.md` — one row per item: # · screen · owner words · type (fix/redesign/new/question) · inspo · status · proof. Nothing is merged, split away, or dropped. Questions are answered in writing first.
2. **Design first (Claude), for every redesign item.** Study the inspo (frames + measurements in `design/inspo/<screen>/NOTES.md`), use the design skills (apple-design, swiftui-animation, ui-animation, impeccable/frontend-design for direction), and produce a visual spec or prototype for the owner. Owner approves before any code.
3. **Briefs (Claude → Codex).** One brief per screen, listing the exact acceptance rows it owns. Scope = the screen and anything it needs; never block on a file list. Every brief links `design/DESIGN.md`.
4. **Proof per row (Codex).** For each row: uncropped screenshots light/dark × EN/AR with the owner backup, plus a screen recording for anything that moves. A row without proof is not done.
5. **Review per row (Claude).** Claude opens every proof and compares with the owner's words and inspo. Status ∈ {pass, fail, blocked-by-server, blocked-by-owner}. Never "done" from a report or a test.
6. **Owner report.** The ACCEPTANCE table is what the owner sees: every item, its proof link, and anything not passed — said plainly.
7. **Server-dependent items** stay "blocked-by-server" until the Worker is deployed and tested on the owner's phone.
8. **Consistency.** Any change to fonts, colours, motion values or locked identity goes through `design/DESIGN.md` + `design/CHANGELOG.md` with owner approval.
