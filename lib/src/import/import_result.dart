/// A single file that failed to import.
class ImportError {
  final String filename;
  final String reason;
  final String? details;
  const ImportError({required this.filename, required this.reason, this.details});
  @override
  String toString() => '$filename: $reason';
}

/// Results of scanning a de1app folder before import.
class ScanResult {
  final int shotCount;
  final int profileCount;
  final bool hasDyeGrinders;
  final String sourcePath;
  final String? shotSource; // 'history_v2', 'history', or null
  const ScanResult({required this.shotCount, required this.profileCount, required this.hasDyeGrinders, required this.sourcePath, this.shotSource});
  int get totalItems => shotCount + profileCount;
  bool get isEmpty => totalItems == 0;
}

/// Results of a completed import operation.
class ImportResult {
  final int shotsImported;
  final int shotsSkipped;
  final int profilesImported;
  final int profilesSkipped;
  final int beansCreated;
  final int beansSkipped;
  final int grindersCreated;
  final int grindersSkipped;
  final List<ImportError> errors;
  const ImportResult({this.shotsImported = 0, this.shotsSkipped = 0, this.profilesImported = 0, this.profilesSkipped = 0, this.beansCreated = 0, this.beansSkipped = 0, this.grindersCreated = 0, this.grindersSkipped = 0, this.errors = const []});
  bool get hasErrors => errors.isNotEmpty;
  ImportResult operator +(ImportResult other) {
    return ImportResult(
      shotsImported: shotsImported + other.shotsImported,
      shotsSkipped: shotsSkipped + other.shotsSkipped,
      profilesImported: profilesImported + other.profilesImported,
      profilesSkipped: profilesSkipped + other.profilesSkipped,
      beansCreated: beansCreated + other.beansCreated,
      beansSkipped: beansSkipped + other.beansSkipped,
      grindersCreated: grindersCreated + other.grindersCreated,
      grindersSkipped: grindersSkipped + other.grindersSkipped,
      errors: [...errors, ...other.errors],
    );
  }
}

/// Progress callback for import operations.
class ImportProgress {
  final int current;
  final int total;
  final String phase; // 'shots', 'profiles', 'grinders'
  const ImportProgress({required this.current, required this.total, required this.phase});
  double get fraction => total > 0 ? current / total : 0;
}
