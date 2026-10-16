import 'package:flutter/material.dart';

import '../app/controller.dart';
import 'theme.dart';

/// A note as a ruled index card: title, crimson rule, items on blue lines.
class NoteCard extends StatefulWidget {
  final NoteSummary note;
  final VoidCallback onOpen;
  final bool showFolder;

  const NoteCard({super.key, required this.note, required this.onOpen, this.showFolder = false});

  /// Height estimate used to balance the masonry columns.
  static double estimate(NoteSummary n) =>
      64 + ruleHeight * n.preview.length + (n.todoCount > 0 || n.conflict ? 26 : 0);

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = widget.note;
    final body = noteText(p, size: 14.5);
    return Semantics(
      button: true,
      label: n.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: p.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
            side: BorderSide(color: _hover ? p.ink.withValues(alpha: 0.45) : p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onOpen,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (widget.showFolder && n.folder.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(n.folder, style: TextStyle(fontSize: 12, color: p.muted)),
                    ),
                  Text(n.title, style: titleText(p, size: 17), maxLines: 3, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Container(height: 1.5, color: p.accent.withValues(alpha: p.flat ? 1 : 0.75)),
              if (n.preview.isNotEmpty)
                CustomPaint(
                  painter: RuledPaper(p.rule),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final line in n.preview)
                        SizedBox(
                          height: ruleHeight,
                          child: Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: line.trimLeft().startsWith('☑')
                                ? body.copyWith(color: p.muted, decoration: TextDecoration.lineThrough, decorationColor: p.muted)
                                : body,
                          ),
                        ),
                    ]),
                  ),
                ),
              if (n.todoCount > 0 || n.conflict)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(children: [
                    if (n.conflict)
                      Text('Conflict copy', style: TextStyle(fontSize: 12, color: p.accent, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (n.todoCount > 0)
                      Text('${n.doneCount} of ${n.todoCount} done', style: TextStyle(fontSize: 12, color: p.muted)),
                  ]),
                )
              else
                const SizedBox(height: 6),
            ]),
          ),
        ),
      ),
    );
  }
}
