# Project risk table  (generated 2026-11-01)

Risk = (how many other files it touches) x (how little of it the tests run). Connected AND untested files are the ones to test first.

- Coverage % is line+branch coverage from the backend test run (engine/routers/store/etc.).
- `none` = the file is not in the coverage run (Dart files have no tests yet; some Python files are not imported by any test).

| # | File | Files it touches | Cross-file links | Test coverage | Risk |
|---|------|------------------|------------------|---------------|------|
| 1 | `hulikamote_dashboard/lib/features/benchmark/domain/benchmark_models.dart` | 14 | 16 | none | 14.0 |
| 2 | `hulikamote_dashboard/lib/features/demerit/data/demerit_api.dart` | 13 | 31 | none | 13.0 |
| 3 | `hulikamote_dashboard/lib/features/forensic/data/forensic_media.dart` | 12 | 12 | none | 12.0 |
| 4 | `hulikamote_dashboard/lib/features/forensic/domain/review_controller.dart` | 12 | 13 | none | 12.0 |
| 5 | `hulikamote_dashboard/lib/features/docs/domain/palette/doc_palette.dart` | 11 | 11 | none | 11.0 |
| 6 | `hulikamote_backend/emailer.py` | 10 | 10 | none | 10.0 |
| 7 | `hulikamote_backend/engine/deep_sort/deep_sort.py` | 9 | 28 | not measured (vendored library) | 9.0 |
| 8 | `hulikamote_dashboard/lib/features/forensic/data/harvest_labeling.dart` | 9 | 9 | none | 9.0 |
| 9 | `hulikamote_backend/engine/pipeline.py` | 14 | 40 | 41% | 8.2 |
| 10 | `hulikamote_dashboard/lib/features/docs/domain/models/doc_block.dart` | 8 | 19 | none | 8.0 |
| 11 | `hulikamote_dashboard/lib/features/forensic/domain/forensic_models.dart` | 8 | 11 | none | 8.0 |
| 12 | `hulikamote_dashboard/lib/features/forensic/data/forensic_api.dart` | 8 | 10 | none | 8.0 |
| 13 | `hulikamote_backend/demerit_points.py` | 7 | 19 | none | 7.0 |
| 14 | `hulikamote_dashboard/lib/features/forensic/presentation/screens/forensic_analyzer_screen.dart` | 7 | 8 | none | 7.0 |
| 15 | `hulikamote_backend/store.py` | 25 | 61 | 74% | 6.5 |
| 16 | `hulikamote_backend/cloud.py` | 6 | 7 | none | 6.0 |
| 17 | `hulikamote_backend/engine/deep_sort/sort/tracker.py` | 6 | 12 | not measured (vendored library) | 6.0 |
| 18 | `hulikamote_backend/inference/providers.py` | 6 | 19 | none | 6.0 |
| 19 | `hulikamote_dashboard/lib/features/forensic/domain/harvest_labeling_models.dart` | 6 | 9 | none | 6.0 |
| 20 | `hulikamote_backend/routers/violations.py` | 6 | 12 | 16% | 5.0 |
| 21 | `hulikamote_backend/evidence_files.py` | 5 | 5 | none | 5.0 |
| 22 | `hulikamote_dashboard/lib/features/forensic/presentation/widgets/wizard_steps.dart` | 5 | 5 | none | 5.0 |
| 23 | `hulikamote_dashboard/lib/features/forensic/domain/analysis_draft.dart` | 5 | 5 | none | 5.0 |
| 24 | `hulikamote_dashboard/lib/features/forensic/domain/analysis_runner.dart` | 5 | 5 | none | 5.0 |
| 25 | `hulikamote_backend/yolo_inference.py` | 11 | 36 | 59% | 4.5 |
| 26 | `hulikamote_backend/routers/forensic.py` | 10 | 52 | 56% | 4.4 |
| 27 | `hulikamote_backend/engine/deep_sort/sort/linear_assignment.py` | 4 | 4 | not measured (vendored library) | 4.0 |
| 28 | `hulikamote_dashboard/lib/features/forensic/presentation/widgets/plate_draw_dialog.dart` | 4 | 4 | none | 4.0 |
| 29 | `hulikamote_dashboard/lib/features/training/presentation/widgets/training_images_card.dart` | 4 | 6 | none | 4.0 |
| 30 | `hulikamote_dashboard/lib/features/forensic/data/harvest_source.dart` | 4 | 4 | none | 4.0 |
| 31 | `hulikamote_dashboard/lib/features/forensic/presentation/widgets/results_workspace.dart` | 4 | 4 | none | 4.0 |
| 32 | `hulikamote_dashboard/lib/features/forensic/presentation/widgets/analysis_wizard.dart` | 4 | 5 | none | 4.0 |
| 33 | `hulikamote_backend/engine/violations/base.py` | 20 | 20 | 81% | 3.7 |
| 34 | `hulikamote_backend/routers/stream.py` | 8 | 16 | 54% | 3.7 |
| 35 | `hulikamote_backend/engine/deep_sort/sort/iou_matching.py` | 3 | 3 | not measured (vendored library) | 3.0 |
| 36 | `hulikamote_dashboard/lib/features/forensic/presentation/widgets/harvest_labeler.dart` | 3 | 8 | none | 3.0 |
| 37 | `hulikamote_dashboard/lib/features/forensic/presentation/widgets/video_panel.dart` | 3 | 3 | none | 3.0 |
| 38 | `hulikamote_dashboard/lib/features/training/presentation/screens/training_studio_screen.dart` | 3 | 3 | none | 3.0 |
| 39 | `hulikamote_dashboard/lib/features/benchmark/data/benchmark_api.dart` | 3 | 3 | none | 3.0 |
| 40 | `hulikamote_dashboard/lib/features/wiki/domain/models/archived_resource.dart` | 3 | 3 | none | 3.0 |
