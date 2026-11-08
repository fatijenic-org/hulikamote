# Public benchmark material: what was looked at (scouting pass of 2026-11-03)

Searched: the Zenodo, Figshare and Hugging Face APIs (20 topic queries), plus web searches limited to Mendeley, Zenodo, Figshare and OSF for each
violation without public material. Every record kept was opened and its description, licence and file list read. Evaluation only: never train on these.
The earlier pass (2026-10-29) is in `public_sources.yaml`; this one added the sources marked NEW there.

## Taken (NEW, all open: no account, form or login)

| Source | Host | Size | Licence | Covers | Kind of data |
|---|---|---|---|---|---|
| Wrong-turn violations at roundabouts, Peshawar | Figshare 31572715 | 15.6 GB | CC BY 4.0 | illegal_turn, counterflow | roadside-camera frames cut from video |
| Motorcycle Safety Violation Dataset, heterogeneous traffic | Figshare 32310867 | 1.5 GB | CC BY 4.0 | no_helmet, overloading | surveillance/ANPR keyframes, plates blurred |
| Keke-Aware Vehicle Counting | Figshare 31968651 | 1.2 GB | CC BY 4.0 | tricycle_on_highway | roadside video frames with a tricycle class |
| FLUID signalized-intersection drone dataset | Figshare 29974954 | 17.7 GB | CC BY 4.0 | red_light, blocking_intersection | drone videos plus signal timings and trajectories |
| NANCY multi-perspective traffic video | Zenodo 18375218 | 10 GB | CC BY 4.0 | zone rules | vehicle, roadside and drone video of one area |
| AVDL, 50 road cameras (Latvia) | Zenodo 6274296 | 2.3 GB | CC BY 4.0 | zone rules, truck_ban | frames from 50 fixed cameras |
| Road Anomaly dataset (CCTV) | Zenodo 13832363 | 1.8 GB | CC BY 4.0 | zone rules, counterflow | CCTV anomalies |
| Vehicle Tracking Dataset (Hanoi motorbikes) | Zenodo 18195750 | 0.04 GB | CC BY 4.0 | zone rules | dense motorbike traffic |
| Road Lane Quality (smartphone dashcam) | Zenodo 18157438 | 6.6 GB | CC BY 4.0 | crossing_solid_line | dashcam video |
| Australian Roads Dashcam Driving | Hugging Face | 0.6 GB | CC BY-NC 4.0 | swerving | dashcam clips (crash, near crash, normal) |
| Small Crowd and Traffic Video Footages | Hugging Face | 0.1 GB | MIT | zone rules | short stock traffic clips |

Also still queued from before: the other RideSafe-400 zips, HELMET parts 5 and 6 and the clips not yet converted, METEOR (93 GB).

## Looked at and left out

| Source | Why not |
|---|---|
| UA-DETRAC | The official site could not be confirmed online; no verified download. |
| i-LIDS parked vehicle, Sussex traffic, ISLab parking | Licensed or on request, no free download found. |
| ATG-PVD (parking, drone) | Download link dead since 2026-10-29. |
| UK-Road-DashCam (Hugging Face) | 175 GB of unlabelled dashcam driving: too big for what it adds. |
| UniDataPro road-traffic-in-serbia | CC BY-NC-ND (no adaptations): re-encoding clips would break it. |
| thundarstrom Hugging Face repos | README only, or copies of RideSafe-400 / Indian helmet images. |
| open_video_helmet (Hugging Face) | A multi-camera rig recording of forests and a village, not traffic, despite the name. |
| BMD-45 (CCTV vehicle detection, India) | Stills from 3,600 cameras with no violation labels. |
| SIND (drone, red-light labels) | Availability not verified. |
| US DOT Intersection Safety Challenge | Full data needs a request form; the public sample is 20 staged runs. |
| MTID, Highway Traffic Videos (Kaggle) | Need a Kaggle login: never bypassed (see `--list`). |
| Roboflow sets | Need your own Roboflow key. |
| VLPI-RC (solid-line crossing), Bayonet-Drivers (phone, seatbelt) | Papers say a dataset exists; no public release found. |
| BrnoCompSpeed | Free but on request through a form. |
| DLR Highway Traffic | Trajectory tables, only a 16 MB video. |
| TU-DAT (road anomalies) | Download not found. |

## Still without any public video (film them: `CLIP_CHECKLIST.md`)

illegal_parking, double_parking, illegal_loading, pickup_passengers, riding_outside_vehicle, signal_light, no_seatbelt (road camera),
distracted_driving, missing_side_mirror, disregarding_signs, illegal_u_turn (the Malaysia challenge set needs a manual request).
The zone rules (restricted_lane, crossing_solid_line, disregarding_signs, double_parking, illegal_loading) can be run on any fixed-camera clip with the right vehicles:
the `__zone-rules` folders are that substrate, but nobody has labelled the events in them.
