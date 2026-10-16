import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../format/note.dart';
import '../theme.dart';

/// Keys the editor handles itself instead of the text field.
class RowKeys {
  final VoidCallback onEnter;
  final VoidCallback onBackspaceAtStart;
  final VoidCallback onIndent;
  final VoidCallback onOutdent;
  final VoidCallback onToggleCheckbox;
  final VoidCallback onUp;
  final VoidCallback onDown;

  const RowKeys({
    required this.onEnter,
    required this.onBackspaceAtStart,
    required this.onIndent,
    required this.onOutdent,
    required this.onToggleCheckbox,
    required this.onUp,
    required this.onDown,
  });
}

/// One item of the editor: indent, marker (bullet or checkbox), text.
class ItemRow extends StatelessWidget {
  final NoteLine line;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onChecked;
  final RowKeys keys;

  const ItemRow({
    super.key,
    required this.line,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onChecked,
    required this.keys,
  });

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final sel = controller.selection;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (shift) return KeyEventResult.ignored;
      ctrl ? keys.onToggleCheckbox() : keys.onEnter();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab) {
      shift ? keys.onOutdent() : keys.onIndent();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace && sel.isCollapsed && sel.baseOffset == 0) {
      keys.onBackspaceAtStart();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && !shift && _onFirstLine()) {
      keys.onUp();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown && !shift && _onLastLine()) {
      keys.onDown();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Up leaves the item from its start, Down from its end, so arrows still
  // move within a long wrapped item.
  bool _onFirstLine() => controller.selection.baseOffset <= 0;
  bool _onLastLine() => controller.selection.baseOffset >= controller.text.length;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final done = line.kind == ItemKind.done;
    final style = noteText(p).copyWith(
      color: done ? p.muted : p.ink,
      decoration: done ? TextDecoration.lineThrough : null,
      decorationColor: p.muted,
    );
    return Padding(
      padding: EdgeInsets.only(left: 24.0 * line.indent),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 30,
          height: ruleHeight,
          child: switch (line.kind) {
            ItemKind.bullet => Center(
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
                ),
              ),
            ItemKind.todo || ItemKind.done => Center(
                child: InkBox(checked: done, onChanged: onChecked),
              ),
            ItemKind.plain => null,
          },
        ),
        Expanded(
          child: Focus(
            onKeyEvent: _onKey,
            skipTraversal: true,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: style,
              maxLines: null,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              onEditingComplete: keys.onEnter,
              onChanged: onChanged,
              decoration: bareField(),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A square checkbox drawn in ink, sized for the ruled line.
class InkBox extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onChanged;
  const InkBox({super.key, required this.checked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      checked: checked,
      button: true,
      child: InkResponse(
        radius: 16,
        onTap: () => onChanged(!checked),
        child: Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: checked ? p.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(2.5),
            border: Border.all(color: p.ink, width: 1.6),
          ),
          child: checked ? Icon(Icons.check, size: 13, color: p.card) : null,
        ),
      ),
    );
  }
}
