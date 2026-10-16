/// What a device remembers between syncs.
class SyncState {
  /// Commit SHA of the branch head at the last successful sync.
  String? head;

  /// Tracked path → blob SHA as of [head]. A local file whose SHA differs
  /// from this has changed since the last sync.
  Map<String, String> base;

  /// Which repository and branch [head] and [base] refer to
  /// (`owner/repo@branch`). A different value means the user pointed the
  /// app at another repository.
  String? remote;

  /// Path → epoch milliseconds of the last open or edit on this device.
  /// Never synced.
  Map<String, int> recent;

  SyncState({this.head, this.remote, Map<String, String>? base, Map<String, int>? recent})
      : base = base ?? {},
        recent = recent ?? {};

  Map<String, dynamic> toJson() =>
      {'version': 1, 'remote': remote, 'head': head, 'base': base, 'recent': recent};

  factory SyncState.fromJson(Map<String, dynamic> j) => SyncState(
        head: j['head'] as String?,
        remote: j['remote'] as String?,
        base: Map<String, String>.from(j['base'] as Map? ?? {}),
        recent: {
          for (final e in (j['recent'] as Map? ?? {}).entries)
            e.key as String: (e.value as num).toInt(),
        },
      );
}
