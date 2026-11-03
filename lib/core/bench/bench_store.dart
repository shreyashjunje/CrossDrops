import '../media/save_target.dart';
import '../protocol/models.dart';
import '../server/file_store.dart';
import 'bench.dart';

/// Benchmark builds wrap the real store: files named by [benchFileName]
/// are received and verified like any other, then deleted instead of saved
/// (D-058). Everything else goes to [inner].
class BenchDiscardingStore implements ReceivedFileStore {
  BenchDiscardingStore(this.inner);

  final ReceivedFileStore inner;

  /// The `finalLocation` stored for a discarded file.
  static const discarded = 'bench:discarded';

  @override
  String initialLocation(String sessionDir, FileOffer offer) =>
      inner.initialLocation(sessionDir, offer);

  @override
  Future<(PartFile, String)> open(
    String location, {
    required String sessionDir,
    required FileOffer offer,
  }) => inner.open(location, sessionDir: sessionDir, offer: offer);

  @override
  Future<int> length(String location) => inner.length(location);

  @override
  Future<int> restore(String location, int checkpoint) =>
      inner.restore(location, checkpoint);

  @override
  Future<void> delete(String location) => inner.delete(location);

  @override
  Future<SaveResult> save(String location, FileOffer offer) async {
    if (!isBenchFileName(offer.name)) return inner.save(location, offer);
    await inner.delete(location);
    return const SaveResult(
      location: discarded,
      collection: SaveCollection.files,
    );
  }
}
