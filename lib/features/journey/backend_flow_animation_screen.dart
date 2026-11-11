import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Interactive 60-FPS Backend Flow & ML vs. Non-ML Path Tracing Animator Screen.
///
/// Designed for live academic/lecturer demonstrations of:
/// 1. Path Tracing in GPS Blackout: Without ML (Pure IMU Dead Reckoning) vs. With ML (EKF + Drift Predictor)
/// 2. Travelling Salesman / Route Graph Optimization: Shortest Path vs. Bayesian AI Safety-Weighted Graph
/// 3. Full End-to-End Backend Architecture Packet Flow
class BackendFlowAnimationScreen extends StatefulWidget {
  const BackendFlowAnimationScreen({super.key});

  @override
  State<BackendFlowAnimationScreen> createState() =>
      _BackendFlowAnimationScreenState();
}

enum _SimTab { pathTracing, tspGraph, architecture }

enum _MlCompareMode { withoutMl, withMl, compareBoth }

class _BackendFlowAnimationScreenState extends State<BackendFlowAnimationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  _SimTab _currentTab = _SimTab.pathTracing;
  _MlCompareMode _mlMode = _MlCompareMode.compareBoth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _restart() {
    _controller.forward(from: 0.0);
    _controller.repeat();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xff0f172a),
      appBar: AppBar(
        backgroundColor: const Color(0xff0f172a),
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backend Flow & ML Animator',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Without ML vs. With ML Path Tracing & TSP Graph',
              style: TextStyle(fontSize: 11, color: Color(0xff94a3b8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _controller.isAnimating ? 'Pause' : 'Play',
            icon: Icon(
              _controller.isAnimating
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
            onPressed: () {
              setState(() {
                if (_controller.isAnimating) {
                  _controller.stop();
                } else {
                  _controller.repeat();
                }
              });
            },
          ),
          IconButton(
            tooltip: 'Restart Animation',
            icon: const Icon(Icons.replay),
            onPressed: _restart,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value; // 0.0 to 1.0
          return ListView(
            padding: EdgeInsets.fromLTRB(14, 8, 14, 24 + bottomInset),
            children: [
              // 1. Scene Selector Tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabChip(
                      tab: _SimTab.pathTracing,
                      icon: Icons.timeline,
                      label: '1. ML Path Tracing (GPS Outage)',
                    ),
                    const SizedBox(width: 8),
                    _buildTabChip(
                      tab: _SimTab.tspGraph,
                      icon: Icons.hub_outlined,
                      label: '2. TSP / Safe Route Graph',
                    ),
                    const SizedBox(width: 8),
                    _buildTabChip(
                      tab: _SimTab.architecture,
                      icon: Icons.account_tree_outlined,
                      label: '3. Backend Dataflow',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 2. ML Mode Toggle Bar
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xff1e293b),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xff334155)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildModeButton(
                        mode: _MlCompareMode.withoutMl,
                        label: 'Without ML',
                        activeColor: const Color(0xffef4444),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildModeButton(
                        mode: _MlCompareMode.withMl,
                        label: 'With ML ON',
                        activeColor: const Color(0xff22c55e),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildModeButton(
                        mode: _MlCompareMode.compareBoth,
                        label: 'Compare Both',
                        activeColor: const Color(0xff3b82f6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 3. Interactive Animated Canvas Card
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xff111827),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xff334155)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      color: const Color(0xff1e293b),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _sceneSubtitle(progress),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff0f172a),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xff334155),
                              ),
                            ),
                            child: Text(
                              't = ${(progress * 42.0).toStringAsFixed(1)}s',
                              style: const TextStyle(
                                color: Color(0xff38bdf8),
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 270,
                      child: CustomPaint(
                        painter: _BackendAnimationPainter(
                          tab: _currentTab,
                          mlMode: _mlMode,
                          progress: progress,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      color: const Color(0xff0f172a),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: const [
                          _LegendDot(
                            color: Color(0xff94a3b8),
                            label: 'Ground Truth Road',
                          ),
                          _LegendDot(
                            color: Color(0xffef4444),
                            label: 'Without ML (Drifts / Unsafe)',
                          ),
                          _LegendDot(
                            color: Color(0xff22c55e),
                            label: 'With ML (Corrected / Safe Tour)',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 4. Live Comparison Telemetry Metrics
              _buildMetricsRow(progress),
              const SizedBox(height: 12),

              // 5. Active Backend Execution Pipeline Steps
              _buildPipelineCard(progress),
              const SizedBox(height: 12),

              // 6. Mathematical Formulation Card for Lecturer
              _buildMathCard(),
            ],
          );
        },
      ),
    );
  }

  String _sceneSubtitle(double p) {
    switch (_currentTab) {
      case _SimTab.pathTracing:
        return p <= 0.28
            ? '📡 Open Sky: GPS 1Hz + IMU 40Hz Calibrating EKF'
            : '⚡ GPS Blackout Tunnel: Comparing ML vs. Raw IMU Drift';
      case _SimTab.tspGraph:
        return '🛡️ Graph Search: Shortest Distance vs. Bayesian Hazard Cost';
      case _SimTab.architecture:
        return '🔄 Real-Time Sensor & Hazard Packet Pipeline';
    }
  }

  Widget _buildTabChip({
    required _SimTab tab,
    required IconData icon,
    required String label,
  }) {
    final selected = _currentTab == tab;
    return InkWell(
      onTap: () => setState(() => _currentTab = tab),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff2563eb) : const Color(0xff1e293b),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xff60a5fa) : const Color(0xff334155),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required _MlCompareMode mode,
    required String label,
    required Color activeColor,
  }) {
    final active = _mlMode == mode;
    return InkWell(
      onTap: () => setState(() => _mlMode = mode),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xff94a3b8),
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsRow(double progress) {
    final inOutage = progress > 0.28;
    final b = inOutage ? (progress - 0.28) / 0.72 : 0.0;

    final String m1Title;
    final String m1Val;
    final String m2Title;
    final String m2Val;
    final String m3Title;
    final String m3Val;

    if (_currentTab == _SimTab.pathTracing) {
      m1Title = 'Without ML Error';
      m1Val = inOutage
          ? '${(b * b * 146.3).toStringAsFixed(1)} m'
          : '1.2 m';
      m2Title = 'With ML Error';
      m2Val = inOutage ? '${(b * 56.5).toStringAsFixed(1)} m' : '0.8 m';
      m3Title = 'Drift Reduction';
      m3Val = '+61.4%';
    } else {
      m1Title = 'No-ML Shortest';
      m1Val = '9.0km (91% Risk)';
      m2Title = 'AI Safe Route';
      m2Val = '10.8km (89/100)';
      m3Title = 'Blackspots Avoided';
      m3Val = '2 Hazards';
    }

    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            label: m1Title,
            value: m1Val,
            valueColor: const Color(0xffef4444),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricTile(
            label: m2Title,
            value: m2Val,
            valueColor: const Color(0xff22c55e),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricTile(
            label: m3Title,
            value: m3Val,
            valueColor: const Color(0xff38bdf8),
          ),
        ),
      ],
    );
  }

  Widget _buildPipelineCard(double progress) {
    final List<({String title, String badge, String desc})> steps;
    if (_currentTab == _SimTab.pathTracing) {
      if (_mlMode == _MlCompareMode.withoutMl) {
        steps = const [
          (
            title: '1. Raw 40Hz IMU Stream',
            badge: 'Accel + Gyro',
            desc: 'Reads body-frame (ax, ay, az) and angular rates (gx, gy, gz)',
          ),
          (
            title: '2. NED Attitude Rotation',
            badge: 'DCM Matrix',
            desc: 'Rotates specific force to North-East-Down frame & subtracts gravity',
          ),
          (
            title: '3. Uncorrected Double Integration',
            badge: 'Quadratic Drift',
            desc: 'p = p + v·dt + ½a·dt² → Sensor bias explodes quadratically!',
          ),
          (
            title: '4. Off-Road Path Divergence',
            badge: '146.3m Error',
            desc: 'Without ML residual correction, vehicle trace drifts 146.3m off-road',
          ),
        ];
      } else {
        steps = const [
          (
            title: '1. Synchronized Sensor Pre-Processor',
            badge: '40Hz → 10Hz',
            desc: 'Aligns 9-axis IMU telemetry with last known GPS anchor',
          ),
          (
            title: '2. 16-D Kinematic Feature Extractor',
            badge: '16 Features',
            desc: 'Computes ||a||₂, jerk da/dt, ||ω||₂, inertial speed, yaw angle ψ',
          ),
          (
            title: '3. 6-State EKF + ZUPT Filter',
            badge: 'x ∈ ℝ⁶',
            desc: 'Tracks [p_N, p_E, v_N, v_E, ψ, b_ω] and clamps stationary drift',
          ),
          (
            title: '4. Deep Stacking / Ridge ML Predictor',
            badge: '+61.4% Acc',
            desc: 'Predicts step drift (ΔEast, ΔNorth) & locks trajectory to road',
          ),
        ];
      }
    } else {
      steps = const [
        (
          title: '1. Candidate Route Graph Builder',
          badge: 'OSRM / Google',
          desc: 'Extracts road nodes V and segment edges E with polylines',
        ),
        (
          title: '2. 6-Layer Hazard Telemetry Fusion',
          badge: 'Live APIs',
          desc: 'Fuses Traffic, Open-Meteo Rain, BBMP Flood & MoRTH Blackspots',
        ),
        (
          title: '3. Naive Bayesian Risk Posterior',
          badge: 'P(Hazard|E)',
          desc: 'Updates 5% base prior with 6 conditional likelihood ratios L(E_i)',
        ),
        (
          title: '4. Safety-Weighted Graph / TSP Solver',
          badge: 'S→B→D→E',
          desc: 'Re-weights edge costs W = d × (1 + λ·Risk) to bypass Flood & Accident nodes',
        ),
      ];
    }

    final activeIdx = (progress * steps.length).floor().clamp(0, steps.length - 1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff1e293b),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVE BACKEND EXECUTION PIPELINE',
            style: TextStyle(
              color: Color(0xff94a3b8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: i == activeIdx
                    ? const Color(0xff2563eb).withValues(alpha: 0.18)
                    : const Color(0xff0f172a),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: i == activeIdx
                      ? const Color(0xff3b82f6)
                      : const Color(0xff334155),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          steps[i].title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        steps[i].badge,
                        style: TextStyle(
                          color: i == activeIdx
                              ? const Color(0xff38bdf8)
                              : const Color(0xff64748b),
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    steps[i].desc,
                    style: const TextStyle(
                      color: Color(0xff94a3b8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMathCard() {
    final formula = _currentTab == _SimTab.pathTracing
        ? '• Without ML (DeadReckoningEngine):\n'
          '  v(t+dt) = (v(t) + a_NED·dt)·0.98  ⇒  Error ∝ ½·b_ω·t² (146.3m)\n\n'
          '• With ML (EKF + Deep Stacking / Ridge Predictor):\n'
          '  [Δx̂, Δŷ] = Stacking(MLP₁₂₈₋₆₄₋₃₂(X₁₆), GBDT₄₀(X₁₆))\n'
          '  p_corrected = p_EKF + clamp([Δx̂, Δŷ], ±2.0m)  ⇒  56.5m (+61.4%)'
        : '• Without ML (Standard Shortest Path / TSP):\n'
          '  min ∑ d(u, v)  ⇒  Picks S→A→C→E (Hits Severe Flood & Blackspot)\n\n'
          '• With AI Bayesian Safety Engine:\n'
          '  O(Hazard|E) = O(Prior) × ∏ L(E_i)\n'
          '  W_AI(u, v) = d(u, v) × (1 + λ·P(Hazard|E))  ⇒  Picks Safe S→B→D→E';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff090d16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MATHEMATICAL FORMULATION (FOR LECTURER VIVA)',
            style: TextStyle(
              color: Color(0xff94a3b8),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formula,
            style: const TextStyle(
              color: Color(0xff38bdf8),
              fontSize: 11,
              fontFamily: 'monospace',
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xff1e293b),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xff334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xff94a3b8), fontSize: 10.5),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: Color(0xff94a3b8), fontSize: 11),
        ),
      ],
    );
  }
}

class _BackendAnimationPainter extends CustomPainter {
  _BackendAnimationPainter({
    required this.tab,
    required this.mlMode,
    required this.progress,
  });

  final _SimTab tab;
  final _MlCompareMode mlMode;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    switch (tab) {
      case _SimTab.pathTracing:
        _paintPathTracing(canvas, size);
      case _SimTab.tspGraph:
        _paintTspGraph(canvas, size);
      case _SimTab.architecture:
        _paintArchitecture(canvas, size);
    }
  }

  void _paintPathTracing(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final blackoutX = w * 0.30;

    // 1. Highlight GPS Blackout Zone
    final blackoutPaint = Paint()
      ..color = const Color(0xffef4444).withValues(alpha: 0.08);
    canvas.drawRect(
      Rect.fromLTWH(blackoutX, 0, w - blackoutX, h),
      blackoutPaint,
    );

    final dividerPaint = Paint()
      ..color = const Color(0xffef4444).withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    for (double y = 0; y < h; y += 10) {
      canvas.drawLine(Offset(blackoutX, y), Offset(blackoutX, y + 5), dividerPaint);
    }

    _drawText(
      canvas,
      'GPS LOCK (1Hz)',
      const Offset(12, 10),
      const Color(0xff22c55e),
      10,
    );
    _drawText(
      canvas,
      '⚡ 30s GPS BLACKOUT ZONE (TUNNEL)',
      Offset(blackoutX + 10, 10),
      const Color(0xffef4444),
      10,
    );

    // 2. Generate trajectories
    const totalPts = 80;
    final gtPts = <Offset>[];
    final drPts = <Offset>[];
    final mlPts = <Offset>[];

    for (var i = 0; i <= totalPts; i++) {
      final u = i / totalPts;
      final x = 20 + u * (w - 40);
      final y = h * 0.54 + math.sin(u * math.pi * 2.0) * (h * 0.25);
      gtPts.add(Offset(x, y));

      if (u <= 0.28) {
        drPts.add(Offset(x, y + math.sin(i.toDouble()) * 1.2));
        mlPts.add(Offset(x, y + math.cos(i.toDouble()) * 0.9));
      } else {
        final b = (u - 0.28) / 0.72;
        final driftX = -b * b * (w * 0.07);
        final driftY = -b * b * (h * 0.34) + math.sin(b * 6) * 5;
        drPts.add(Offset(x + driftX, y + driftY));

        final mlErrY = math.sin(b * math.pi * 3) * (4 * b) - b * 8;
        mlPts.add(Offset(x - b * 3, y + mlErrY));
      }
    }

    // Draw broad road asphalt
    final roadPaint = Paint()
      ..color = const Color(0xff94a3b8).withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    final roadPath = Path()..moveTo(gtPts.first.dx, gtPts.first.dy);
    for (final p in gtPts.skip(1)) {
      roadPath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(roadPath, roadPaint);

    // Draw ground truth centerline
    final gtPaint = Paint()
      ..color = const Color(0xff94a3b8).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(roadPath, gtPaint);

    final curIdx = (progress * totalPts).floor().clamp(0, totalPts);

    // Draw Without ML Path (Red)
    if (mlMode == _MlCompareMode.withoutMl ||
        mlMode == _MlCompareMode.compareBoth) {
      final drPaint = Paint()
        ..color = const Color(0xffef4444)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      final p = Path()..moveTo(drPts.first.dx, drPts.first.dy);
      for (var i = 1; i <= curIdx; i++) {
        p.lineTo(drPts[i].dx, drPts[i].dy);
      }
      canvas.drawPath(p, drPaint);
      canvas.drawCircle(
        drPts[curIdx],
        5.5,
        Paint()..color = const Color(0xffef4444),
      );
    }

    // Draw With ML Path (Green)
    if (mlMode == _MlCompareMode.withMl ||
        mlMode == _MlCompareMode.compareBoth) {
      final mlPaint = Paint()
        ..color = const Color(0xff22c55e)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      final p = Path()..moveTo(mlPts.first.dx, mlPts.first.dy);
      for (var i = 1; i <= curIdx; i++) {
        p.lineTo(mlPts[i].dx, mlPts[i].dy);
      }
      canvas.drawPath(p, mlPaint);
      canvas.drawCircle(
        mlPts[curIdx],
        5.5,
        Paint()..color = const Color(0xff22c55e),
      );
    }
  }

  void _paintTspGraph(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final nodes = <({String id, String label, Offset pos, Color color})>[
      (
        id: 'S',
        label: 'Start',
        pos: Offset(w * 0.10, h * 0.52),
        color: const Color(0xff3b82f6),
      ),
      (
        id: 'A',
        label: 'Flood Zone (0.90)',
        pos: Offset(w * 0.36, h * 0.24),
        color: const Color(0xffef4444),
      ),
      (
        id: 'B',
        label: 'Safe Hwy (0.12)',
        pos: Offset(w * 0.36, h * 0.80),
        color: const Color(0xff22c55e),
      ),
      (
        id: 'C',
        label: 'Blackspot (0.88)',
        pos: Offset(w * 0.66, h * 0.24),
        color: const Color(0xffef4444),
      ),
      (
        id: 'D',
        label: 'Ring Rd (0.14)',
        pos: Offset(w * 0.66, h * 0.80),
        color: const Color(0xff22c55e),
      ),
      (
        id: 'E',
        label: 'Dest',
        pos: Offset(w * 0.90, h * 0.52),
        color: const Color(0xff3b82f6),
      ),
    ];

    const edges = <(int, int)>[
      (0, 1),
      (0, 2),
      (1, 3),
      (1, 4),
      (2, 1),
      (2, 4),
      (3, 5),
      (4, 5),
    ];

    final edgePaint = Paint()
      ..color = const Color(0xff475569)
      ..strokeWidth = 2.0;
    for (final (u, v) in edges) {
      canvas.drawLine(nodes[u].pos, nodes[v].pos, edgePaint);
    }

    const noMlTour = [0, 1, 3, 5];
    const withMlTour = [0, 2, 4, 5];

    void drawTour(List<int> tour, Color color, double yOffset) {
      final segFloat = progress * (tour.length - 1);
      final curSeg = segFloat.floor().clamp(0, tour.length - 2);
      final frac = segFloat - curSeg;

      final p = Path();
      Offset carPos = nodes[tour.first].pos.translate(0, yOffset);
      for (var i = 0; i <= curSeg; i++) {
        final p1 = nodes[tour[i]].pos.translate(0, yOffset);
        final p2 = nodes[tour[i + 1]].pos.translate(0, yOffset);
        if (i == 0) p.moveTo(p1.dx, p1.dy);
        if (i < curSeg) {
          p.lineTo(p2.dx, p2.dy);
          carPos = p2;
        } else {
          final cx = p1.dx + (p2.dx - p1.dx) * frac;
          final cy = p1.dy + (p2.dy - p1.dy) * frac;
          p.lineTo(cx, cy);
          carPos = Offset(cx, cy);
        }
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
      canvas.drawCircle(carPos, 6, Paint()..color = color);
    }

    if (mlMode == _MlCompareMode.withoutMl ||
        mlMode == _MlCompareMode.compareBoth) {
      drawTour(noMlTour, const Color(0xffef4444), -3);
    }
    if (mlMode == _MlCompareMode.withMl ||
        mlMode == _MlCompareMode.compareBoth) {
      drawTour(withMlTour, const Color(0xff22c55e), 3);
    }

    for (final n in nodes) {
      canvas.drawCircle(n.pos, 13, Paint()..color = n.color);
      _drawText(
        canvas,
        n.id,
        n.pos.translate(-4, -6),
        Colors.white,
        11,
        bold: true,
      );
      _drawText(
        canvas,
        n.label,
        n.pos.translate(-34, n.pos.dy < h * 0.5 ? -28 : 16),
        const Color(0xffe2e8f0),
        10,
      );
    }
  }

  void _paintArchitecture(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final nodes = <({String title, Offset center, Color color})>[
      (
        title: 'IMU 40Hz',
        center: Offset(w * 0.16, h * 0.22),
        color: const Color(0xff3b82f6),
      ),
      (
        title: 'GPS 1Hz',
        center: Offset(w * 0.16, h * 0.52),
        color: const Color(0xff06b6d4),
      ),
      (
        title: 'Hazard APIs',
        center: Offset(w * 0.16, h * 0.82),
        color: const Color(0xfff59e0b),
      ),
      (
        title: '16-D Features',
        center: Offset(w * 0.50, h * 0.22),
        color: const Color(0xff8b5cf6),
      ),
      (
        title: '6-State EKF',
        center: Offset(w * 0.50, h * 0.52),
        color: const Color(0xff10b981),
      ),
      (
        title: 'Bayesian Risk',
        center: Offset(w * 0.50, h * 0.82),
        color: const Color(0xffec4899),
      ),
      (
        title: 'Stacking ML',
        center: Offset(w * 0.84, h * 0.35),
        color: const Color(0xff22c55e),
      ),
      (
        title: 'Safe Route UI',
        center: Offset(w * 0.84, h * 0.72),
        color: const Color(0xff38bdf8),
      ),
    ];

    const links = <(int, int)>[
      (0, 3),
      (0, 4),
      (1, 4),
      (3, 6),
      (4, 6),
      (6, 7),
      (2, 5),
      (5, 7),
    ];

    final linePaint = Paint()
      ..color = const Color(0xff334155)
      ..strokeWidth = 2.0;

    for (var i = 0; i < links.length; i++) {
      final (a, b) = links[i];
      final p1 = nodes[a].center;
      final p2 = nodes[b].center;
      canvas.drawLine(p1, p2, linePaint);

      final t = ((progress * 3.0 + i * 0.17) % 1.0);
      final pkt = Offset(
        p1.dx + (p2.dx - p1.dx) * t,
        p1.dy + (p2.dy - p1.dy) * t,
      );
      canvas.drawCircle(pkt, 4, Paint()..color = const Color(0xff38bdf8));
    }

    for (final n in nodes) {
      final rect = Rect.fromCenter(center: n.center, width: 92, height: 38);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(rrect, Paint()..color = const Color(0xff1e293b));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = n.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _drawText(
        canvas,
        n.title,
        n.center.translate(-36, -6),
        Colors.white,
        10.5,
        bold: true,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize, {
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _BackendAnimationPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.tab != tab ||
      oldDelegate.mlMode != mlMode;
}
