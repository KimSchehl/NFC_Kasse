/// One open (or done) pager order — one row per booking that contained at
/// least one `requires_pager` article, not one row per article. Scoped to
/// the operator who created it (see `PagerService`/`pagerListProvider`).
///
/// [createdAt]/[doneAt] are kept as raw strings rather than parsed
/// [DateTime]s — nothing in the UI currently does date arithmetic with them
/// (the list is already sorted server-side), so parsing would just add an
/// unused timezone question (SQLite's `datetime('now')` has no offset).
class PagerOrderModel {
  final int id;
  final String itemSummary;
  final int pagerNumber;
  final String status;
  final String createdAt;
  final String? doneAt;

  const PagerOrderModel({
    required this.id,
    required this.itemSummary,
    required this.pagerNumber,
    required this.status,
    required this.createdAt,
    this.doneAt,
  });

  factory PagerOrderModel.fromJson(Map<String, dynamic> j) => PagerOrderModel(
        id: j['id'] as int,
        itemSummary: j['item_summary'] as String,
        pagerNumber: j['pager_number'] as int,
        status: j['status'] as String,
        createdAt: j['created_at'] as String,
        doneAt: j['done_at'] as String?,
      );

  bool get isOpen => status == 'open';
}
