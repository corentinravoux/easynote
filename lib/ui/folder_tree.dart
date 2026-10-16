import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../store/paths.dart';
import 'theme.dart';

/// Desktop sidebar: Recent, the top level, and the folder tree.
class FolderTree extends StatefulWidget {
  final AppController controller;
  final void Function(String folder) onSelect;
  final void Function(String folder) onFolderMenu;
  final VoidCallback onNewFolder;
  final Widget footer;

  const FolderTree({
    super.key,
    required this.controller,
    required this.onSelect,
    required this.onFolderMenu,
    required this.onNewFolder,
    required this.footer,
  });

  @override
  State<FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends State<FolderTree> {
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = widget.controller;
    final selected = c.query.isEmpty ? c.folder : null;

    // Keep the selected folder's ancestors open.
    for (var f = selected ?? ''; f.isNotEmpty; f = parentOf(f)) {
      if (f != selected) _collapsed.remove(f);
    }

    final rows = <Widget>[];
    void addChildren(String parent, int depth) {
      for (final f in c.childFolders(parent)) {
        final hasKids = c.childFolders(f).isNotEmpty;
        final open = !_collapsed.contains(f);
        rows.add(_TreeRow(
          label: basenameOf(f),
          icon: Icons.folder_outlined,
          depth: depth,
          selected: selected == f,
          expanded: hasKids ? open : null,
          onToggle: () => setState(() => open ? _collapsed.add(f) : _collapsed.remove(f)),
          onTap: () => widget.onSelect(f),
          onMenu: () => widget.onFolderMenu(f),
          count: c.countUnder(f),
        ));
        if (hasKids && open) addChildren(f, depth + 1);
      }
    }

    addChildren('', 0);

    return Container(
      color: p.desk,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Text('easynote', style: titleText(p, size: 22)),
        ),
        _TreeRow(
          label: 'Recent',
          icon: Icons.history,
          depth: 0,
          selected: selected == recentFolder,
          onTap: () => widget.onSelect(recentFolder),
        ),
        _TreeRow(
          label: 'Notes',
          icon: Icons.inbox_outlined,
          depth: 0,
          selected: selected == '',
          onTap: () => widget.onSelect(''),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
          child: Row(children: [
            Text('Folders', style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              tooltip: 'New folder',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: p.muted,
              onPressed: widget.onNewFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text('No folders yet.', style: TextStyle(fontSize: 13, color: p.muted)),
                )
              : ListView(padding: const EdgeInsets.only(bottom: 12), children: rows),
        ),
        Divider(color: p.border),
        widget.footer,
      ]),
    );
  }
}

class _TreeRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int depth;
  final bool selected;
  final bool? expanded;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onMenu;
  final int? count;

  const _TreeRow({
    required this.label,
    required this.icon,
    required this.depth,
    required this.selected,
    required this.onTap,
    this.expanded,
    this.onToggle,
    this.onMenu,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? p.highlight : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: onTap,
          onSecondaryTap: onMenu,
          onLongPress: onMenu,
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: selected ? p.accent : Colors.transparent, width: 3)),
            ),
            padding: EdgeInsets.only(left: 6.0 + 16 * depth, right: 8),
            child: Row(children: [
              SizedBox(
                width: 22,
                child: expanded == null
                    ? null
                    : InkResponse(
                        radius: 14,
                        onTap: onToggle,
                        child: Icon(expanded! ? Icons.expand_more : Icons.chevron_right, size: 18, color: p.muted),
                      ),
              ),
              Icon(icon, size: 18, color: selected ? p.ink : p.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: p.ink,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    )),
              ),
              if (count != null && count! > 0)
                Text('$count', style: TextStyle(fontSize: 12.5, color: p.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
