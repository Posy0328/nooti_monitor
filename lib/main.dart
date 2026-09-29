import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const NootiApp());

/// 与安卓原生端（MainActivity.kt）约定好的通道名与指令名，两端必须一致
const MethodChannel _ch = MethodChannel('nooti/listener');

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
  bool _canNotify = false;    // Nooti 自己发提醒的权限
  bool _filterOn = false;     // 过滤总开关
  List<String> _groups = [];   // 安静群组
  List<String> _keywords = []; // 重点提醒词
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

  void _addGroup() {
    final v = _groupCtrl.text.trim();
    if (v.isEmpty || _groups.contains(v)) return;
    setState(() => _groups.add(v));
    _groupCtrl.clear();
    _saveRules();
  }

  void _addKeyword() {
    final v = _kwCtrl.text.trim();
    if (v.isEmpty || _keywords.contains(v)) return;
    setState(() => _keywords.add(v));
    _kwCtrl.clear();
    _saveRules();
  }

  Future<void> _refresh() async {
    bool enabled = false;
    bool canNotify = false;
    List<Map<String, dynamic>> items = const [];
    try {
      enabled = await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {}
    try {
      canNotify = await _ch.invokeMethod<bool>('canNotify') ?? false;
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
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _canNotify = canNotify;
      _items = items;
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

  Widget _ruleEditor({
    required String label,
    required String hint,
    required TextEditingController ctrl,
    required List<String> values,
    required VoidCallback onAdd,
    required void Function(int) onDel,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(hint, style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              isDense: true,
              hintText: '输入后点「添加」',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: onAdd, child: const Text('添加')),
      ]),
      if (values.isNotEmpty)
        Padding(
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
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nooti 监听')),
      body: Column(children: [
        // 监听权限状态卡
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _enabled ? const Color(0xFFE7F8EE) : const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(14),
          ),
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

        // 提醒权限提示（重点消息要弹响需要它）
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

        // 过滤规则卡
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F8FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDCE6F8)),
          ),
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
              '开启后：名单里的群消息会被 Nooti 静音（不响不弹）；群里出现重点词会大声提醒你；个人私聊完全不受影响。',
              style: TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.5),
            ),
            _ruleEditor(
              label: '安静群组',
              hint: '填群名或群名里的一段，比如「班级群」「一家人」',
              ctrl: _groupCtrl,
              values: _groups,
              onAdd: _addGroup,
              onDel: (i) {
                setState(() => _groups.removeAt(i));
                _saveRules();
              },
            ),
            _ruleEditor(
              label: '重点提醒词',
              hint: '比如「有人@我」「老师」「截止」「交作业」',
              ctrl: _kwCtrl,
              values: _keywords,
              onAdd: _addKeyword,
              onDel: (i) {
                setState(() => _keywords.removeAt(i));
                _saveRules();
              },
            ),
          ]),
        ),

        const SizedBox(height: 8),

        // 抓到的通知列表
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Text('还没有抓到任何通知', style: TextStyle(color: Colors.black38)))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (c, i) {
                    final m = _items[i];
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
                            _badge('重点提醒', const Color(0xFFFDEEEE), const Color(0xFFD64545)),
                          if (muted && !alerted)
                            _badge('已静音', const Color(0xFFEEEFF3), const Color(0xFF6B7280)),
                          if (silent)
                            _badge('免打扰', const Color(0xFFEFECFE), const Color(0xFF7C6BF0)),
                        ]),
                        subtitle: Text('${m['text'] ?? ''}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text(_fmtTime(m['time']),
                            style:
                                const TextStyle(fontSize: 11, color: Colors.black38)),
                      ),
                    );
                  },
                ),
        ),
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
