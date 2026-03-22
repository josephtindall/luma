import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../services/page_service.dart';

enum _SaveStatus { saved, saving, unsaved }

class PageEditorScreen extends StatefulWidget {
  final String shortId;
  final PageService pageService;

  const PageEditorScreen({
    super.key,
    required this.shortId,
    required this.pageService,
  });

  @override
  State<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends State<PageEditorScreen> {
  PageDetail? _page;
  TextEditingController? _titleController;
  EditorState? _editorState;
  EditorScrollController? _scrollController;
  StreamSubscription<dynamic>? _transactionSub;
  Timer? _saveTimer;
  _SaveStatus _status = _SaveStatus.saved;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    try {
      final page = await widget.pageService.getPage(widget.shortId);
      if (!mounted) return;
      final editorState = _initEditorState(page.content);
      final scrollController = EditorScrollController(editorState: editorState);
      final titleController = TextEditingController(text: page.title);

      titleController.addListener(_scheduleAutoSave);
      _transactionSub = editorState.transactionStream.listen((_) => _scheduleAutoSave());

      setState(() {
        _page = page;
        _titleController = titleController;
        _editorState = editorState;
        _scrollController = scrollController;
        _status = _SaveStatus.saved;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  EditorState _initEditorState(Map<String, dynamic> content) {
    if (content.containsKey('document')) {
      return EditorState(document: Document.fromJson(content));
    }
    // Server default {"blocks":[]} or empty — treat as blank document.
    return EditorState.blank(withInitialText: false);
  }

  void _scheduleAutoSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
    if (_status != _SaveStatus.unsaved && mounted) {
      setState(() => _status = _SaveStatus.unsaved);
    }
  }

  Future<void> _save() async {
    final page = _page;
    final titleCtrl = _titleController;
    final editorState = _editorState;
    if (page == null || titleCtrl == null || editorState == null) return;

    final title = titleCtrl.text.trim().isEmpty ? 'Untitled' : titleCtrl.text.trim();
    final content = Map<String, dynamic>.from(editorState.document.toJson());

    if (mounted) setState(() => _status = _SaveStatus.saving);
    try {
      await widget.pageService.savePage(
        widget.shortId,
        title: title,
        content: content,
      );
      if (mounted) setState(() => _status = _SaveStatus.saved);
    } catch (_) {
      // Leave as unsaved so the timer re-attempts on the next keystroke.
      if (mounted) setState(() => _status = _SaveStatus.unsaved);
    }
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    await _save();
  }

  String _vaultSlug() {
    final vaultId = _page?.vaultId;
    if (vaultId == null) return '';
    try {
      return widget.pageService.vaults.firstWhere((v) => v.id == vaultId).slug;
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _transactionSub?.cancel();
    _titleController?.dispose();
    _scrollController?.dispose();
    _editorState?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            'Could not load page: $_loadError',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    if (_editorState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) => _saveNow(),
      child: Scaffold(
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveNow,
            const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveNow,
          },
          child: Focus(
            autofocus: false,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth.clamp(0.0, 720.0);
                      return Center(
                        child: SizedBox(
                          width: width,
                          height: constraints.maxHeight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 32, 16, 8),
                                child: TextField(
                                  controller: _titleController,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    hintText: 'Untitled',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  maxLines: null,
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Expanded(
                                child: AppFlowyEditor(
                                  editorState: _editorState!,
                                  editorScrollController: _scrollController!,
                                  editorStyle: EditorStyle.desktop(
                                    textStyleConfiguration:
                                        TextStyleConfiguration(
                                      text: GoogleFonts.inter(
                                        fontSize: 16,
                                        height: 24 / 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                  ),
                                  blockComponentBuilders:
                                      standardBlockComponentBuilderMap,
                                  characterShortcutEvents:
                                      standardCharacterShortcutEvents,
                                  commandShortcutEvents:
                                      standardCommandShortcutEvents,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(128),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: 'Back',
            onPressed: () async {
              await _saveNow();
              if (mounted) {
                final slug = _vaultSlug();
                context.go(slug.isNotEmpty ? '/vaults/$slug' : '/home');
              }
            },
          ),
          const Spacer(),
          _SaveIndicator(status: _status),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _SaveIndicator extends StatelessWidget {
  final _SaveStatus status;

  const _SaveIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return switch (status) {
      _SaveStatus.saved => Text('Saved', style: textStyle),
      _SaveStatus.saving => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Text('Saving\u2026', style: textStyle),
          ],
        ),
      _SaveStatus.unsaved => Text(
          '\u2022 Unsaved',
          style: textStyle?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
    };
  }
}
