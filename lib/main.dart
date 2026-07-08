import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wireguard_flutter_plus/wireguard_flutter_plus.dart';

void main() => runApp(const PistachioVpnApp());

class PistachioVpnApp extends StatelessWidget {
  const PistachioVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pistachio VPN',
      theme: ThemeData(fontFamily: 'Vazirmatn'),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: PistachioVpnScreen(),
      ),
    );
  }
}

enum VpnState { disconnected, connecting, connected, disconnecting }

// ---- Design tokens ----
const Color kBg1 = Color(0xFF24402F);
const Color kBg2 = Color(0xFF16261F);
const Color kSurface = Color(0xFF1F3529);
const Color kLeafGreen = Color(0xFF7FB069);
const Color kLeafGreenHi = Color(0xFFA9CB84);
const Color kLeafYellow = Color(0xFFC9A24B);
const Color kLeafYellowHi = Color(0xFFDCB86C);
const Color kTrunk = Color(0xFF5B4029);
const Color kGold = Color(0xFFE3B23C);
const Color kCoral = Color(0xFFE07A5F);
const Color kCream = Color(0xFFF4EDE0);
const Color kMuted = Color(0xFFB9C2AE);

const String kPrefsConfigKey = 'wg_config';
const String kInterfaceName = 'wg0';
const String kProviderBundleId = 'com.example.pistachio_vpn';

class LeafSpec {
  final double cx, cy, r;
  const LeafSpec(this.cx, this.cy, this.r);
}

class PistachioCluster {
  final double x, y;
  final int n;
  final int delayMs;
  const PistachioCluster(this.x, this.y, this.n, this.delayMs);
}

const List<LeafSpec> leafClusters = [
  LeafSpec(150, 92, 46),
  LeafSpec(104, 108, 38),
  LeafSpec(198, 108, 38),
  LeafSpec(128, 68, 34),
  LeafSpec(174, 68, 34),
  LeafSpec(150, 130, 40),
  LeafSpec(84, 138, 26),
  LeafSpec(218, 138, 26),
  LeafSpec(150, 56, 24),
];

const List<PistachioCluster> pistachioClusters = [
  PistachioCluster(118, 96, 3, 0),
  PistachioCluster(168, 88, 2, 60),
  PistachioCluster(140, 118, 3, 120),
  PistachioCluster(96, 122, 2, 180),
  PistachioCluster(196, 118, 2, 90),
  PistachioCluster(150, 74, 2, 150),
  PistachioCluster(210, 96, 2, 40),
  PistachioCluster(88, 96, 2, 200),
];

class PistachioVpnScreen extends StatefulWidget {
  const PistachioVpnScreen({super.key});

  @override
  State<PistachioVpnScreen> createState() => _PistachioVpnScreenState();
}

class _PistachioVpnScreenState extends State<PistachioVpnScreen>
    with TickerProviderStateMixin {
  VpnState _state = VpnState.disconnected;
  int _seconds = 0;
  Timer? _ticker;

  late final AnimationController _swayController;
  late final AnimationController _pulseController;

  final wireguard = WireGuardFlutter.instance;
  StreamSubscription? _stageSub;
  String _config = '';
  bool _initialized = false;
  bool _busyToggle = false;

  @override
  void initState() {
    super.initState();
    _swayController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 5500))
          ..repeat(reverse: true);
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
          ..repeat();

    _loadConfig();
    _initWireguard();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _config = prefs.getString(kPrefsConfigKey) ?? '';
    });
  }

  Future<void> _initWireguard() async {
    try {
      await wireguard.initialize(interfaceName: kInterfaceName, vpnName: 'Pistachio VPN');
      _initialized = true;
      _stageSub = wireguard.vpnStageSnapshot.listen((event) {
        final mapped = _mapStage(event.toString());
        if (!mounted) return;
        setState(() => _state = mapped);
        if (mapped == VpnState.connected) {
          _startTimer();
        } else if (mapped == VpnState.disconnected) {
          _stopTimer();
        }
      });
    } catch (e) {
      debugPrint('wireguard init failed: $e');
    }
  }

  VpnState _mapStage(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('disconnecting')) return VpnState.disconnecting;
    if (s.contains('connecting')) return VpnState.connecting;
    if (s.contains('connected')) return VpnState.connected;
    return VpnState.disconnected;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stageSub?.cancel();
    _swayController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _ticker?.cancel();
    _seconds = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  void _stopTimer() {
    _ticker?.cancel();
    if (mounted) setState(() => _seconds = 0);
  }

  String? _extractEndpoint(String conf) {
    final match = RegExp(r'Endpoint\s*=\s*(\S+)', caseSensitive: false).firstMatch(conf);
    return match?.group(1);
  }

  Future<void> _handleToggle() async {
    if (_busyToggle) return;

    if (_state == VpnState.disconnected) {
      if (_config.trim().isEmpty) {
        _showSnack('اول کانفیگ WireGuard رو وارد کن');
        _openSettings();
        return;
      }
      final endpoint = _extractEndpoint(_config);
      if (endpoint == null) {
        _showSnack('کانفیگ نامعتبره — خط Endpoint پیدا نشد');
        return;
      }
      setState(() => _busyToggle = true);
      try {
        if (!_initialized) await _initWireguard();
        await wireguard.startVpn(
          serverAddress: endpoint,
          wgQuickConfig: _config,
          providerBundleIdentifier: kProviderBundleId,
        );
      } catch (e) {
        _showSnack('اتصال ناموفق بود: $e');
      }
      setState(() => _busyToggle = false);
    } else if (_state == VpnState.connected) {
      setState(() => _busyToggle = true);
      try {
        await wireguard.stopVpn();
      } catch (e) {
        _showSnack('قطع اتصال ناموفق بود: $e');
      }
      setState(() => _busyToggle = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openSettings() async {
    final controller = TextEditingController(text: _config);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('کانفیگ WireGuard',
                  style: TextStyle(color: kCream, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                'کل محتوای فایل .conf که سرور برات ساخته رو اینجا پیست کن.',
                style: TextStyle(color: kMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 10,
                style: const TextStyle(color: kCream, fontFamily: 'monospace', fontSize: 12),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.25),
                  hintText: '[Interface]\nPrivateKey = ...\nAddress = ...\n\n[Peer]\nPublicKey = ...\nEndpoint = your.server:51820\nAllowedIPs = 0.0.0.0/0',
                  hintStyle: const TextStyle(color: kMuted, fontSize: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: kBg2,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(ctx, controller.text),
                  child: const Text('ذخیره', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefsConfigKey, result);
      setState(() => _config = result);
      _showSnack('کانفیگ ذخیره شد');
    }
  }

  bool get _busy =>
      _busyToggle || _state == VpnState.connecting || _state == VpnState.disconnecting;
  bool get _grown => _state == VpnState.connected;

  Color get _leafColor =>
      _state == VpnState.connected ? kLeafGreen : (_state == VpnState.connecting ? kLeafGreen.withOpacity(0.7) : kLeafYellow);
  Color get _leafHi =>
      _state == VpnState.connected ? kLeafGreenHi : (_state == VpnState.connecting ? kLeafGreenHi.withOpacity(0.7) : kLeafYellowHi);

  String get _statusText => switch (_state) {
        VpnState.disconnected => 'قطع',
        VpnState.connecting => 'در حال اتصال…',
        VpnState.connected => 'متصل',
        VpnState.disconnecting => 'در حال قطع…',
      };

  Color get _statusColor => switch (_state) {
        VpnState.disconnected => kCoral,
        VpnState.connecting => kGold,
        VpnState.connected => kLeafGreen,
        VpnState.disconnecting => kGold,
      };

  String get _buttonLabel => switch (_state) {
        VpnState.disconnected => 'اتصال',
        VpnState.connecting => 'در حال اتصال…',
        VpnState.connected => 'قطع اتصال',
        VpnState.disconnecting => 'در حال قطع…',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.5),
            radius: 1.1,
            colors: [kBg1, kBg2],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: 360,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 40,
                        offset: const Offset(0, 20)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 36),
                        Expanded(child: Center(child: _buildStatusBadge())),
                        IconButton(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.settings, color: kMuted, size: 20),
                          tooltip: 'تنظیمات',
                        ),
                      ],
                    ),
                    _buildTree(),
                    const SizedBox(height: 4),
                    _buildTimer(),
                    const SizedBox(height: 18),
                    _buildButton(),
                    const SizedBox(height: 18),
                    _buildInfoRow(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _statusColor,
              shape: BoxShape.circle,
              boxShadow: _grown
                  ? [BoxShadow(color: _statusColor, blurRadius: 8)]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(_statusText,
              style: const TextStyle(
                  color: kCream, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTree() {
    return SizedBox(
      width: 300,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(300, 240),
            painter: _TrunkPainter(),
          ),

          if (_grown)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(300, 240),
                  painter: _PulsePainter(_pulseController.value),
                );
              },
            ),

          if (_state == VpnState.connecting)
            Positioned(
              top: 20,
              child: SizedBox(
                width: 116,
                height: 116,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kGold.withOpacity(0.7),
                ),
              ),
            ),

          AnimatedBuilder(
            animation: _swayController,
            builder: (context, child) {
              final angle = (_swayController.value - 0.5) * 0.02;
              return Transform.rotate(
                angle: angle,
                alignment: const Alignment(0, 0.75),
                child: child,
              );
            },
            child: SizedBox(
              width: 300,
              height: 240,
              child: Stack(
                children: [
                  ...leafClusters.asMap().entries.map((e) {
                    final i = e.key;
                    final leaf = e.value;
                    final color = i % 3 == 0 ? _leafHi : _leafColor;
                    return Positioned(
                      left: leaf.cx - leaf.r,
                      top: leaf.cy - leaf.r,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 900),
                        width: leaf.r * 2,
                        height: leaf.r * 2,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                  ..._buildPistachios(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPistachios() {
    final widgets = <Widget>[];
    int i = 0;
    for (final cluster in pistachioClusters) {
      for (int ni = 0; ni < cluster.n; ni++) {
        final x = cluster.x + ni * 7 - (cluster.n - 1) * 3.5;
        final y = cluster.y + (ni % 2 == 0 ? 0.0 : 5.0);
        final delay = cluster.delayMs + ni * 40;
        widgets.add(_Pistachio(
          key: ValueKey('pistachio-$i'),
          x: x,
          y: y,
          index: i,
          grown: _grown,
          falling: _state == VpnState.disconnecting,
          delayMs: delay,
        ));
        i++;
      }
    }
    return widgets;
  }

  Widget _buildTimer() {
    return Column(
      children: [
        const Text('مدت اتصال', style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 2),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            _fmt(_seconds),
            style: const TextStyle(
              color: kCream,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(int s) {
    final h = (s ~/ 3600).toString().padLeft(2, '0');
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$h:$m:$sec';
  }

  Widget _buildButton() {
    final isConnected = _state == VpnState.connected;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _busy ? null : _handleToggle,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: isConnected ? kCoral : kGold,
          disabledBackgroundColor: (isConnected ? kCoral : kGold).withOpacity(0.75),
          foregroundColor: isConnected ? kCream : kBg2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 6,
        ),
        child: Text(_buttonLabel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildInfoRow() {
    return Row(
      children: [
        Expanded(child: _infoCard('حجم باقی‌مانده', '۴۲.۵ گیگابایت')),
        const SizedBox(width: 10),
        Expanded(child: _infoCard('تاریخ انقضا', '۱۴۰۴/۰۶/۱۵')),
      ],
    );
  }

  Widget _infoCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: kCream, fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _TrunkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final soilPaint = Paint()..color = const Color(0xFF0F1B15).withOpacity(0.6);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(150, 222), width: 180, height: 20),
        soilPaint);

    final soilPaint2 = Paint()..color = const Color(0xFF3A2C1D).withOpacity(0.5);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(150, 219), width: 140, height: 14),
        soilPaint2);

    final trunkPaint = Paint()
      ..color = kTrunk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final trunkPath = Path()
      ..moveTo(150, 210)
      ..cubicTo(148, 190, 146, 175, 148, 160)
      ..cubicTo(149, 150, 151, 145, 150, 135);
    canvas.drawPath(trunkPath, trunkPaint);

    final branchPaint = Paint()
      ..color = kTrunk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    final branchPath = Path()
      ..moveTo(150, 160)
      ..cubicTo(138, 150, 122, 148, 112, 140);
    final branchPath2 = Path()
      ..moveTo(150, 150)
      ..cubicTo(164, 142, 178, 140, 190, 132);
    canvas.drawPath(branchPath, branchPaint);
    canvas.drawPath(branchPath2, branchPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PulsePainter extends CustomPainter {
  final double t;
  _PulsePainter(this.t);

  void _ring(Canvas canvas, double phase) {
    final local = (t + phase) % 1.0;
    final scale = 1.0 + local * 1.6;
    final opacity = (1.0 - local).clamp(0.0, 1.0) * 0.55;
    final paint = Paint()
      ..color = kLeafGreen.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(150, 219), width: 40 * scale, height: 8 * scale),
        paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ring(canvas, 0.0);
    _ring(canvas, 0.5);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) => oldDelegate.t != t;
}

class _Pistachio extends StatefulWidget {
  final double x, y;
  final int index;
  final bool grown;
  final bool falling;
  final int delayMs;

  const _Pistachio({
    super.key,
    required this.x,
    required this.y,
    required this.index,
    required this.grown,
    required this.falling,
    required this.delayMs,
  });

  @override
  State<_Pistachio> createState() => _PistachioState();
}

class _PistachioState extends State<_Pistachio> {
  double _dy = 0;
  double _rotation = 0;
  double _opacity = 0;
  double _scale = 0;

  @override
  void didUpdateWidget(covariant _Pistachio old) {
    super.didUpdateWidget(old);
    _applyState();
  }

  @override
  void initState() {
    super.initState();
    _applyState();
  }

  void _applyState() {
    final angle = ((widget.index * 47) % 40 - 20) * math.pi / 180;
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (!mounted) return;
      setState(() {
        if (widget.falling) {
          _dy = 130;
          _rotation = angle + math.pi / 3;
          _opacity = 0;
          _scale = 1;
        } else if (widget.grown) {
          _dy = 0;
          _rotation = angle;
          _opacity = 1;
          _scale = 1;
        } else {
          _dy = 0;
          _rotation = 0;
          _opacity = 0;
          _scale = 0;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.x - 6,
      top: widget.y - 8,
      child: AnimatedSlide(
        duration: Duration(milliseconds: widget.falling ? 900 : 480),
        curve: widget.falling ? Curves.easeIn : Curves.elasticOut,
        offset: Offset(0, _dy / 24),
        child: AnimatedOpacity(
          duration: Duration(milliseconds: widget.falling ? 700 : 380),
          opacity: _opacity,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 480),
            scale: _scale,
            child: Transform.rotate(
              angle: _rotation,
              child: const _PistachioIcon(),
            ),
          ),
        ),
      ),
    );
  }
}

class _PistachioIcon extends StatelessWidget {
  const _PistachioIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 16,
      child: CustomPaint(painter: _PistachioPainter()),
    );
  }
}

class _PistachioPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final shellPaint = Paint()..color = const Color(0xFFE7DCC2);
    final strokePaint = Paint()
      ..color = const Color(0xFFB79A6B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    final kernelPaint = Paint()..color = const Color(0xFF8CA34C);
    final blushPaint = Paint()..color = const Color(0xFFD98E82).withOpacity(0.75);

    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawOval(
        Rect.fromCenter(center: center, width: size.width, height: size.height),
        shellPaint);
    canvas.drawOval(
        Rect.fromCenter(center: center, width: size.width, height: size.height),
        strokePaint);
    canvas.drawOval(
        Rect.fromCenter(
            center: center.translate(-1.6, 0), width: 4, height: size.height - 4),
        kernelPaint);
    canvas.drawOval(
        Rect.fromCenter(
            center: center.translate(-3.4, -4), width: 4.8, height: 6),
        blushPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
