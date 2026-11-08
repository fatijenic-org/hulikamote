import 'forensic_models.dart';
import 'holding_models.dart';
import 'plate_tools_models.dart';

/// What the review workspace needs from the backend. The HTTP implementation lives in
/// `data/forensic_api.dart`; tests use a fake, so review logic runs without a server.
abstract class ReviewGateway {
  /// Stores the reviewer's decision on every violation row of a ticket.
  Future<void> setStatus(List<String> dbIds, ReviewStatus status);

  /// merge | split | move-frames | not-duplicate. Returns the full, updated ticket list.
  Future<List<ForensicTicket>> ticketAction(
    String taskId,
    String action,
    Map<String, dynamic> body,
  );

  /// Saves the reviewer's plate on a ticket (the report and every violation row).
  /// [plate] empty = "no readable plate"; [revert] goes back to what the system read.
  /// Returns the full, updated ticket list.
  Future<List<ForensicTicket>> setPlate(
    String taskId,
    String ticketUid,
    String plate, {
    bool revert = false,
  });

  /// Looks for the plate again in the chosen photos (empty = all of them) and votes again.
  Future<RereadResult> rereadPlate(String taskId, String ticketUid, List<String> frames);

  /// Reads the text inside a box drawn by hand on [image] (a file under snapshots/evidence).
  /// [box] is [x0, y0, x1, y1] as fractions of the picture.
  Future<PlateBoxRead> readPlateBox(String taskId, String image, List<double> box);

  /// Sends a plate crop + the true text (empty = "not a plate") to the OCR training data.
  /// [imageName] is a file under snapshots/evidence.
  Future<void> sendPlateFeedback({
    required String imageName,
    required String label,
  });

  /// The state of an analysis that is still running, with the tickets released so far.
  Future<RunStatus> followStatus(String taskId);

  /// Takes the photos in [frames] out of a ticket and parks them in Holding (nothing is decided about them yet).
  Future<HoldingResult> setAside(String taskId, String ticketUid, List<String> frames);

  /// The photos waiting in Holding.
  Future<List<HoldingBatch>> loadHolding(String taskId);

  /// make-ticket | add-to-ticket | put-back | throw-away, for one batch in Holding.
  Future<HoldingResult> holdingAction(String taskId, String action, Map<String, dynamic> body);
}
