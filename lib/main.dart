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

class _MonitorHomeState extends State<MonitorHome> with WidgetsBindingObserver {
  int _tab = 0;                  // 0=监听  1=消息  2=待办
  bool _enabled = false;         // 通知使用权
  bool _canNotify = false;       // Nooti 发提醒的权限
  bool _overlayOk = false;       // 悬浮窗权限：卡片能不能霸道地盖在屏幕正中央
  int _listenerTs = 0;           // 监听服务心跳：>0 且很新 = 服务活着；旧了/没有 = 被系统杀了
  bool _batteryOk = false;       // 电池优化白名单：不在里面的话国产系统随时冻结我们
  bool _filterOn = true;         // 过滤总开关
  bool _allGroups = true;        // 所有群都安静（默认开：不用一个个加群名）
  bool _watchOthers = false;     // 也收录非聊天应用的通知（测试用，默认关：只看微信/QQ/钉钉等）
  int _minLevel = _kGeneral;     // 弹卡门槛：0 全部 / 1 重要以上 / 2 只有紧急
  int _inboxFilter = 0;          // 消息页筛选：0 全部 / 1 弹过卡 / 2 已静音 / 3 群消息 / 4 指定会话
  String _inboxConv = '';        // 筛选=4 时，只看这个会话名

  List<String> _groups = [];                   // 安静群组（手动名单）
  List<String> _keywords = [];                 // 重点提醒词
  Map<String, int> _kwLevels = {};             // 词 → 等级
  List<String> _learnedTitles = [];            // 系统认出来的群名
  List<Map<String, dynamic>> _discovered = []; // 见过消息的会话
  List<Map<String, dynamic>> _items = [];      // 抓包流水（最近60条，诊断用）
  List<Map<String, dynamic>> _inbox = [];      // 全量收到的消息（落盘）
  List<Map<String, dynamic>> _todos = [];      // 待办池

  Timer? _timer;
  final _groupCtrl = TextEditingController();
  final _kwCtrl = TextEditingController();
  final _todoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRules();
    _loadLearned();
    _refresh();
    _hideOverlay();   // 人已经在 App 里了，卡片不用再压在屏幕上
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _groupCtrl.dispose();
    _kwCtrl.dispose();
    _todoCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _hideOverlay();
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
        _watchOthers = m['watchOthers'] == true;
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
          'watchOthers': _watchOthers,
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
    bool enabled = false, canNotify = false, overlayOk = false, batteryOk = false;
    int listenerTs = 0;
    List<Map<String, dynamic>> items = const [];
    List<Map<String, dynamic>> discovered = const [];
    List<Map<String, dynamic>> todos = const [];
    List<Map<String, dynamic>> inbox = const [];
    try {
      enabled = await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {}
    try {
      canNotify = await _ch.invokeMethod<bool>('canNotify') ?? false;
    } catch (_) {}
    try {
      overlayOk = await _ch.invokeMethod<bool>('canOverlay') ?? false;
    } catch (_) {}
    try {
      listenerTs = (await _ch.invokeMethod<int>('listenerAlive')) ?? 0;
    } catch (_) {}
    try {
      batteryOk = await _ch.invokeMethod<bool>('batteryOk') ?? false;
    } catch (_) {}
    try {
      final list = await _ch.invokeMethod<List<dynamic>>('getCaptured');
      if (list != null) {
        items = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    try {
      final list = await _ch.invokeMethod<List<dynamic>>('getInbox');
      if (list != null) {
        inbox = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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
      _overlayOk = overlayOk;
      _listenerTs = listenerTs;
      _batteryOk = batteryOk;
      _items = items;
      _inbox = inbox;
      _discovered = discovered;
      _todos = todos;
    });
  }

  // 监听服务健不健康：0=没授权 1=活着 2=疑似被系统杀了
  int get _serviceState {
    if (!_enabled) return 0;
    if (_listenerTs <= 0) return 2;
    final age = DateTime.now().millisecondsSinceEpoch - _listenerTs;
    return age < 10 * 60 * 1000 ? 1 : 2;
  }

  // 有没有抓到过微信/QQ 这类聊天应用的消息（一条都没有 = 免打扰没关 / 微信被杀）
  bool get _seenAnyChat {
    const chatPkgs = {
      'com.tencent.mm', 'com.tencent.mobileqq', 'com.tencent.tim',
      'com.tencent.wework', 'com.alibaba.android.rimet', 'com.ss.android.lark',
    };
    for (final m in _inbox) {
      if (chatPkgs.contains('${m['pkg'] ?? ''}')) return true;
    }
    for (final m in _items) {
      if (chatPkgs.contains('${m['pkg'] ?? ''}')) return true;
    }
    return false;
  }

  Future<void> _wakeService() async {
    try {
      await _ch.invokeMethod('requestRebind');
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 2));
    _refresh();
  }

  Future<void> _openBatterySettings() async {
    try {
      await _ch.invokeMethod('openBatterySettings');
    } catch (_) {}
  }

  Future<void> _openAutoStartSettings() async {
    try {
      await _ch.invokeMethod('openAutoStartSettings');
    } catch (_) {}
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

  Future<void> _openOverlaySettings() async {
    try {
      await _ch.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  Future<void> _hideOverlay() async {
    try {
      await _ch.invokeMethod('hideOverlay');
    } catch (_) {}
  }

  Future<void> _clearInbox() async {
    try {
      await _ch.invokeMethod('clearInbox');
    } catch (_) {}
    if (mounted) setState(() => _inbox = []);
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

  /// 防杀三件套里的一行：图标 + 名称 + 说明 + 可选按钮
  Widget _keepRow(IconData icon, Color color, String name, String desc,
          (String, VoidCallback)? action) =>
      Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(desc,
                style: const TextStyle(fontSize: 11, color: Colors.black45, height: 1.4)),
          ]),
        ),
        if (action != null)
          TextButton(onPressed: action.$2, child: Text(action.$1)),
      ]);

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

    final svc = _serviceState;
    return ListView(children: [
      // 监听服务健康卡：授权 + 服务是否活着，一眼看清
      _card(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
              svc == 1
                  ? Icons.check_circle
                  : (svc == 2 ? Icons.heart_broken : Icons.notifications_off),
              color: svc == 1
                  ? const Color(0xFF16A34A)
                  : (svc == 2 ? const Color(0xFFE5484D) : const Color(0xFFFF8A00)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                svc == 1
                    ? '监听服务运行中'
                    : (svc == 2 ? '授权还在，但监听服务被系统停了' : '通知使用权还没开启'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            if (svc == 0) TextButton(onPressed: _openSettings, child: const Text('去开启')),
            if (svc == 2) TextButton(onPressed: _wakeService, child: const Text('点我唤醒')),
          ]),
          if (svc == 2) ...[
            const SizedBox(height: 6),
            const Text(
              '这就是「刚装上有效、过一会儿就没反应」的原因：系统把监听服务杀了。'
              '点「点我唤醒」能立刻拉起来；想根治，把下面「防杀三件套」配好。',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF9A5410), height: 1.5),
            ),
          ],
        ]),
      ),

      // 防杀三件套：电池白名单 + 自启动 + 常驻通知。国产系统不配这三样，必被杀
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.shield_outlined, size: 18, color: Color(0xFFE5484D)),
            SizedBox(width: 8),
            Text('防杀三件套（华为/小米必做）',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          _note('Nooti 必须在后台一直活着才能监听。手机系统会「省电」把它杀掉，'
              '杀了就收不到、也不弹卡片——不是坏了，是被系统清了。'),
          const SizedBox(height: 10),
          _keepRow(
            _batteryOk ? Icons.check_circle : Icons.battery_alert,
            _batteryOk ? const Color(0xFF16A34A) : const Color(0xFFE5484D),
            '电池不受限制',
            _batteryOk ? '已加入白名单' : '没开：锁屏久了会被冻结',
            _batteryOk ? null : ('去开启', _openBatterySettings),
          ),
          const SizedBox(height: 8),
          _keepRow(
            Icons.rocket_launch_outlined,
            const Color(0xFFF2843C),
            '允许自启动',
            '系统设置里手动开：被清掉后能自己回来',
            ('去设置', _openAutoStartSettings),
          ),
          const SizedBox(height: 8),
          _keepRow(
            Icons.push_pin_outlined,
            const Color(0xFF3D7FE0),
            '常驻通知别划掉',
            '通知栏里「Nooti 正在监听」那条要在，它在=进程在',
            null,
          ),
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

      // 悬浮窗权限 —— 卡片能不能「霸道地出现在屏幕正中央」，全看它
      Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _overlayOk ? const Color(0xFFEAF7EE) : const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_overlayOk ? Icons.layers_rounded : Icons.warning_amber_rounded,
                color: _overlayOk ? const Color(0xFF16A34A) : const Color(0xFFE08A00)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _overlayOk ? '悬浮窗已开：卡片会直接盖在屏幕正中央' : '还差一步：卡片弹不到屏幕正中央',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            if (!_overlayOk)
              TextButton(onPressed: _openOverlaySettings, child: const Text('去开启')),
          ]),
          if (!_overlayOk) ...[
            const SizedBox(height: 4),
            const Text(
              '没有这个权限，卡片只能变成系统横幅，从顶部溜一下就没了 —— 就是你说的那种「跟普通弹窗一样」。'
              '去打开的页面里找到 Nooti监听，把「显示在其他应用上层 / 悬浮窗」打开。',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF9A5410), height: 1.5),
            ),
          ],
        ]),
      ),

      // 微信/QQ 完全没消息进来时的醒目提示（真机最常见：群免打扰没关，或微信自己被杀）
      if (_enabled && !_seenAnyChat)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.search_off, size: 18, color: Color(0xFFE08A00)),
              SizedBox(width: 8),
              Expanded(
                child: Text('到现在一条微信/QQ 消息都没抓到',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
              '两个最常见的坑，挨个查：\n'
              '① 微信里群的「消息免打扰」还开着 —— 开了它，微信压根不发通知，谁也抓不到。全关掉，静音交给 Nooti。\n'
              '② 微信自己被系统杀了 —— 平板锁屏久了，微信收消息都延迟。给微信也开「电池不受限制 + 自启动」。',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF9A5410), height: 1.6),
            ),
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

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _watchOthers,
            onChanged: (v) {
              setState(() => _watchOthers = v);
              _saveRules();
            },
            title: const Text('也收录其他应用的通知',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: _note('默认关：只看微信/QQ/钉钉等聊天应用，列表干净。'
                '打开后什么通知都收（代理软件、输入法都会灌进来），排查问题时再开。'),
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
            _note('这些会话来过消息。群/个人标签判断错了？点那个标签就能纠正。'),
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
                    // 标签可点：判断错了点一下就纠正（群 ↔ 个人）
                    GestureDetector(
                      onTap: () => _markGroup(pkg, t, !isGroup),
                      child: _badge(
                          isGroup ? '群' : '个人',
                          isGroup ? const Color(0xFFE3EEFF) : const Color(0xFFEEEFF3),
                          isGroup ? const Color(0xFF2E6BD0) : const Color(0xFF6B7280)),
                    ),
                    if (isGroup)
                      TextButton(
                        onPressed: () => _addGroupName(t),
                        child: const Text('设为安静', style: TextStyle(fontSize: 12.5)),
                      ),
                  ]),
                );
              }),
          ]),
        ),

      // 详细流水挪到「消息」页去了，这里只留一句指引
      _card(
        child: Row(children: [
          const Icon(Icons.list_alt_rounded, size: 18, color: Color(0xFF8A93A5)),
          const SizedBox(width: 8),
          Expanded(child: _note('收到的每一条消息（含为什么被静音）都在底部「消息」页，测试期去看那里统计。')),
        ]),
      ),

      const SizedBox(height: 80),
    ]);
  }

  // ---------- 页二：消息（全量收录，测试期统计用） ----------

  List<Map<String, dynamic>> get _inboxShown {
    switch (_inboxFilter) {
      case 1:
        return _inbox.where((m) => m['alerted'] == true).toList();
      case 2:
        return _inbox.where((m) => m['muted'] == true).toList();
      case 3:
        return _inbox.where((m) => m['isGroup'] == true).toList();
      case 4:
        return _inbox.where((m) => '${m['title']}' == _inboxConv).toList();
      default:
        return _inbox;
    }
  }

  Widget _statCol(String label, Object n, Color c, [VoidCallback? onTap]) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(children: [
            Text('$n',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
      );

  /// 点「会话数」：按会话聚合，看看都是谁在发，点进去只看它
  void _showConversations() {
    final agg = <String, Map<String, dynamic>>{};
    for (final m in _inbox) {
      final t = '${m['title'] ?? '（无标题）'}';
      final a = agg.putIfAbsent(t, () => {
            'title': t,
            'pkg': '${m['pkg'] ?? ''}',
            'count': 0,
            'last': 0,
            'isGroup': m['isGroup'] == true,
            'sample': '${m['text'] ?? ''}',
          });
      a['count'] = (a['count'] as int) + ((m['count'] as num?)?.toInt() ?? 1);
      final ts = (m['time'] as num?)?.toInt() ?? 0;
      if (ts > (a['last'] as int)) {
        a['last'] = ts;
        a['sample'] = '${m['text'] ?? ''}';
      }
      if (m['isGroup'] == true) a['isGroup'] = true;
    }
    final list = agg.values.toList()
      ..sort((a, b) => (b['last'] as int).compareTo(a['last'] as int));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, sc) => ListView(controller: sc, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('都是谁在发消息',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          for (final a in list)
            ListTile(
              dense: true,
              leading: Icon(a['isGroup'] == true ? Icons.groups : Icons.person,
                  color: a['isGroup'] == true ? _cGeneral : const Color(0xFF9AA3B3)),
              title: Text('${_appName('${a['pkg']}')} · ${a['title']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: Text('${a['sample']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5)),
              trailing: Text('×${a['count']}',
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
              onTap: () {
                Navigator.pop(c);
                setState(() {
                  _inboxFilter = 4;
                  _inboxConv = '${a['title']}';
                });
              },
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  /// 点一条消息：看全文 + 可以直接收入待办
  void _showMessageDetail(Map<String, dynamic> m) {
    final bool alerted = m['alerted'] == true;
    final int lv = (m['level'] as num?)?.toInt() ?? _kGeneral;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 4,
            bottom: MediaQuery.of(c).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: alerted ? _levelColor(lv) : const Color(0xFFD3D9E3),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${_appName('${m['pkg'] ?? ''}')} · ${m['title'] ?? ''}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            Text(_fmtTime(m['time']),
                style: const TextStyle(fontSize: 11, color: Colors.black38)),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFF5F7FB), borderRadius: BorderRadius.circular(10)),
            child: SelectableText('${m['text'] ?? ''}',
                style: const TextStyle(fontSize: 13.5, height: 1.6)),
          ),
          const SizedBox(height: 10),
          Text('为什么这样处理：${m['reason'] ?? '—'}',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A93A5), height: 1.5)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('关闭'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    await _ch.invokeMethod('addTodo', {
                      'title': '${m['title'] ?? ''}',
                      'text': '${m['text'] ?? ''}',
                      'pkg': '${m['pkg'] ?? ''}',
                      'kw': '${m['kw'] ?? ''}',
                    });
                  } catch (_) {}
                  if (c.mounted) Navigator.pop(c);
                  _refresh();
                },
                icon: const Icon(Icons.inbox_rounded, size: 18),
                label: const Text('收入待办'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _clearInboxAsk() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空收到的消息？'),
        content: const Text('只会清掉这份统计列表；待办和过滤规则不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) await _clearInbox();
  }

  Widget _buildInbox() {
    final alerted = _inbox.where((m) => m['alerted'] == true).length;
    final muted = _inbox.where((m) => m['muted'] == true).length;
    final groups = _inbox.where((m) => m['isGroup'] == true).length;
    final chats = _inbox.map((m) => '${m['title']}').toSet().length;
    final shown = _inboxShown;

    return ListView(children: [
      _card(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.forum_rounded, size: 18, color: _cGeneral),
            const SizedBox(width: 8),
            Text('一共收到 ${_inbox.length} 条',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(
              onPressed: _inbox.isEmpty ? null : _clearInboxAsk,
              child: const Text('清空', style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 2),
          _note('测试期专用：不管那条消息重不重要、有没有弹卡片、有没有进待办，这里都留一份。'
              '不用盯着屏幕，回头翻这一页就知道一共收到了多少、都是什么。'),
          const SizedBox(height: 14),
          Row(children: [
            _statCol('弹过卡片', alerted, _cUrgent,
                () => setState(() => _inboxFilter = 1)),
            _statCol('被静音', muted, const Color(0xFF6B7280),
                () => setState(() => _inboxFilter = 2)),
            _statCol('来自群', groups, _cGeneral,
                () => setState(() => _inboxFilter = 3)),
            _statCol('会话数', chats, const Color(0xFF7C4DFF), _showConversations),
          ]),
          if (_inbox.isNotEmpty) ...[
            const SizedBox(height: 10),
            _note('最早 ${_fmtTime(_inbox.last['time'])} · 最近 ${_fmtTime(_inbox.first['time'])}'),
          ],
        ]),
      ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(spacing: 6, runSpacing: 4, children: [
          for (final f in const [
            ['全部', 0],
            ['弹过卡', 1],
            ['被静音', 2],
            ['群消息', 3],
          ])
            ChoiceChip(
              label: Text('${f[0]}', style: const TextStyle(fontSize: 12)),
              selected: _inboxFilter == f[1],
              onSelected: (_) => setState(() {
                _inboxFilter = f[1] as int;
                _inboxConv = '';
              }),
              visualDensity: VisualDensity.compact,
            ),
          if (_inboxFilter == 4)
            InputChip(
              label: Text('只看「$_inboxConv」', style: const TextStyle(fontSize: 12)),
              onDeleted: () => setState(() {
                _inboxFilter = 0;
                _inboxConv = '';
              }),
              visualDensity: VisualDensity.compact,
            ),
        ]),
      ),

      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Text(_inbox.isEmpty ? '还没收到任何消息' : '这个筛选下没有消息',
                style: const TextStyle(color: Colors.black38)),
          ),
        )
      else
        for (final m in shown)
          Builder(builder: (_) {
            final bool muted = m['muted'] == true;
            final bool alerted = m['alerted'] == true;
            final bool isGroup = m['isGroup'] == true;
            final int lv = (m['level'] as num?)?.toInt() ?? _kGeneral;
            final String app = _appName('${m['pkg'] ?? ''}');
            final int cnt = (m['count'] as num?)?.toInt() ?? 1;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                dense: true,
                onTap: () => _showMessageDetail(m),
                leading: Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: alerted ? _levelColor(lv) : const Color(0xFFD3D9E3),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Row(children: [
                  Expanded(
                    child: Text('$app · ${m['title'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  if (cnt > 1) _badge('×$cnt', const Color(0xFFEEEFF3), const Color(0xFF6B7280)),
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
      appBar: AppBar(
          title: Text(_tab == 0 ? 'Nooti 监听' : (_tab == 1 ? '收到的消息' : '待办'))),
      body: IndexedStack(
          index: _tab, children: [_buildMonitor(), _buildInbox(), _buildTodo()]),
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
              isLabelVisible: _inbox.isNotEmpty,
              label: Text('${_inbox.length}'),
              child: const Icon(Icons.forum_outlined),
            ),
            selectedIcon: const Icon(Icons.forum_rounded),
            label: '消息',
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
    );
  }
}
