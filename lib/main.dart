import 'dart:async';
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
      title: 'Nooti 监听验证器',
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
  bool _enabled = false;
  List<Map<String, dynamic>> _items = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    bool enabled = false;
    List<Map<String, dynamic>> items = const [];
    try {
      enabled = await _ch.invokeMethod<bool>('isEnabled') ?? false;
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
      _items = items;
    });
  }

  Future<void> _openSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nooti 监听验证器')),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _enabled
                ? '保持这个页面开着，让微信（包括开了免打扰的群）来一条消息。下面实时冒出来＝监听成功；带「免打扰」标签的就是免打扰群的消息。'
                : '点「去开启」，在系统列表里找到 Nooti监听 并打开开关，再回到这个页面。',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Text('还没有抓到任何通知', style: TextStyle(color: Colors.black38)))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (c, i) {
                    final m = _items[i];
                    final bool silent = m['silent'] == true;
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
                          if (silent)
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFECFE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('免打扰',
                                  style:
                                      TextStyle(fontSize: 10, color: Color(0xFF7C6BF0))),
                            ),
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
