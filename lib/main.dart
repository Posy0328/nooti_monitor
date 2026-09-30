import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const NootiApp());

/// 与安卓原生端（MainActivity.kt）约定好的通道名与指令名，两端必须一致
const MethodChannel _ch = MethodChannel('nooti/listener');

/// 等级：0 一般（蓝） / 1 重要（橙） / 2 紧急（红）
const int _kGeneral = 0;
const int _kImportant = 1;
const int _kUrgent = 2;

const Color _cGeneral = Color(0xFF3D7FE0);
const Color _cImportant = Color(0xFFF2843C);
const Color _cUrgent = Color(0xFFE5484D);

String _levelName(int lv) => lv == _kUrgent ? '紧急' : (lv == _kImportant ? '重要' : '一般');
Color _levelColor(int lv) => lv == _kUrgent ? _cUrgent : (lv == _kImportant ? _cImportant : _cGeneral);

/// 校园/班级场景高频词，一键添加。第二个值是默认等级。
const List<List<Object>> _presets = [
  ['@全体成员', _kUrgent], ['@所有人', _kUrgent], ['有人@我', _kUrgent],
  ['全体成员', _kUrgent], ['紧急', _kUrgent], ['马上', _kUrgent], ['立刻', _kUrgent],
  ['老师', _kImportant], ['班主任', _kImportant], ['辅导员', _kImportant],
  ['班长', _kImportant], ['团支书', _kImportant], ['学习委员', _kImportant],
  ['截止', _kImportant], ['交作业', _kImportant], ['作业', _kImportant],
  ['提交', _kImportant], ['逾期', _kImportant], ['未交', _kImportant],
  ['接龙', _kImportant], ['报名', _kImportant], ['签到', _kImportant],
  ['打卡', _kImportant], ['统计', _kImportant], ['填表', _kImportant],
  ['材料', _kImportant], ['改期', _kImportant], ['换教室', _kImportant],
  ['停课', _kImportant], ['调课', _kImportant], ['考试', _kImportant],
  ['成绩', _kImportant], ['通知', _kImportant], ['开会', _kImportant],
  ['收到请回复', _kImportant], ['缴费', _kImportant],
];

/// 把常见的系统包名翻译成人话（没收录的就原样显示）
String _appName(String pkg) {
  const Map<String, String> names = {
    'com.tencent.mm': '微信',
    'com.tencent.mobileqq': 'QQ',
    'com.alibaba.android.rimet': '钉钉',
    'com.tencent.wework': '企业微信',
    'com.tencent.tim': 'TIM',
  };
  return names[pkg] ?? (pkg.isEmpty ? '手动' : pkg);
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
  int _tab = 0;                  // 0=监听  1=待办
  bool _enabled = false;         // 通知使用权
  bool _canNotify = false;       // Nooti 发提醒的权限
  bool _filterOn = true;         // 过滤总开关
  bool _allGroups = true;        // 所有群都安静（默认开：不用一个个加群名）
  int _minLevel = _kGeneral;     // 弹卡门槛：0 全部 / 1 重要以上 / 2 只有紧急

  List<String> _groups = [];                   // 安静群组（手动名单）
  List<String> _keywords = [];                 // 重点提醒词
  Map<String, int> _kwLevels = {};             // 词 → 等级
  List<String> _learnedTitles = [];            // 系统认出来的群名
  List<Map<String, dynamic>> _discovered = []; // 见过消息的会话
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
    _loadLearned();
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

  // ---------- 规则读写 ----------

  Future<void> _loadRules() async {
    try {
      final s = await _ch.invokeMethod<String>('getRules') ?? '';
      if (s.isEmpty) return;
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _filterOn = m['enabled'] != false;
        _allGroups = m['allGroups'] != false;
        _minLevel = (m['minLevel'] as num?)?.toInt() ?? _kGeneral;
        _groups = (m['groups'] as List? ?? []).map((e) => '$e').toList();
        _keywords = (m['keywords'] as List? ?? []).map((e) => '$e').toList();
        final lv = m['kwLevel'];
        if (lv is Map) {
          _kwLevels = lv.map((k, v) => MapEntry('$k', (v as num).toInt()));
        }
      });
    } catch (_) {}
  }

  Future<void> _saveRules() async {
    try {
      await _ch.invokeMethod('setRules', {
        'json': jsonEncode({
          'enabled': _filterOn,
          'allGroups': _allGroups,
          'minLevel': _minLevel,
          'groups': _groups,
          'keywords': _keywords,
          'kwLevel': _kwLevels,
        })
      });
    } catch (_) {}
  }

  Future<void> _loadLearned() async {
    try {
      final s = await _ch.invokeMethod<String>('getLearned') ?? '[]';
      final l = jsonDecode(s) as List;
      if (!mounted) return;
      setState(() {
        _learnedTitles = l
            .whereType<Map>()
            .map((e) => '${e['t'] ?? ''}')
            .where((e) => e.isNotEmpty)
            .toList();
      });
    } catch (_) {}
  }

  // ---------- 词表操作 ----------

  void _addGroupName(String v) {
    v = v.trim();
    if (v.isEmpty || _groups.contains(v)) return;
    setState(() => _groups.add(v));
    _saveRules();
  }

  void _addKeyword(String v, [int? level]) {
    v = v.trim();
    if (v.isEmpty || _keywords.contains(v)) return;
    setState(() {
      _keywords.add(v);
      _kwLevels[v] = level ?? _kImportant;
    });
    _saveRules();
  }

  /// 点一下词，在 一般 → 重要 → 紧急 之间轮换
  void _cycleKeywordLevel(String w) {
    final cur = _kwLevels[w] ?? _kImportant;
    final next = cur >= _kUrgent ? _kGeneral : cur + 1;
    setState(() => _kwLevels[w] = next);
    _saveRules();
  }

  void _removeKeyword(int i) {
    if (i < 0 || i >= _keywords.length) return;
    final w = _keywords[i];
    setState(() {
      _keywords.removeAt(i);
      _kwLevels.remove(w);
    });
    _saveRules();
  }

  // ---------- 数据刷新 ----------

  Future<void> _refresh() async {
    bool enabled = false, canNotify = false;
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
      final list = await _ch.invokeMethod<List<dynamic>>('getCaptured');
      if (list != null) {
        items = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    try {
      final s = await _ch.invokeMethod<String>('getDiscovered') ?? '[]';
      discovered = (jsonDecode(s) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
          .reversed
          .toList();
    } catch (_) {}
    try {
      final s = await _ch.invokeMethod<String>('getTodos') ?? '[]';
      todos = (jsonDecode(s) as List)
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

  Future<void> _clear() async {
    try {
      await _ch.invokeMethod('clear');
    } catch (_) {}
    if (mounted) setState(() => _items = []);
  }

  Future<void> _markGroup(String pkg, String t, bool g) async {
    try {
      await _ch.invokeMethod('markAsGroup', {'pkg': pkg, 't': t, 'g': g});
    } catch (_) {}
    await _loadLearned();
  }

  // ---------- 待办 ----------

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
      await _ch.invokeMethod('addTodo', {'title': '手动添加', 'text': v, 'pkg': '', 'kw': ''});
    } catch (_) {}
    _todoCtrl.clear();
    _refresh();
  }

  // ---------- 小工具 ----------

  String _fmtTime(dynamic v) {
    final int ms = v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10, color: fg)),
      );

  Widget _card({required Widget child, EdgeInsets? margin}) => Container(
        margin: margin ?? const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3E9F4)),
        ),
        child: child,
      );

  Widget _inputRow(TextEditingController ctrl, String hint, VoidCallback onAdd) => Row(children: [
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

  Widget _sectionTitle(String t) =>
      Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700));

  Widget _note(String text) =>
      Text(text, style: const TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.5));

  /// 关键词标签：颜色 = 等级，点一下换等级，× 删掉
  Widget _kwChip(String w) {
    final lv = _kwLevels[w] ?? _kImportant;
    return InputChip(
      label: Text('$w · ${_levelName(lv)}',
          style: const TextStyle(fontSize: 11.5, color: Colors.white)),
      backgroundColor: _levelColor(lv),
      deleteIconColor: Colors.white,
      onPressed: () => _cycleKeywordLevel(w),
      onDeleted: () => _removeKeyword(_keywords.indexOf(w)),
      visualDensity: VisualDensity.compact,
    );
  }

  // ---------- 页一：监听 ----------

  Widget _buildMonitor() {
    // 界面上的群名集合：系统学到的 + 手动加的
    final knownGroups = <String>{..._learnedTitles, ..._groups};
    final found = _discovered.where((d) {
      final t = '${d['t'] ?? ''}';
      return t.isNotEmpty && !_groups.any((g) => t.contains(g));
    }).toList();

    return ListView(children: [
      // 权限状态
      _card(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          Icon(_enabled ? Icons.check_circle : Icons.notifications_off,
              color: _enabled ? const Color(0xFF16A34A) : const Color(0xFFFF8A00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_enabled ? '通知使用权已开启，正在监听' : '通知使用权还没开启',
                style: const TextStyle(fontSize: 14)),
          ),
          if (!_enabled) TextButton(onPressed: _openSettings, child: const Text('去开启')),
        ]),
      ),

      if (!_canNotify)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFFDEEEE), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.campaign, color: Color(0xFFD64545)),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('「重点提醒」通知权限没开，卡片弹不出来', style: TextStyle(fontSize: 13))),
            TextButton(onPressed: _requestNotify, child: const Text('去开启')),
          ]),
        ),

      // 必读：微信的免打扰必须关掉，否则微信自己就不发通知，谁也抓不到
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.priority_high_rounded, size: 18, color: Color(0xFFE5484D)),
            SizedBox(width: 8),
            Text('用之前必须先做这一步', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          const Text(
            '微信里那些群的「消息免打扰」，要全部关掉。\n'
            '原因：微信一旦开了免打扰，它自己就再也不往通知栏发通知了——Nooti 拿不到通知，'
            '既静不了音，也做不出重点提醒。\n'
            '正确做法：微信里关掉免打扰 → 回到 Nooti 打开下面的「所有群都安静」。'
            '静音这件事交给 Nooti 做，它才知道哪句话重要。',
            style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.6),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(10)),
            child: const Text(
              '卡片没弹出来？多半是系统把「悬浮通知 / 锁屏通知」关了。'
              '去系统设置里给 Nooti 打开「横幅」「锁屏显示」「允许自启动」「电池不受限制」。',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF9A5410), height: 1.5),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child:
                TextButton(onPressed: _openNotifySettings, child: const Text('去通知设置')),
          ),
        ]),
      ),

      // 静音与提醒
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('静音与提醒',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Switch(
              value: _filterOn,
              onChanged: (v) {
                setState(() => _filterOn = v);
                _saveRules();
              },
            ),
          ]),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _allGroups,
            onChanged: (v) {
              setState(() => _allGroups = v);
              _saveRules();
            },
            title: const Text('所有群都安静',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: _note('推荐打开。群消息一律不响不弹，只有命中重点词才弹卡片——不用一个个加群名。'),
          ),

          const Divider(height: 18),
          _sectionTitle('安静群组（额外指定）'),
          const SizedBox(height: 6),
          _inputRow(_groupCtrl, '填群名或群名里的一段', () {
            _addGroupName(_groupCtrl.text);
            _groupCtrl.clear();
          }),
          if (_groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _groups.length; i++)
                    Chip(
                      label: Text(_groups[i], style: const TextStyle(fontSize: 12)),
                      onDeleted: () {
                        setState(() => _groups.removeAt(i));
                        _saveRules();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),

          const SizedBox(height: 14),
          _sectionTitle('重点提醒词'),
          const SizedBox(height: 2),
          _note('颜色就是这个词的等级：红=紧急、橙=重要、蓝=一般。点一下词就能换等级。'),
          const SizedBox(height: 6),
          _inputRow(_kwCtrl, '手动输入关键词', () {
            _addKeyword(_kwCtrl.text);
            _kwCtrl.clear();
          }),
          if (_keywords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final w in _keywords) _kwChip(w),
              ]),
            ),
          const SizedBox(height: 10),
          _note('常用词一键添加：'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final p in _presets)
                if (!_keywords.contains('${p[0]}'))
                  ActionChip(
                    avatar: CircleAvatar(backgroundColor: _levelColor(p[1] as int), radius: 5),
                    label: Text('${p[0]}', style: const TextStyle(fontSize: 12)),
                    onPressed: () => _addKeyword('${p[0]}', p[1] as int),
                    visualDensity: VisualDensity.compact,
                  ),
            ],
          ),

          const SizedBox(height: 14),
          _sectionTitle('什么等级才弹卡片'),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                  value: _kGeneral, label: Text('全都弹', style: TextStyle(fontSize: 12))),
              ButtonSegment<int>(
                  value: _kImportant, label: Text('重要以上', style: TextStyle(fontSize: 12))),
              ButtonSegment<int>(
                  value: _kUrgent, label: Text('只有紧急', style: TextStyle(fontSize: 12))),
            ],
            selected: {_minLevel},
            onSelectionChanged: (s) {
              setState(() => _minLevel = s.first);
              _saveRules();
            },
          ),
          const SizedBox(height: 4),
          _note(_minLevel == _kGeneral
              ? '命中任意重点词都弹卡片。'
              : '低于这个等级的命中会被安静收录进待办，不会弹卡片打扰你。'),
        ]),
      ),

      // 见过的会话
      if (found.isNotEmpty)
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('见过的会话（${found.length}）',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            _note('这些会话来过消息。标签是 Nooti 判断的群/个人，判断错了点右边按钮纠正。'),
            const SizedBox(height: 6),
            for (final d in found.take(12))
              Builder(builder: (_) {
                final t = '${d['t'] ?? ''}';
                final pkg = '${d['pkg'] ?? ''}';
                final last = '${d['last'] ?? ''}';
                final isGroup = d['g'] == true || knownGroups.contains(t);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Icon(isGroup ? Icons.groups : Icons.person,
                        size: 20, color: isGroup ? _cGeneral : const Color(0xFF9AA3B3)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        if (last.isNotEmpty)
                          Text(last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.black38)),
                      ]),
                    ),
                    _badge(
                        isGroup ? '群' : '个人',
                        isGroup ? const Color(0xFFE3EEFF) : const Color(0xFFEEEFF3),
                        isGroup ? const Color(0xFF2E6BD0) : const Color(0xFF6B7280)),
                    if (isGroup)
                      TextButton(
                        onPressed: () => _addGroupName(t),
                        child: const Text('设为安静', style: TextStyle(fontSize: 12.5)),
                      )
                    else
                      TextButton(
                        onPressed: () => _markGroup(pkg, t, true),
                        child: const Text('它其实是群', style: TextStyle(fontSize: 12.5)),
                      ),
                  ]),
                );
              }),
          ]),
        ),

      // 诊断
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 16, 4),
        child: Text('抓到的通知（含判定原因）',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      if (_items.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('还没有抓到任何通知', style: TextStyle(color: Colors.black38))),
        )
      else
        for (final m in _items)
          Builder(builder: (_) {
            final bool muted = m['muted'] == true;
            final bool alerted = m['alerted'] == true;
            final bool isGroup = m['isGroup'] == true;
            final String app = _appName('${m['pkg'] ?? ''}');
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(child: Text(app.isEmpty ? '?' : app.substring(0, 1))),
                title: Row(children: [
                  Expanded(
                    child: Text('$app · ${m['title'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  if (alerted) _badge('弹卡片', const Color(0xFFFDECEC), _cUrgent),
                  if (muted && !alerted)
                    _badge('已静音', const Color(0xFFEEEFF3), const Color(0xFF6B7280)),
                  if (isGroup) _badge('群', const Color(0xFFE3EEFF), const Color(0xFF2E6BD0)),
                ]),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${m['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('为什么：${m['reason'] ?? '—'}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8A93A5))),
                ]),
                trailing: Text(_fmtTime(m['time']),
                    style: const TextStyle(fontSize: 11, color: Colors.black38)),
              ),
            );
          }),
      const SizedBox(height: 80),
    ]);
  }

  // ---------- 页二：待办 ----------

  Widget _buildTodo() {
    final doneCount = _todos.where((t) => t['done'] == true).length;
    return ListView(children: [
      _card(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.inbox_rounded, size: 18, color: _cGeneral),
            const SizedBox(width: 8),
            Text('待办 · ${_todos.length} 条',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (doneCount > 0)
              TextButton(
                onPressed: _todoClearDone,
                child: Text('清掉已完成 $doneCount', style: const TextStyle(fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 6),
          _note('卡片上点「收入待办」，那条消息就原封不动存到这里——带来源群、时间和原文。'
              '这是微信免打扰给不了的：它只会响一下，不会替你留着。'),
          const SizedBox(height: 10),
          _inputRow(_todoCtrl, '也可以手动记一条', _todoAddManual),
        ]),
      ),
      if (_todos.isEmpty)
        const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('还没有收入待办的消息', style: TextStyle(color: Colors.black38))),
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
                      decoration:
                          t['done'] == true ? TextDecoration.lineThrough : TextDecoration.none,
                      color: t['done'] == true ? Colors.black38 : Colors.black87,
                    ),
                  ),
                ),
                if ('${t['kw'] ?? ''}'.isNotEmpty)
                  _badge('${t['kw']}', const Color(0xFFFDECEC), _cUrgent),
              ]),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 3),
                Text('${t['text'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 3),
                Text(_fmtTime(t['ts']),
                    style: const TextStyle(fontSize: 11, color: Colors.black38)),
              ]),
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
      appBar: AppBar(title: Text(_tab == 0 ? 'Nooti 监听' : '待办')),
      body: IndexedStack(index: _tab, children: [_buildMonitor(), _buildTodo()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.hearing_outlined),
              selectedIcon: Icon(Icons.hearing),
              label: '监听'),
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
