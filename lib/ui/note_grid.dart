import 'dart:math';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../store/paths.dart';
import 'note_card.dart';
import 'theme.dart';

/// Subfolders as tabs, then notes as a masonry of cards.
class NoteGrid extends StatelessWidget {
  final AppController controller;
  final List<String> folders;
  final List<NoteSummary> notes;
  final void Function(String folder) onOpenFolder;
  final void Function(String path) onOpenNote;
  final void Function(String folder)? onFolderMenu;
  final bool showFolders;
  final Widget empty;

  const NoteGrid({
    super.key,
    required this.controller,
    required this.folders,
    required this.notes,
    required this.onOpenFolder,
    required this.onOpenNote,
    required this.empty,
    this.onFolderMenu,
    this.showFolders = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final pad = box.maxWidth < 600 ? 12.0 : 24.0;
      final width = box.maxWidth - 2 * pad;
      const gap = 14.0;
      final cols = max(width >= 340 ? 2 : 1, (width / 250).floor());
      final colWidth = (width - gap * (cols - 1)) / cols;

      final columns = List.generate(cols, (_) => <NoteSummary>[]);
      final heights = List.filled(cols, 0.0);
      for (final n in notes) {
        var k = 0;
        for (var i = 1; i < cols; i++) {
          if (heights[i] < heights[k] - 1) k = i;
        }
        columns[k].add(n);
        heights[k] += NoteCard.estimate(n) + gap;
      }

      return ListView(
        padding: EdgeInsets.fromLTRB(pad, 4, pad, 96),
        children: [
          if (folders.isNotEmpty) ...[
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final f in folders)
                FolderTab(
                  name: basenameOf(f),
                  count: controller.countUnder(f),
                  onTap: () => onOpenFolder(f),
                  onMenu: onFolderMenu == null ? null : () => onFolderMenu!(f),
                ),
            ]),
            const SizedBox(height: 20),
          ],
          if (notes.isEmpty && folders.isEmpty) empty,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < cols; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              SizedBox(
                width: colWidth,
                child: Column(children: [
                  for (final n in columns[i])
                    Padding(
                      padding: const EdgeInsets.only(bottom: gap),
                      child: NoteCard(
                        key: ValueKey(n.path),
                        note: n,
                        showFolder: showFolders,
                        onOpen: () => onOpenNote(n.path),
                      ),
                    ),
                ]),
              ),
            ],
          ]),
        ],
      );
    });
  }
}

/// A subfolder, drawn as the tab of a card-catalogue divider.
class FolderTab extends StatelessWidget {
  final String name;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onMenu;

  const FolderTab({super.key, required this.name, required this.count, required this.onTap, this.onMenu});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(3)),
        side: BorderSide(color: p.border),
      ),
      child: InkWell(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(3)),
        onTap: onTap,
        onLongPress: onMenu,
        onSecondaryTap: onMenu,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.folder_outlined, size: 18, color: p.muted),
            const SizedBox(width: 8),
            Text(name, style: TextStyle(fontSize: 14.5, color: p.ink, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('$count', style: TextStyle(fontSize: 13, color: p.muted)),
          ]),
        ),
      ),
    );
  }
}
