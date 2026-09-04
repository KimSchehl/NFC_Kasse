import 'package:flutter/material.dart';

/// A left-bordered, left-padded indent block — the vertical "tree line"
/// used to nest child rows under a parent row. Purely presentational, no
/// business logic. Shared by `edit_user_dialog.dart`'s permission tree and
/// the article admin screen's category tree.
class TreeBranch extends StatelessWidget {
  final Color lineColor;
  final List<Widget> children;

  const TreeBranch({super.key, required this.lineColor, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: lineColor, width: 1.5)),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}
