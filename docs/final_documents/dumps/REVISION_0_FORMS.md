# REVISION LOG 0: FORMS AND RELATED TEXT

Read this file **before** `REVISION_LOG.md`. It uses the same format. Its entries are numbered F1 to F10 so they do not clash with entries 1 to 12.
Date written: 2026-11-19.

Document: `FINAL-PROPOSAL.pdf` (92 pages).
Printed page = PDF page - 9. Line numbers are the numbers in the left margin of the PDF.
Appendix C (the evaluation form) is a **picture** in the PDF. It has no line numbers. To change it, edit the printable form `docs/evaluation_form.html` and replace the pictures on printed pages 68 to 71 (PDF 77 to 80).

## Why this file exists

Many more violations are now built than the forms name. The forms must not grow with each new rule.
Plan: keep the form stable. Put the changing list of violations on a separate one-page sheet (F6). The form points to that sheet.
Do **not** change the 10 SUS statements. SUS is a standard test, and changed words break its meaning.
Do **not** add one form item for each violation. That makes too many items.
The extra violations (blocking intersection, sidewalk driving, illegal loading, truck ban, tricycle on a national highway, double parking, distracted driving) are "optional extras" (Revision Log entry 2). Show them if they work. Do not score them on the form.

| # | Where | What | Status |
|---|---|---|---|
| F1 | printed p. 69 (PDF 78), Form, Functionality item 2 | Other violations: use the sheet, not a fixed list | proposed |
| F2 | printed p. 68 (PDF 77), Form, rating scale | Add N/O (not observed) | proposed |
| F3 | printed p. 69 (PDF 78), Form, Reliability item 2 | Lighting: daytime | proposed |
| F4 | printed p. 54 (PDF 63), after line 952 | Rule: N/O is not counted | proposed |
| F5 | printed p. 55 (PDF 64), after line 962 | Table 4 and the form's rating words | proposed |
| F6 | after printed p. 71 (PDF 80), Appendix C | New page: violations shown at the session | proposed |
| F7 | printed p. 80 (PDF 89), lines 1152-1155 | Consent: purpose list | proposed |
| F8 | printed p. 80 (PDF 89), lines 1163-1164 | Consent: Violator Portal | proposed, only if the Portal is demonstrated |
| F9 | printed p. 81 (PDF 90), lines 1171-1173 | Consent: "offline" sentence | decide first (cloud GPU) |
| F10 | printed p. 6 (PDF 15), lines 264-265 | Scope: "tested offline" sentence | decide first (cloud GPU) |

---

## F1. Form: other violations
**Page:** printed 69 (PDF 78) | **Item:** F - Functionality, second item (picture, no line number)

**DELETE:**
> The system accurately detects other defined violations (e.g., missing side mirror, counterflow driving, illegal turning, passenger overloading).

**WRITE:**
> The system accurately detects the other violations shown in today's demonstration (see the list given to you).

*Metadata*
- Why: the evaluator rates only what he saw. The old text names "missing side mirror", which cannot work yet. The old text also needs an edit each time a rule is added.
- Needs: F6 (the list), F2 (N/O).
- Status: proposed

---

## F2. Form: N/O (not observed)
**Page:** printed 68 (PDF 77) | **Place:** under "Rate each item using the scale below:" (picture, no line number)

**KEEP:**
> 4 = Highly Acceptable    3 = Acceptable    2 = Needs Revision    1 = Not Acceptable

**ADD AFTER IT:**
> N/O = Not observed. Write N/O in the Rating box if you did not see it. It is not counted.

*Metadata*
- Why: the evaluator does not rate a violation he did not see. This avoids forced or guessed scores.
- Needs: F4 (the counting rule).
- Status: proposed

---

## F3. Form: lighting
**Page:** printed 69 (PDF 78) | **Item:** R - Reliability, second item (picture, no line number)

**DELETE:**
> The system performs consistently across the different simulated lighting and traffic conditions shown.

**WRITE:**
> The system performs consistently across the different daytime lighting and traffic conditions shown.

*Metadata*
- Why: the scope allows daylight only. Night is outside the scope (Revision Log entry 5). The old word "lighting" can be read as night.
- Status: proposed

---

## F4. Chapter 3: N/O is not counted
**Page:** printed 54 (PDF 63) | **Lines:** after line 952 (the word "average")

**KEEP:**
> Every single item and criterion-level scores will be using the Weighted Mean, which mainly accounts for how each of the individual ratings are distributed across all response categories instead of treating them as equal contribution in a flat average

**ADD AFTER IT:**
> Items marked N/O (not observed) by an evaluator are not counted in the weighted mean. The mean is computed from the items the evaluator rated.

*Metadata*
- Why: matches F2.
- Status: proposed

---

## F5. Chapter 3: Table 4 and the form's rating words
**Page:** printed 55 (PDF 64) | **Lines:** after line 962 (the words "targeted improvement.")

**KEEP:**
> ...serves as the primary guideline for our targeted improvement.

**ADD AFTER IT:**
> On the evaluation form, a rating of 4 is Highly Acceptable, 3 is Acceptable, 2 is Needs Revision, and 1 is Not Acceptable. Table 4 describes the mean of these ratings: a mean of 2.50 to 3.49 reads as Acceptable with Minor Revisions, and a mean of 1.50 to 2.49 reads as Acceptable with Major Revisions.

*Metadata*
- Why: the form and Table 4 use different words. This sentence joins them without changing the form, which may already be approved.
- Option (not recommended): change the form's words to the Table 4 words.
- Status: proposed

---

## F6. Appendix C: new page "Violations shown at the session"
**Page:** after printed 71 (PDF 80), before Appendix D

**WRITE (new page):**
> **Violations shown at this session**
> Date: __________  Evaluator: __________
>
> | Violation | Status | Shown today (Yes / No) |
> |---|---|---|
> | (one row for each violation) | Scored / Built, not scored / Experimental / Cannot work yet | |
>
> Status words:
> - Scored: tested on real footage with known answers; the result is in Chapter 4.
> - Built, not scored: the rule runs, but it has no real-footage result yet.
> - Experimental: the rule can give false flags; it is not a headline result.
> - Cannot work yet: the rule is listed, but it has no working detector or data (for example, missing side mirror).
>
> Rate on the form only the violations marked "Yes".

*Metadata*
- Why: the list changes. The form does not. Update the page, not the form.
- Fill in the rows from `VIOLATIONS_LIST.md` and the latest benchmark report before each session.
- Status: proposed

---

## F7. Consent: purpose list
**Page:** printed 80 (PDF 89) | **Lines:** 1152-1155

**DELETE:**
> (such as no helmet, no side mirror, overloading, counterflow, illegal turning, illegal parking, disregarding traffic signs, and no visible license plate)

**WRITE:**
> (the list is given at the session)

*Metadata*
- Why: the old list names "no side mirror", which cannot work yet, and it is out of date.
- Needs: F6 (the list handed out at the session).
- Status: proposed

---

## F8. Consent: Violator Portal
**Page:** printed 80 (PDF 89) | **Lines:** 1163-1164

**DELETE:**
> attend and observe a live demonstration of the HULI-KAMOTE Admin Dashboard

**WRITE:**
> attend and observe a live demonstration of the HULI-KAMOTE Admin Dashboard and the Violator Portal

*Metadata*
- Why: the consent names only the Admin Dashboard. The Final Proposal also has the Violator Portal.
- Apply only if the Portal is demonstrated at the session.
- Status: proposed

---

## F9. Consent: "offline" sentence (only if a cloud GPU is used)
**Page:** printed 81 (PDF 90) | **Lines:** 1171-1173

**DELETE:**
> the entire demonstration and evaluation will be conducted strictly within a controlled, offline simulation setting.

**WRITE:**
> the entire demonstration and evaluation will be conducted strictly within a controlled simulation setting, using demonstration footage only. The system runs offline on local computing resources. If a temporary cloud GPU is used for the live demonstration, it processes demonstration footage only, and it is deleted after the session.

*Metadata*
- Why: the old sentence would be false if the demo runs on a cloud GPU.
- Decide first: ask the adviser and the Research Ethics Office. If the cloud is not used, do not change this sentence.
- Status: decide first

---

## F10. Scope: "tested offline" sentence (only if a cloud GPU is used)
**Page:** printed 6 (PDF 15) | **Lines:** 264-265

**DELETE:**
> The system is tested offline using local computing resources.

**WRITE:**
> The system runs offline on local computing resources. For the live demonstration only, the researchers may use a temporary cloud GPU that processes demonstration footage only (no barangay footage and no real motorist data). The cloud machine is deleted after the session.

**Keep:** the next sentence ("It does not connect to any government enforcement database...").

*Metadata*
- Why: the old sentence would be false if the demo uses a cloud GPU. The cloud sees unblurred frames, so only demo footage may go up.
- Decide first: measure the demo laptop's fps first. Use the cloud only if it is still too slow.
- Also change: `SCOPE_AND_LIMITATIONS.md` and F9.
- Status: decide first
