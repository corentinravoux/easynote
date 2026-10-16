import 'package:flutter/material.dart';

import '../store/paths.dart';
import 'theme.dart';

Future<String?> askText(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  String? hint,
}) {
  final ctrl = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: titleText(ctx.palette, size: 20)),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(action)),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: titleText(ctx.palette, size: 20)),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

/// Pick a destination folder. Returns '' for the top level, null on cancel.
Future<String?> pickFolder(
  BuildContext context, {
  required List<String> folders,
  required String current,
  String title = 'Move to folder',
  Set<String> exclude = const {},
}) {
  final options = ['', ...folders.where((f) => !exclude.any((x) => f == x || isUnder(f, x)))];
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final p = ctx.palette;
      return SimpleDialog(
        title: Text(title, style: titleText(p, size: 20)),
        children: [
          SizedBox(
            width: 360,
            height: (options.length * 44.0).clamp(88, 420),
            child: ListView(children: [
              for (final f in options)
                ListTile(
                  dense: true,
                  selected: f == current,
                  selectedColor: p.accent,
                  contentPadding: EdgeInsets.only(left: 20.0 + 18 * (f.isEmpty ? 0 : f.split('/').length - 1), right: 20),
                  leading: Icon(f.isEmpty ? Icons.inbox_outlined : Icons.folder_outlined, size: 20),
                  title: Text(f.isEmpty ? 'Notes (top level)' : basenameOf(f)),
                  onTap: () => Navigator.pop(ctx, f),
                ),
            ]),
          ),
        ],
      );
    },
  );
}
