# Time of the video and ban hours (truck ban)

A truck ban holds only at certain hours. So the system must know **when the footage was recorded**, and it must say where that time came from. The code is `engine/video_clock.py`.

## Where the time comes from (best first)

| # | Source | How | Weak spot |
|---|---|---|---|
| 1 | **Typed by the operator** ("video started 7:40 AM") | Settings step, "Video start time". Also the way to **simulate** an hour for a test or a demo | A person can type a wrong time |
| 2 | **Clock printed in the picture** (OSD) | OCR of the four corners at up to 8 moments of the video. It counts only when **two readings agree with the time that really passed between them** (a misread digit cannot agree twice) | Needs a visible clock; a camera clock can drift |
| 3 | **The video's own information** | `creation_time` tag (ffprobe). Taken as UTC, shown as Philippine time (UTC+8) | Copied or re-saved files may lose it or show the copy time; some cameras write local time where UTC belongs |
| 4 | **The file name** | `20261105_074000.mp4`, `2026-11-05 07-40-00` ... | Only if the name carries a time |
| 5 | **Estimate from the picture** | Brightness: day, twilight or night | **Not a time.** It cannot tell 8 AM from 10 AM |

If the screen clock and the file tag disagree by more than 5 minutes, the screen clock is used and the note says so.

## What happens when no real time is found

The truck is still flagged, but the ticket says **"Time not confirmed"** and carries a review flag, so a person checks the time before confirming. Nothing is ticketed silently on a guess.

## Ban hours

Set in the truck-ban editor (Zones step): **Only ban at certain hours**, up to 3 windows ("From 6:00 AM to 9:00 AM"). No hours set = the ban holds all day (as before). A window can pass midnight. Each frame is judged by the time of that frame: a truck inside the window is flagged, a truck outside is not.

The wizard has a button "Use example hours (6-9 AM, 4-7 PM)". It is **only an example**. The real hours of Zamboanga City must come from its ordinance (the Revised Traffic Code, City Ordinance No. 248, was named in one source and not confirmed): ask the City Traffic or City Legal office.

## Where the time shows

- **Settings step** ("Time of the video" card): the time found, where it came from, and whether the video starts inside the ban hours.
- **Every ticket** of a run that looked for the time: "7:42 AM (read from the clock in the picture)" in the open ticket and the queue.
- **Live Monitor**: uses this computer's clock. Typing a start time in the wizard and pressing "Use for Live Monitor" pretends that time for the live demo (`clock_start` in `camera_config.json`).

## How professionals do it (for the thesis)

- The recorder stamps time from a **synced clock (NTP or GPS)** at the moment of capture. It is not worked out afterwards.
- The **source of the time is recorded**, and the camera clock is **checked for drift** against real time.
- When the time is unknown, there is **no automatic ticket**: a person decides.

This system follows the same rules where the footage allows it. For old footage with no stamped time it falls back down the ladder above and marks the result honestly.

## Limits

- A clock printed in a small or low-contrast corner may not be read; then the next source is tried.
- The search for a clock takes about 15-20 s on this laptop when the video has none (8 pictures, 4 corners each); it takes 1-3 s when the clock is there.
- Checked on three real clips of the team with a painted clock (read on all three) and on clips with no clock (none invented). Not yet checked on footage from a real Zamboanga camera.
