import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../core/core_api.dart';
import '../core/core_controller.dart';
import '../core/models.dart';
import '../l10n/app_localizations.dart';
import '../platform.dart' show isPhone;
import 'connections_view.dart';
import 'format.dart';
import 'widgets.dart';

/// The core's live log: a level and text filter, auto-scroll,
/// clear, and copy; on a computer also the proxy's connections, in a
/// second tab. On a narrow screen (a phone) the tools take two rows: the
/// filter with the level, then auto-scroll with the actions.
class LogsPage extends StatefulWidget {
  const LogsPage({
    super.key,
    required this.core,
    this.settings,
    this.connections,
  });

  final CoreController core;

  /// Keeps the Connections tab's columns; without it they are not kept.
  final AppSettings? settings;

  /// The Connections tab is offered; by default on a computer.
  final bool? connections;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  /// Levels from least to most severe; the filter shows a level and above.
  static const _levels = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
  static const _max = 2000;

  final _entries = <LogEntry>[];
  final _scroll = ScrollController();
  Timer? _timer;
  int _after = 0;
  bool _reading = false;
  String _minLevel = 'DEBUG';
  String _text = '';
  bool _follow = true;

  /// The Connections tab is shown (computers only).
  bool _connections = false;

  /// logging.verbose in the core's settings; null until read.
  bool? _verbose;

  @override
  void initState() {
    super.initState();
    _after = widget.core.logsClearedAfter;
    _readVerbose();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (_reading) return;
    _reading = true;
    try {
      final more = await widget.core.call((api) => api.logs(_after));
      if (!mounted || more.isEmpty) return;
      // Lines logged before Clear but not yet read (the page reads once a
      // second, and a read may be under way) stay cleared.
      final cleared = widget.core.logsClearedAt;
      setState(() {
        _entries.addAll([
          for (final e in more)
            if (cleared == null || e.time == null || e.time!.isAfter(cleared))
              e,
        ]);
        _after = more.last.id;
        if (_entries.length > _max) {
          _entries.removeRange(0, _entries.length - _max);
        }
      });
      if (_follow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    } on CoreApiException {
      // The next tick tries again.
    } on CoreUnavailable {
      // The shell shows it.
    } finally {
      _reading = false;
    }
  }

  Future<void> _readVerbose() async {
    try {
      final config = await widget.core.settings();
      final logging = config['logging'];
      if (mounted) {
        setState(
          () => _verbose = logging is Map<String, Object?>
              ? logging['verbose'] == true
              : false,
        );
      }
    } on Exception {
      // The chip stays hidden.
    }
  }

  Future<void> _setVerbose(bool on) async {
    final ok = await runShowingErrors(
      context,
      () => widget.core.editSettings((config) {
        final logging = config['logging'];
        if (logging is Map<String, Object?>) {
          logging['verbose'] = on;
        } else {
          config['logging'] = <String, Object?>{'verbose': on};
        }
      }),
    );
    if (ok && mounted) setState(() => _verbose = on);
  }

  List<LogEntry> _visible() {
    final min = _levels.indexOf(_minLevel);
    final text = _text.trim().toLowerCase();
    return [
      for (final e in _entries)
        if (_levels.indexOf(e.level) >= min &&
            (text.isEmpty || e.message.toLowerCase().contains(text)))
          e,
    ];
  }

  /// A computer's tools: the levels and the filter, then the switches,
  /// with the actions as icons on the far side (their names in tooltips):
  /// the same layout as the Connections tab.
  Widget _wideTools(AppLocalizations l, List<LogEntry> visible) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final level in _levels)
                ButtonSegment(value: level, label: Text(_levelName(l, level))),
            ],
            selected: {_minLevel},
            onSelectionChanged: (v) => setState(() => _minLevel = v.first),
          ),
          SizedBox(width: 280, child: _filterField(l)),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _followSwitch(l),
                // Every destination in the log, for finding problems.
                if (_verbose case final verbose?)
                  LabeledSwitch(
                    label: l.verboseLogs,
                    value: verbose,
                    onChanged: _setVerbose,
                  ),
              ],
            ),
          ),
          _copyButton(l, visible),
          _clearButton(l),
        ],
      ),
    ],
  );

  /// A phone's tools, in two rows: the filter with the level beside it,
  /// then auto-scroll with the actions; the full log is in the menu.
  Widget _narrowTools(AppLocalizations l, List<LogEntry> visible) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: _filterField(l)),
          const SizedBox(width: 8),
          _levelMenu(l),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _followSwitch(l),
            ),
          ),
          _copyButton(l, visible),
          _clearButton(l),
          if (_verbose case final verbose?)
            PopupMenuButton<void>(
              itemBuilder: (context) => [
                checkMenuItem(
                  label: l.verboseLogs,
                  checked: verbose,
                  onTap: () => _setVerbose(!verbose),
                ),
              ],
            ),
        ],
      ),
    ],
  );

  static String _levelName(AppLocalizations l, String level) =>
      level == 'DEBUG' ? l.levelAll : level;

  Widget _filterField(AppLocalizations l) => TextField(
    decoration: InputDecoration(
      isDense: true,
      prefixIcon: const Icon(Icons.filter_list_rounded, size: 20),
      hintText: l.filter,
      border: const OutlineInputBorder(),
    ),
    onChanged: (v) => setState(() => _text = v),
  );

  /// The level as a small menu, as tall as the filter beside it.
  Widget _levelMenu(AppLocalizations l) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      initialValue: _minLevel,
      onSelected: (v) => setState(() => _minLevel = v),
      itemBuilder: (context) => [
        for (final level in _levels)
          PopupMenuItem(value: level, child: Text(_levelName(l, level))),
      ],
      child: Container(
        height: 48,
        padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_levelName(l, _minLevel)),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }

  Widget _followSwitch(AppLocalizations l) => LabeledSwitch(
    label: l.follow,
    value: _follow,
    onChanged: (v) => setState(() => _follow = v),
  );

  Widget _copyButton(AppLocalizations l, List<LogEntry> visible) => IconButton(
    tooltip: l.copyAll,
    icon: const Icon(Icons.copy_rounded),
    onPressed: visible.isEmpty
        ? null
        : () {
            Clipboard.setData(
              ClipboardData(text: visible.map(_line).join('\n')),
            );
            showError(context, l.logsCopied);
          },
  );

  Widget _clearButton(AppLocalizations l) => IconButton(
    tooltip: l.clear,
    icon: const Icon(Icons.delete_sweep_outlined),
    onPressed: () => setState(() {
      widget.core.logsClearedAfter = _after;
      widget.core.logsClearedAt = DateTime.now();
      _entries.clear();
    }),
  );

  static String _line(LogEntry e) {
    final t = e.time;
    final time = t == null
        ? ''
        : '${formatTime(t)}:${t.second.toString().padLeft(2, '0')}';
    return '$time ${e.level.padRight(5)} ${e.message}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final visible = _visible();
    return Padding(
      padding: pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageTitle(l.navLogs),
          const SizedBox(height: 16),
          if (widget.connections ?? !isPhone) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(l.tabLog),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.swap_vert_rounded, size: 18),
                    label: Text(l.tabConnections),
                  ),
                ],
                selected: {_connections},
                onSelectionChanged: (v) =>
                    setState(() => _connections = v.first),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_connections)
            Expanded(
              child: ConnectionsView(
                core: widget.core,
                settings: widget.settings,
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, box) => box.maxWidth < 600
                  ? _narrowTools(l, visible)
                  : _wideTools(l, visible),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: visible.isEmpty
                    ? Center(child: Text(l.noLogs))
                    : SelectionArea(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(12),
                          itemCount: visible.length,
                          itemBuilder: (context, i) =>
                              _LogLine(entry: visible[i]),
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final color = switch (e.level) {
      'ERROR' => StatusColors.bad,
      'WARN' => StatusColors.busy,
      'DEBUG' => theme.colorScheme.onSurfaceVariant,
      _ => theme.colorScheme.primary,
    };
    // Consolas on Windows; elsewhere the system's monospace font.
    const mono = TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: ['Menlo', 'DejaVu Sans Mono', 'monospace'],
      fontSize: 12.5,
      height: 1.45,
    );
    final t = e.time;
    // Log lines are English and stay left to right in every language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text.rich(
        TextSpan(
          style: mono.copyWith(color: theme.colorScheme.onSurface),
          children: [
            if (t != null)
              TextSpan(
                text:
                    '${formatTime(t)}:${t.second.toString().padLeft(2, '0')}  ',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            TextSpan(
              text: '${e.level.padRight(5)}  ',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            TextSpan(text: e.message),
          ],
        ),
      ),
    );
  }
}
