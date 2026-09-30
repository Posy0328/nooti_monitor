import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const NootiApp());

/// 与安卓原生端（MainActivity.kt）约定好的通道名与指令名，两端必须一致
const MethodChannel _ch = MethodChannel('nooti/listener');

/// 校园/班级场景高频重点词，一键添加
const List<String> _presetKeywords = [
  '@全体成员', '@所有人', '有人@我', '全体成员',
  '老师', '班主任', '辅导员', '班长', '团支书', '学习委员',
  '截止', '交作业', '作业', '提交', '逾期', '未交',
  '接龙', '报名', '签到', '打卡', '统计', '填表', '材料',
  '改期', '换教室', '停课', '调课', '考试', '成绩',
  '通知', '紧急', '开会', '收到请回复', '缴费',
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
  int _tab = 0;                 // 0=监听  1=待办
  bool _enabled = false;        // 通知使用权
  bool _canNotify = false;      // Nooti 发提醒的权限
  bool _canFull = true;         // 全屏弹窗权限（老系统默认有）
  bool _filterOn = false;       // 过滤总开关
  bool _fullscreen = false;     // 提醒方式：false=小卡片（默认） true=全屏盖脸
  List<String> _groups = [];    // 安静群组
  List<String> _keywords = [];  // 重点提醒词
  List<Map<String, dynamic>> _discovered = []; // 自动发现的群/联系人
  List<Map<String, dynamic>> _items = [];      // 抓包流水
  List<Map<String, dynamic>> _todos = [];      // 待办池
  Timer? _timer;
  final _groupCtrl = TextEditingController();
  final _kwCtrl = TextEditingController();
  final _todoCtrl = TextEditingController();

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
    _todoCtrl.dispose();
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
          _fullscreen = m['fullscreen'] == true;
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
          'fullscreen': _fullscreen,
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
    List<Map<String, dynamic>> todos = const [];
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
    try {
      final s = await _ch.invokeMethod<String>('getTodos') ?? '[]';
      final l = jsonDecode(s) as List;
      todos = l
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
      _todos = todos;
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

  Future<void> _openNotifySettings() async {
    try {
      await _ch.invokeMethod('openNotifySettings');
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

  Future<void> _todoRemove(String id) async {
    try {
      await _ch.invokeMethod('removeTodo', {'id': id});
    } catch (_) {}
    _refresh();
  }

  Future<void> _todoToggle(String id) async {
    try {
      await _ch.invokeMethod('toggleTodo', {'id': id});
    } catch (_) {}
    _refresh();
  }

  Future<void> _todoClearDone() async {
    for (final t in _todos) {
      if (t['done'] == true) {
        try {
          await _ch.invokeMethod('removeTodo', {'id': '${t['id']}'});
        } catch (_) {}
      }
    }
    _refresh();
  }

  Future<void> _todoAddManual() async {
    final v = _todoCtrl.text.trim();
    if (v.isEmpty) return;
    try {
      await _ch.invokeMethod('addTodo', {
        'title': '手动添加',
        'text': v,
        'pkg': '',
        'kw': '',
      });
    } catch (_) {}
    _todoCtrl.clear();
    _refresh();
  }

  String _fmtTime(dynamic v) {
    final int ms = v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
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

  Widget _note(String text) => Text(
        text,
        style: const TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.5),
      );

  // ---------- 页一：监听 ----------
  Widget _buildMonitor() {
    // 还没加进安静名单的「发现的群」放前面
    final newFound = _discovered.where((d) {
      final t = '${d['t'] ?? ''}';
      return !_groups.any((g) => t.contains(g));
    }).toList();

    return ListView(children: [
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

      // 这张卡片到底弹不弹得出来，取决于系统的「悬浮通知」开关
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.notifications_active_outlined, size: 18, color: Color(0xFF3D7FE0)),
            SizedBox(width: 8),
            Text('提醒卡片弹不出来？',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          const Text(
            '重点消息会从屏幕顶部浮出一张小卡片，几秒后自动收起，也能直接叉掉。'
            '如果你的手机没弹，是系统把「悬浮通知」关了 —— 去通知设置里把它打开即可。',
            style: TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.5),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _openNotifySettings,
              child: const Text('去通知设置'),
            ),
          ),
        ]),
      ),

      // 微信免打扰 vs Nooti：把差异讲清楚，不然用户会问「那我开微信免打扰不就行了」
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.compare_arrows, size: 18, color: Color(0xFF7C6BF0)),
            SizedBox(width: 8),
            Text('和微信自带免打扰，差在哪？',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          _diffRow('关键词随便定', '微信只认「@我 / @所有人」；Nooti 认你自己填的词：截止、交作业、接龙、改教室…', true),
          _diffRow('提醒完还能留下', '微信响完就没了；Nooti 的卡片上有个「收入待办」，消息会存进待办页慢慢处理', true),
          _diffRow('群消息归一处', '不用翻几十个群找那句话，待办页按时间排好，能删能勾完成', true),
          _diffRow('微信图标上的红点', '这个第三方改不了，是微信自己画的。缓解办法：微信里把群「免打扰 + 折叠」，群消息看 Nooti', false),
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
            '开启后：名单里的群消息会被 Nooti 静音（不响不弹，通知栏里堆积的也会一起清掉）；'
            '群里出现重点词就从顶部浮出一张小卡片，可以叉掉或收入待办；个人私聊完全不受影响。',
            style: TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.5),
          ),
          const SizedBox(height: 12),

          const Text('提醒方式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.crop_landscape, size: 16),
                label: Text('小卡片', style: TextStyle(fontSize: 12)),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.fullscreen, size: 16),
                label: Text('全屏盖脸', style: TextStyle(fontSize: 12)),
              ),
            ],
            selected: {_fullscreen},
            onSelectionChanged: (s) {
              setState(() => _fullscreen = s.first);
              _saveRules();
            },
          ),
          const SizedBox(height: 4),
          _note(_fullscreen
              ? '全屏：像来电一样整屏盖住，不想错过时用。需要系统给「全屏提醒」权限。'
              : '小卡片：从屏幕顶部浮出一张小卡，几秒后自动收起，不打断你正在做的事。'),
          if (_fullscreen && !_canFull)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.fullscreen, size: 18, color: Color(0xFFFF8A00)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('还没给「全屏提醒」权限', style: TextStyle(fontSize: 12.5)),
                ),
                TextButton(onPressed: _openFullScreen, child: const Text('去开启')),
              ]),
            ),
          const SizedBox(height: 12),

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
            child: Text('还没有抓到任何通知', style: TextStyle(color: Colors.black38)),
          ),
        )
      else
        for (final m in _items)
          Builder(builder: (c) {
            final bool silent = m['silent'] == true;
            final bool muted = m['muted'] == true;
            final bool alerted = m['alerted'] == true;
            final String kw = '${m['kw'] ?? ''}';
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
                    _badge(kw.isNotEmpty ? '命中 $kw' : '重点提醒',
                        const Color(0xFFFDEEEE), const Color(0xFFD64545)),
                  if (muted && !alerted)
                    _badge('已静音', const Color(0xFFEEEFF3), const Color(0xFF6B7280)),
                  if (silent)
                    _badge('免打扰', const Color(0xFFEFECFE), const Color(0xFF7C6BF0)),
                ]),
                subtitle: Text('${m['text'] ?? ''}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text(_fmtTime(m['time']),
                    style: const TextStyle(fontSize: 11, color: Colors.black38)),
              ),
            );
          }),
      const SizedBox(height: 80),
    ]);
  }

  Widget _diffRow(String title, String desc, bool good) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          good ? Icons.check_circle : Icons.info_outline,
          size: 16,
          color: good ? const Color(0xFF16A34A) : const Color(0xFFFF8A00),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.45),
              children: [
                TextSpan(
                  text: '$title：',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.black87),
                ),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ---------- 页二：待办 ----------
  Widget _buildTodo() {
    final doneCount = _todos.where((t) => t['done'] == true).length;
    return ListView(children: [
      _card(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.inbox_rounded, size: 18, color: Color(0xFF3D7FE0)),
            const SizedBox(width: 8),
            Text('待办 · ${_todos.length} 条',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (doneCount > 0)
              TextButton(
                onPressed: _todoClearDone,
                child: Text('清掉已完成 $doneCount',
                    style: const TextStyle(fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 6),
          const Text(
            '重点消息弹出卡片时，点卡片上的「收入待办」，那条消息就会原封不动存到这里 —— '
            '带来源群、时间和原文。这是微信自带免打扰给不了的东西：它只会响一下，不会替你留着。',
            style: TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.5),
          ),
          const SizedBox(height: 10),
          _inputRow(_todoCtrl, '也可以手动记一条', _todoAddManual),
        ]),
      ),
      if (_todos.isEmpty)
        const Padding(
          padding: EdgeInsets.all(40),
          child: Center(
            child: Text('还没有收入待办的消息', style: TextStyle(color: Colors.black38)),
          ),
        )
      else
        for (final t in _todos)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              dense: true,
              leading: Checkbox(
                value: t['done'] == true,
                onChanged: (_) => _todoToggle('${t['id']}'),
                visualDensity: VisualDensity.compact,
              ),
              title: Row(children: [
                Expanded(
                  child: Text(
                    '${_appName('${t['pkg'] ?? ''}')} · ${t['title'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      decoration: t['done'] == true
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color:
                          t['done'] == true ? Colors.black38 : Colors.black87,
                    ),
                  ),
                ),
                if ('${t['kw'] ?? ''}'.isNotEmpty)
                  _badge('${t['kw']}', const Color(0xFFFDEEEE), const Color(0xFFD64545)),
              ]),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 3),
                  Text('${t['text'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 3),
                  Text(_fmtTime(t['ts']),
                      style: const TextStyle(fontSize: 11, color: Colors.black38)),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _todoRemove('${t['id']}'),
              ),
            ),
          ),
      const SizedBox(height: 80),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Nooti 监听' : '待办'),
      ),
      body: IndexedStack(
        index: _tab,
        children: [_buildMonitor(), _buildTodo()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.hearing_outlined),
            selectedIcon: Icon(Icons.hearing),
            label: '监听',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _todos.isNotEmpty,
              label: Text('${_todos.length}'),
              child: const Icon(Icons.inbox_outlined),
            ),
            selectedIcon: const Icon(Icons.inbox_rounded),
            label: '待办',
          ),
        ],
      ),
      floatingActionButton: _tab == 0 && _items.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
              label: const Text('清空流水'),
            )
          : null,
    );
  }
}
