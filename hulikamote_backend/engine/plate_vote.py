"""
plate_vote.py - how a ticket's plate reads are graded and the best one picked. Pure logic, no models, no files.

A plate crop is read twice: as it was seen (raw) and enhanced (the GAN, or the super resolution). So a crop result carries
`reads` = [{"source": "raw" | "enhanced", "raw": text as the OCR gave it, "cleaned": text after the plate format fix, "confidence": 0..1}].
A crop result without `reads` (an older report) counts as one enhanced read.

Every read is a vote for its text. A text's points are the grading the forensic pass has always used:
  votes + the best confidence that text had + 20 when it has the length of the plate format.
Two reads of the same text (raw and enhanced, or two crops) therefore lift each other. `tier` says it in a word for the screen:
  strong = the right length, 3 votes or more and a confident read
  fair   = the right length and some support (2 votes, a confident read, or raw and enhanced agree)
  weak   = anything else
"""
UNREAD = ("unidentified", "no_plate_found", "", "OCR_NOT_INSTALLED")
LENGTH_BONUS = 20.0


def bonus(text: str, plate_format: str) -> float:
    """+20 for a text with the length of the plate format (the same rule as the forensic pass)."""
    if plate_format == "uk_standard" and len(text) == 7:
        return LENGTH_BONUS
    if plate_format == "ph_standard" and len(text) in (6, 7):
        return LENGTH_BONUS
    return 0.0


def crop_reads(crop: dict) -> list[dict]:
    """The reads of one crop result (an older one, with only `cleaned` and `confidence`, is one enhanced read)."""
    reads = crop.get("reads")
    if reads:
        return [r for r in reads if isinstance(r, dict)]
    return [{"source": "enhanced", "raw": crop.get("raw", ""), "cleaned": crop.get("cleaned", ""), "confidence": crop.get("confidence") or 0.0}]


def best_read(reads: list[dict], plate_format: str) -> dict:
    """The read that heads a crop: a readable one before an unreadable one, then the higher confidence (+ the length bonus);
    the enhanced read wins a tie."""
    if not reads:
        return {"source": "enhanced", "raw": "unidentified", "cleaned": "unidentified", "confidence": 0.0}

    def key(r: dict):
        text = r.get("cleaned", "")
        return (text not in UNREAD, (r.get("confidence") or 0.0) + (1.0 if bonus(text, plate_format) else 0.0))

    return max(sorted(reads, key=lambda r: r.get("source") != "enhanced"), key=key)


def tier(entry: dict, plate_format: str) -> str:
    right_length = bonus(entry["text"], plate_format) > 0 or plate_format not in ("ph_standard", "uk_standard")
    agree = len(entry["sources"]) >= 2
    if right_length and entry["votes"] >= 3 and entry["confidence"] >= 0.6:
        return "strong"
    if right_length and (entry["votes"] >= 2 or entry["confidence"] >= 0.5 or agree):
        return "fair"
    return "weak"


def candidates(crop_results: list[dict], plate_format: str) -> list[dict]:
    """Every distinct text that was read, best first: {"text", "raw", "votes", "confidence", "points", "tier", "sources", "crops"}."""
    found: dict[str, dict] = {}
    for crop in crop_results:
        for read in crop_reads(crop):
            text = read.get("cleaned", "")
            if text in UNREAD:
                continue
            conf = read.get("confidence") or 0.0
            entry = found.setdefault(text, {"text": text, "raw": read.get("raw", text), "votes": 0, "confidence": 0.0, "sources": [], "crops": []})
            entry["votes"] += 1
            if conf >= entry["confidence"]:
                entry["confidence"], entry["raw"] = conf, read.get("raw", text)
            if read.get("source") and read["source"] not in entry["sources"]:
                entry["sources"].append(read["source"])
            if crop.get("image_raw") and crop["image_raw"] not in entry["crops"]:
                entry["crops"].append(crop["image_raw"])
    for entry in found.values():
        entry["points"] = round(entry["votes"] + entry["confidence"] + bonus(entry["text"], plate_format), 3)
        entry["confidence"] = round(entry["confidence"], 3)
        entry["tier"] = tier(entry, plate_format)
    return sorted(found.values(), key=lambda e: (-e["points"], e["text"]))
