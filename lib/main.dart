import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const NootiApp());

/// 与安卓原生端（MainActivity.kt）约定好的通道名与指令名，两端必须一致
const MethodChannel _ch = MethodChannel('nooti/listener');

/// 校园/工作场景高频重点词，一键添加
const List<String> _presetKeywords = [
  '有人@我', '@全体成员', '老师', '班主任', '班长', '截止', '收到请回复',
  '交作业', '提交', '考试', '签到', '紧急', '开会', '成绩', '通知',
];

/// 把常见的系统包名翻译成人话（没收录的就原样显示）
String _appName(String pkg) {
  const Map<String, String> names = {
    'com.tencent.mm': '微信',
    'com.tencent.mobileqq': 'QQ',
    'com.alibaba.android.rimet': '钉钉',
    'com.tencent.wework': '企业微信',
    'com.tencent.tim': 'TIM',
    'com.google.android.gm': 'Gmail',
    'com.netease.mail': '网易邮箱',
  };
  return names[pkg] ?? pkg;
}

class NootiApp extends StatelessWidget {
  const NootiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nooti 监听',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3D7FE0), useMaterial3: true),
      home: const MonitorHome(),
    );
  }
}

class MonitorHome extends StatefulWidget {
  const MonitorHome({super.key});
  @override
  State<MonitorHome> createState() => _MonitorHomeState();
}

class _MonitorHomeState extends State<MonitorHome> {
  bool _enabled = false;      // 通知使用权
  bool _canNotify = false;    // Nooti 发提醒的权限
  bool _canFull = true;       // 全屏弹窗权限（老系统默认有）
  bool _filterOn = false;     // 过滤总开关
  List<String> _groups = [];   // 安静群组
  List<String> _keywords = []; // 重点提醒词
  List<Map<String, dynamic>> _discovered = []; // 自动发现的群/联系人
  List<Map<String, dynamic>> _items = [];
  Timer? _timer;
  final _groupCtrl = TextEditingController();
  final _kwCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRules();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _groupCtrl.dispose();
    _kwCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    try {
      final s = await _ch.invokeMethod<String>('getRules') ?? '';
      if (s.isNotEmpty) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _filterOn = m['enabled'] == true;
          _groups = (m['groups'] as List? ?? []).map((e) => '$e').toList();
          _keywords = (m['keywords'] as List? ?? []).map((e) => '$e').toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveRules() async {
    try {
      await _ch.invokeMethod('setRules', {
        'json': jsonEncode({
          'enabled': _filterOn,
          'groups': _groups,
          'keywords': _keywords,
        })
      });
    } catch (_) {}
  }

  void _addGroupName(String v) {
    v = v.trim();
    if (v.isEmpty || _groups.contains(v)) return;
    setState(() => _groups.add(v));
    _saveRules();
  }

  void _addKeyword(String v) {
    v = v.trim();
    if (v.isEmpty || _keywords.contains(v)) return;
    setState(() => _keywords.add(v));
    _saveRules();
  }

  Future<void> _refresh() async {
    bool enabled = false;
    bool canNotify = false;
    bool canFull = true;
    List<Map<String, dynamic>> items = const [];
    List<Map<String, dynamic>> discovered = const [];
    try {
      enabled = await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {}
    try {
      canNotify = await _ch.invokeMethod<bool>('canNotify') ?? false;
    } catch (_) {}
    try {
      canFull = await _ch.invokeMethod<bool>('canFullScreen') ?? true;
    } catch (_) {}
    try {
      final list = await _ch.invokeMethod<List<dynamic>>('getCaptured');
      if (list != null) {
        items = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    try {
      final s = await _ch.invokeMethod<String>('getDiscovered') ?? '[]';
      final l = jsonDecode(s) as List;
      discovered = l
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
          .reversed
          .toList();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _canNotify = canNotify;
      _canFull = canFull;
      _items = items;
      _discovered = discovered;
    });
  }

  Future<void> _openSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }

  Future<void> _requestNotify() async {
    try {
      await _ch.invokeMethod('requestNotifyPermission');
    } catch (_) {}
  }

  Future<void> _openFullScreen() async {
    try {
      await _ch.invokeMethod('openFullScreenSettings');
    } catch (_) {}
  }

  Future<void> _clear() async {
    try {
      await _ch.invokeMethod('clear');
    } catch (_) {}
    if (mounted) setState(() => _items = []);
  }

  String _fmtTime(dynamic v) {
    final int ms = v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10, color: fg)),
    );
  }

  Widget _card({required Widget child, EdgeInsets? margin}) {
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E9F4)),
      ),
      child: child,
    );
  }

  Widget _inputRow(TextEditingController ctrl, String hint, VoidCallback onAdd) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onSubmitted: (_) => onAdd(),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton(onPressed: onAdd, child: const Text('添加')),
    ]);
  }

  Widget _chips(List<String> values, void Function(int) onDel) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < values.length; i++)
            Chip(
              label: Text(values[i], style: const TextStyle(fontSize: 12)),
              onDeleted: () => onDel(i),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 还没加进安静名单的「发现的群」放前面
    final newFound = _discovered.where((d) {
      final t = '${d['t'] ?? ''}';
      return !_groups.any((g) => t.contains(g));
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Nooti 监听')),
      body: ListView(children: [
        // 监听权限状态卡
        _card(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Icon(
              _enabled ? Icons.check_circle : Icons.notifications_off,
              color: _enabled ? const Color(0xFF16A34A) : const Color(0xFFFF8A00),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _enabled ? '通知使用权已开启，正在监听' : '通知使用权还没开启',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (!_enabled)
              TextButton(onPressed: _openSettings, child: const Text('去开启')),
          ]),
        ),

        // 提醒权限提示
        if (!_canNotify)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFDEEEE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.campaign, color: Color(0xFFD64545)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('「重点提醒」弹响权限未开启', style: TextStyle(fontSize: 13)),
              ),
              TextButton(onPressed: _requestNotify, child: const Text('去开启')),
            ]),
          ),

        // 全屏弹窗权限提示
        if (!_canFull)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.fullscreen, color: Color(0xFFFF8A00)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('开启「全屏提醒」后，重要消息会像来电一样弹出',
                    style: TextStyle(fontSize: 13)),
              ),
              TextButton(onPressed: _openFullScreen, child: const Text('去开启')),
            ]),
          ),

        // 发现的群组（一键设为安静）
        if (newFound.isNotEmpty)
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('发现的群组 / 联系人',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              const Text('这些对话来过消息。点「设为安静」，以后它的消息就由 Nooti 静音（私聊建议别设）。',
                  style: TextStyle(fontSize: 11.5, color: Colors.black45, height: 1.4)),
              const SizedBox(height: 6),
              for (final d in newFound.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(
                      d['g'] == true ? Icons.groups : Icons.person,
                      size: 20,
                      color: d['g'] == true
                          ? const Color(0xFF3D7FE0)
                          : const Color(0xFF9AA3B3),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${d['t'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    _badge(
                      d['g'] == true ? '群' : '私聊',
                      d['g'] == true
                          ? const Color(0xFFE3EEFF)
                          : const Color(0xFFEEEFF3),
                      d['g'] == true
                          ? const Color(0xFF2E6BD0)
                          : const Color(0xFF6B7280),
                    ),
                    TextButton(
                      onPressed: () => _addGroupName('${d['t'] ?? ''}'),
                      child: const Text('设为安静', style: TextStyle(fontSize: 12.5)),
                    ),
                  ]),
                ),
            ]),
          ),

        // 过滤规则卡
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('过滤规则',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: _filterOn,
                onChanged: (v) {
                  setState(() => _filterOn = v);
                  _saveRules();
                },
              ),
            ]),
            const Text(
              '开启后：名单里的群消息会被 Nooti 静音（不响不弹）；群里出现重点词会像来电一样弹出强提醒；个人私聊完全不受影响。',
              style: TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 10),
            const Text('安静群组', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _inputRow(_groupCtrl, '填群名或群名里的一段', () {
              _addGroupName(_groupCtrl.text);
              _groupCtrl.clear();
            }),
            _chips(_groups, (i) {
              setState(() => _groups.removeAt(i));
              _saveRules();
            }),
            const SizedBox(height: 12),
            const Text('重点提醒词', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _inputRow(_kwCtrl, '手动输入关键词', () {
              _addKeyword(_kwCtrl.text);
              _kwCtrl.clear();
            }),
            _chips(_keywords, (i) {
              setState(() => _keywords.removeAt(i));
              _saveRules();
            }),
            const SizedBox(height: 8),
            const Text('常用词一键添加：',
                style: TextStyle(fontSize: 11.5, color: Colors.black45)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final k in _presetKeywords.where((k) => !_keywords.contains(k)))
                  ActionChip(
                    label: Text('+ $k', style: const TextStyle(fontSize: 12)),
                    onPressed: () => _addKeyword(k),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ]),
        ),

        // 抓到的通知
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 16, 4),
          child: Text('抓到的通知',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child:
                  Text('还没有抓到任何通知', style: TextStyle(color: Colors.black38)),
            ),
          )
        else
          for (final m in _items)
            Builder(builder: (c) {
              final bool silent = m['silent'] == true;
              final bool muted = m['muted'] == true;
              final bool alerted = m['alerted'] == true;
              final String app = _appName('${m['pkg'] ?? ''}');
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                      child: Text(app.isEmpty ? '?' : app.substring(0, 1))),
                  title: Row(children: [
                    Expanded(
                      child: Text(
                        '$app · ${m['title'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (alerted)
                      _badge('重点提醒', const Color(0xFFFDEEEE),
                          const Color(0xFFD64545)),
                    if (muted && !alerted)
                      _badge('已静音', const Color(0xFFEEEFF3),
                          const Color(0xFF6B7280)),
                    if (silent)
                      _badge('免打扰', const Color(0xFFEFECFE),
                          const Color(0xFF7C6BF0)),
                  ]),
                  subtitle: Text('${m['text'] ?? ''}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(_fmtTime(m['time']),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black38)),
                ),
              );
            }),
        const SizedBox(height: 80),
      ]),
      floatingActionButton: _items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
              label: const Text('清空'),
            ),
    );
  }
}
