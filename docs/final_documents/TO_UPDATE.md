# TO UPDATE

New things to update, found after `REVISION_LOG.md` was written.
Date written: 2026-11-19.
Status words: **open** = not done. **decide** = needs a decision first. **check** = look first, then act.

## A. The paper (FINAL-PROPOSAL.pdf)

| # | Update | Where | Status |
|---|---|---|---|
| A1 | Apply the form and consent entries F1 to F10 | `dumps/REVISION_0_FORMS.md` | decide (adviser OK) |
| A2 | Write a revision entry: Grounding DINO is replaced by the Harvest tool (our detector proposes boxes, a human checks every picture) | `dumps/REVISION_LOG.md` (new entry), proposal text of "Automatic Tagging Process" | open |
| A3 | Make the "official 20 violations" the same in two files. The Revision Log counts pickup passengers and riding outside as mandatory. `SCOPE_AND_LIMITATIONS.md` ranks blocking intersection and illegal loading in the top 20 | `dumps/REVISION_LOG.md` entry 2 and `SCOPE_AND_LIMITATIONS.md` | decide |
| A4 | State which mandatory violations are not built: kuliglig passengers, overtaking on the right (or build them) | Chapter 4 and `SCOPE_AND_LIMITATIONS.md` | decide |
| A5 | Replace Table 3 with the new Table 3 and check the items marked "to confirm" | `dumps/TABLE3_UPDATE.md` | open |
| A6 | Fix the table of contents: the page numbers of Appendix A to E look wrong by about 3 | List of Appendices (printed p. viii) | check |
| A7 | Write the real image counts per dataset. The 3,000 target is a plan, not a result | Data section (Revision Log entry 3 note) | open |
| A8 | Write the number of evaluators and say what one evaluator can and cannot show | Chapter 3, evaluation | decide |
| A9 | Fill Chapter 4 and Chapter 5 from real results | Chapter 4, Chapter 5 | open |

## B. Project documents

| # | Update | File | Status |
|---|---|---|---|
| B1 | Add the cloud GPU sentence (only if the cloud is used) | `SCOPE_AND_LIMITATIONS.md` (limitations), F10 | decide |
| B2 | Fill every [CHECK] with the latest fact or number | `DEFEND.md` | open |
| B3 | Add the new checklists (evaluator preparation, redesign by FURPS and SUS) | `CHECKLISTS.md` | open |
| B4 | Check the violation list matches the system (25 violations in the benchmark list) | `VIOLATIONS_LIST.md`, `VIOLATIONS_AND_SOURCES.md` | check |
| B5 | Fill the questions | `CONSULTATION_QNA.md` (it is unfinished) | open |

## C. Forms and handouts

| # | Update | File | Status |
|---|---|---|---|
| C1 | Apply F1, F2, F3 and F6 to the printable form after approval | `docs/evaluation_form.html` | decide |
| C2 | Fill "Main Objective" and "Venue/Site of Testing" before printing | printed form | open |
| C3 | Make the one-page sheet: violations shown at the session (F6) and the limits | new file | open |
| C4 | Make the certificate of appreciation (the consent form promises it) | new file | open |
| C5 | Make the dashboard quick-start card | new file | open |
| C6 | Make the scoring sheet (weighted mean, Table 4 band, SUS score) | new file | open |

## D. Documentation site

| # | Update | Where | Status |
|---|---|---|---|
| D1 | Rebuild the site. Check if the Violations page still says 20 violations and 12 zone rules. The system has 25 | `tools/doc_site/`, `docs/documentation_site/` | check |
| D2 | Add cards for the 5 new violations (illegal loading, truck ban, tricycle on highway, sidewalk driving, double parking) | `tools/doc_site/violation_cards.py` | check |

## E. System work (pointers)

The full implementation prompts were given in chat. Names only:

- Features to check and finish: blur gaps (A1), notices (A2), demerit points (A3), Violator Portal and officer appeals (A4), restricted access (A5), live camera path (A6), evidence record and camera tag (A7), demo clip pack and rehearsal (A8).
- Polish: plate reading (P1), no helmet on rear and top-down views (P2), overloading rider count (P3), real benchmark numbers (P4), tracker default DeepSORT (P5), vehicle model check (P6), re-score models after data cleaning (P7), keep the test suite green (P8).
- Scope gaps: kuliglig passengers (C1), overtaking on the right (C2).

## F. Decisions to get

| # | Ask | Who | Status |
|---|---|---|---|
| F1 | Is one evaluator enough? | adviser | decide |
| F2 | May the session be online if the evaluator cannot come? | adviser | decide |
| F3 | Is the Harvest tool an accepted replacement for Grounding DINO? | adviser | decide |
| F4 | Which 20 violations are the official ones? | team and adviser | decide |
| F5 | Use a cloud GPU for the live demo? Measure fps on the demo laptop first. | team | decide |
| F6 | If the cloud is used: does the consent edit (F9) need an amendment? | Research Ethics Office | decide |
