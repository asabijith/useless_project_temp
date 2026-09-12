import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';


import 'package:flutter/cupertino.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

void main() {
  runApp(const BiscuitProtectorApp());
}

class BiscuitProtectorApp extends StatelessWidget {
  const BiscuitProtectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Biscuit Protector',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF2F2F7), // iOS Grouped Background
        colorScheme: ColorScheme.fromSeed(seedColor: CupertinoColors.systemBlue),
        useMaterial3: true,
        fontFamily: '.SF Pro Text', // Native iOS font fallback
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: CupertinoColors.systemBlue),
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

// TickerProviderStateMixin enables AnimationControllers
class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  WebSocketChannel? channel;
  StreamSubscription? subscription;


  // ============================
  // ESP32 CONNECTION
  // ============================

  String esp32Ip = '10.11.240.216';

  String connectionStatus = 'Disconnected';

  // ============================
  // SENSOR VALUES
  // ============================

  double distance = 0.0;
  double temperature = 0.0;
  double humidity = 0.0;

  bool alert = false;

  String alertMessage = 'No one detected';

  Timer? _alertResetTimer;

  // Tracks the last time a REAL alert was confirmed (Arduino said 1, or d ≤ 15)
  // Used to keep showing ANGRY when sensor returns 999.0 (saturation = too close)
  int _lastConfirmedAlertMs = 0;

  // ============================
  // PREMIUM PLAN (RAZORPAY)
  // ============================
  late Razorpay _razorpay;
  bool isPremium = false;

  // ============================
  // EYE ANIMATION CONTROLLERS
  // ============================

  late AnimationController _blinkCtrl;
  late Animation<double> _blinkAnim;
  Timer? _blinkTimer;

  late AnimationController _lookCtrl;
  late Animation<Offset> _lookAnim;
  Timer? _lookTimer;
  Offset _lookCurrent = Offset.zero;

  late AnimationController _angryBlinkCtrl;
  late Animation<double> _angryBlinkAnim;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _setupRazorpay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      connectToESP32();
    });
  }

  void _setupRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    setState(() {
      isPremium = true;
    });
    _showCupertinoAlert(
      'Success! 🎉',
      'Anti-Ant Forcefield ACTIVATED! Your biscuits are completely safe from ants!',
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    _showCupertinoAlert(
      'Payment Failed',
      'Forcefield failed to activate. The ants are still a threat! (Error: ${response.message})',
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    _showCupertinoAlert('External Wallet', 'Please complete the payment in your wallet.');
  }

  void _showCupertinoAlert(String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
    );
  }

  void openCheckout() {
    var options = {
      'key': 'rzp_test_TateySDHEenCyl',
      'amount': 9900, // 99 INR
      'name': 'Biscuit Protector',
      'description': 'Anti-Ant Forcefield Premium Upgrade',
      'prefill': {
        'contact': '9876543210',
        'email': 'ant_hater@biscuit.com'
      }
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _cancelPremium() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Cancel Protection?'),
        content: const Text('Are you sure you want to cancel the Anti-Ant Forcefield? Your biscuits will be vulnerable to ants again!'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Keep it Safe'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Yes, Cancel'),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                isPremium = false;
              });
            },
          )
        ],
      ),
    );
  }

  void _setupAnimations() {
    // Normal blink: 140ms quick close-open
    _blinkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 140));
    _blinkAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 60),
    ]).animate(_blinkCtrl);

    _scheduleBlink();

    // Pupil look-around
    _lookCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _lookAnim = Tween<Offset>(begin: Offset.zero, end: Offset.zero)
        .animate(CurvedAnimation(parent: _lookCtrl, curve: Curves.easeInOut));
    _lookCtrl.addListener(() {
      if (mounted) setState(() => _lookCurrent = _lookAnim.value);
    });
    _scheduleLookAround();

    // Angry rapid blink: 280ms repeat
    _angryBlinkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _angryBlinkAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(_angryBlinkCtrl);
    _angryBlinkCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _scheduleBlink() {
    final delay = Duration(milliseconds: 2800 + Random().nextInt(2500));
    _blinkTimer?.cancel();
    _blinkTimer = Timer(delay, () {
      if (mounted && !alert) {
        _blinkCtrl.forward(from: 0.0).then((_) {
          if (mounted && !alert && Random().nextBool()) {
            // Natural occasional double-blink
            Timer(const Duration(milliseconds: 180), () {
              if (mounted && !alert) _blinkCtrl.forward(from: 0.0);
            });
          }
          _scheduleBlink();
        });
      } else {
        _scheduleBlink();
      }
    });
  }

  void _scheduleLookAround() {
    final delay = Duration(milliseconds: 1800 + Random().nextInt(2200));
    _lookTimer?.cancel();
    _lookTimer = Timer(delay, () {
      if (mounted && !alert) {
        final rand = Random();
        final dx = (rand.nextDouble() * 2 - 1) * 0.65;
        final dy = (rand.nextDouble() * 2 - 1) * 0.45;
        _lookAnim = Tween<Offset>(begin: _lookCurrent, end: Offset(dx, dy))
            .animate(
                CurvedAnimation(parent: _lookCtrl, curve: Curves.easeInOut));
        _lookCtrl.forward(from: 0.0);
      }
      _scheduleLookAround();
    });
  }

  void _startAngryBlink() => _angryBlinkCtrl.repeat();

  void _stopAngryBlink() {
    _angryBlinkCtrl.stop();
    _angryBlinkCtrl.value = 0.0;
    // Smoothly return pupils to center
    _lookAnim = Tween<Offset>(begin: _lookCurrent, end: Offset.zero)
        .animate(CurvedAnimation(parent: _lookCtrl, curve: Curves.easeOut));
    _lookCtrl.forward(from: 0.0);
  }

  @override
  void reassemble() {
    super.reassemble();
    esp32Ip = '10.11.240.216';
    connectToESP32();
  }


  // ============================
  // CONNECT TO ESP32
  // ============================

  void connectToESP32() {
    // Close old connection
    subscription?.cancel();
    channel?.sink.close();

    if (mounted) {
      setState(() {
        connectionStatus = 'Connecting...';
      });
    }

    final url = 'ws://$esp32Ip:8765';

    print('Connecting to Python Server: $url');

    try {
      final newChannel = WebSocketChannel.connect(
        Uri.parse(url),
      );

      channel = newChannel;

      // Detect connection completion immediately (even before any data arrives)
      newChannel.ready.then((_) {
        print('WebSocket connected to $url');
        if (mounted) {
          setState(() {
            connectionStatus = 'Connected';
          });
        }
      }).catchError((error) {
        print('WebSocket connection error: $error');
        if (mounted) {
          setState(() {
            connectionStatus = 'Connection error';
          });
        }
      });

      subscription = newChannel.stream.listen(
        (message) {
          print('ESP32 DATA: $message');

          if (mounted) {
            setState(() {
              connectionStatus = 'Connected';
            });
          }

          handleMessage(message.toString());
        },
        onError: (error) {
          print('WebSocket ERROR: $error');

          if (mounted) {
            setState(() {
              connectionStatus = 'Connection error';
            });
          }
        },
        onDone: () {
          print('WebSocket connection closed');

          if (mounted) {
            setState(() {
              connectionStatus = 'Disconnected';
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      print('Connection exception: $e');

      if (mounted) {
        setState(() {
          connectionStatus = 'Connection failed';
        });
      }
    }
  }

  // ============================
  // HANDLE ESP32 DATA
  // ============================

  void handleMessage(String rawMessage) {
    for (final line in rawMessage.split('\n')) {
      final msg = line.trim();
      if (msg.isNotEmpty) {
        _processSingleMessage(msg);
      }
    }
  }

  void _processSingleMessage(String message) {
    print('Received: $message');

    if (message == 'CONNECTED' || message.contains('Flutter connected')) {
      if (mounted) setState(() => connectionStatus = 'Connected');
      return;
    }

    if (message.startsWith('STATUS,')) {
      final parts = message.split(',');
      if (parts.length < 5) return;

      final d = double.tryParse(parts[1].trim());
      final t = double.tryParse(parts[2].trim());
      final h = double.tryParse(parts[3].trim());

      // Arduino's own alarmState is the PRIMARY source of truth
      final arduinoAlert = parts[4].trim() == '1';

      final now = DateTime.now().millisecondsSinceEpoch;
      final is999 = (d == 999.0);
      final distanceClose = (d != null && d > 0.5 && d <= 15.0);

      // 999.0 means sensor saturated = hand TOO CLOSE to measure.
      // If confirmed alert within 3 seconds, treat 999.0 as STILL NEAR.
      final recentAlert = (now - _lastConfirmedAlertMs) < 3000;
      final isNear = arduinoAlert || distanceClose || (is999 && recentAlert);

      // Stamp the confirmed alert time
      if (arduinoAlert || distanceClose) {
        _lastConfirmedAlertMs = now;
      }

      // --- Update sensor values first (OUTSIDE alert logic) ---
      if (mounted) {
        setState(() {
          if (d != null) {
            // Only show 999 if truly out of range, keep last known distance if saturated near
            if (!is999) {
              distance = d;
            } else if (!isNear) {
              distance = 999.0;
            }
          }
          if (t != null) temperature = t;
          if (h != null) humidity = h;
        });
      }

      // Handle alert OUTSIDE setState (never nest setState)
      if (isNear) {
        _triggerAlert('Someone is near the biscuit!');
      } else if (!(_alertResetTimer?.isActive ?? false)) {
        if (mounted) {
          setState(() {
            alert = false;
            alertMessage = 'No one detected';
          });
          _stopAngryBlink();
        }
      }
    } else if (message.startsWith('ALERT,')) {
      final text = message.substring(6).trim();
      _lastConfirmedAlertMs = DateTime.now().millisecondsSinceEpoch;
      _triggerAlert(text.isNotEmpty ? text : 'Someone is near the biscuit!');
    }
  }

  void _triggerAlert(String msg) {
    _alertResetTimer?.cancel();
    if (mounted) {
      final wasAlert = alert;
      setState(() {
        alert = true;
        alertMessage = msg;
      });
      // Start angry rapid blink only on transition to alert
      if (!wasAlert) _startAngryBlink();
    }

    // After 3 seconds of silence, reset to SAFE
    _alertResetTimer = Timer(const Duration(milliseconds: 3000), () {
      if (mounted) {
        setState(() {
          alert = false;
          alertMessage = 'No one detected';
        });
        _stopAngryBlink();
      }
    });
  }


  // ============================
  // CHANGE ESP32 IP
  // ============================

  void showEditIpDialog() {
    final controller =
        TextEditingController(text: esp32Ip);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Python Server IP Address',
          ),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'PC IP Address',
              hintText: '192.168.1.100',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newIp =
                    controller.text.trim();

                if (newIp.isNotEmpty) {
                  setState(() {
                    esp32Ip = newIp;
                  });

                  Navigator.pop(dialogContext);

                  connectToESP32();
                }
              },
              child: const Text(
                'Save & Connect',
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================
  // BUILD UI (iOS Style)
  // ============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.cookie, color: Colors.orangeAccent, size: 28),
        title: const Text('Biscuit Protector', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.settings),
            onPressed: showEditIpDialog,
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Connection Status Card
          _buildInfoCard(
            child: Row(
              children: [
                Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: connectionStatus == 'Connected' ? CupertinoColors.activeGreen : CupertinoColors.destructiveRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Server: $esp32Ip\nStatus: $connectionStatus', 
                    style: const TextStyle(fontSize: 15, height: 1.3)
                  )
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: connectToESP32,
                  child: const Icon(CupertinoIcons.refresh),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Robot Eyes Card
          _buildInfoCard(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                Text(
                  alert ? '⚠️ INTRUDER DETECTED!' : 'All Safe. No one detected.',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold, 
                    color: alert ? CupertinoColors.destructiveRed : CupertinoColors.activeGreen
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_blinkCtrl, _angryBlinkCtrl, _lookCtrl]),
                    builder: (context, child) {
                      final double blinkVal = alert ? _angryBlinkAnim.value : _blinkAnim.value;
                      final Offset lookOffset = alert ? const Offset(0.35, 0.25) : _lookCurrent;

                      return Container(
                        width: 200,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: alert 
                                  ? const Color.fromRGBO(244, 67, 54, 0.65) // Red shadow
                                  : const Color.fromRGBO(0, 188, 212, 0.2), // Cyan shadow
                              blurRadius: 20,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                        child: CustomPaint(
                          painter: RobotEyesPainter(
                            isAngry: alert,
                            blinkAmount: blinkVal,
                            lookOffset: lookOffset,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Sensor Data Grid
          Row(
            children: [
              Expanded(child: _buildMetricCard('Distance', '${distance.toStringAsFixed(1)} cm', Icons.straighten)),
              const SizedBox(width: 12),
              Expanded(child: _buildMetricCard('Temp', '${temperature.toStringAsFixed(1)} °C', Icons.thermostat)),
              const SizedBox(width: 12),
              Expanded(child: _buildMetricCard('Humidity', '${humidity.toStringAsFixed(1)} %', Icons.water_drop)),
            ],
          ),
          const SizedBox(height: 24),

          // PREMIUM PLAN CARD (Razorpay)
          if (!isPremium)
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFF9A9E), Color(0xFFFECFEF)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(233, 30, 99, 0.3),
                    blurRadius: 10, offset: Offset(0, 4)
                  )
                ]
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    '🐜 Warning: Ants Detected!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Biscuits are highly vulnerable to ant invasions. Upgrade now!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: openCheckout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.pink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text('Unlock Anti-Ant Forcefield (₹99)', style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF43E97B), Color(0xFF38F9D7)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(67, 233, 123, 0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                    offset: Offset(0, 4)
                  )
                ]
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(CupertinoIcons.shield_lefthalf_fill, color: Colors.white, size: 40),
                  const SizedBox(height: 8),
                  const Text('Anti-Ant Forcefield ACTIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const Text('Your biscuits are 100% safe.', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _cancelPremium,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withAlpha(50),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel Protection', style: TextStyle(fontWeight: FontWeight.w600)),
                  )
                ]
              )
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.04), blurRadius: 10, offset: Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon) {
    return _buildInfoCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: Colors.blueGrey, size: 28),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _alertResetTimer?.cancel();
    _blinkTimer?.cancel();
    _lookTimer?.cancel();
    _blinkCtrl.dispose();
    _lookCtrl.dispose();
    _angryBlinkCtrl.dispose();
    subscription?.cancel();
    channel?.sink.close();
    super.dispose();
  }
}

// ==========================================
// ANIMATED ROBOT EYES CUSTOM PAINTER
// blinkAmount: 0.0 = fully open, 1.0 = fully closed
// lookOffset: pupil gaze direction, range -1..1 in x and y
// ==========================================

class RobotEyesPainter extends CustomPainter {
  final bool isAngry;
  final double blinkAmount;
  final Offset lookOffset;

  const RobotEyesPainter({
    required this.isAngry,
    required this.blinkAmount,
    required this.lookOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 128.0;
    final sy = size.height / 64.0;

    final eyeColor = Paint()
      ..color = isAngry ? const Color(0xFFFF2222) : const Color(0xFF00E5FF);
    final pupilPaint = Paint()..color = Colors.black;
    final browPaint = Paint()
      ..color = const Color(0xFFFF2222)
      ..strokeWidth = 3.8 * sx
      ..strokeCap = StrokeCap.round;

    // Eye center positions matching Arduino OLED coords
    final leftCenter = Offset(38 * sx, 32 * sy);
    final rightCenter = Offset(90 * sx, 32 * sy);
    const eyeR = 12.0;
    const pupilR = 5.0;

    // Pupil look-around travel (canvas units)
    final lx = lookOffset.dx * 5.0 * sx;
    final ly = lookOffset.dy * 3.5 * sy;

    if (!isAngry) {
      // ---- SAFE: calm eyes with blinking + pupil look-around ----
      _drawEye(canvas,
          center: leftCenter.translate(lx, ly),
          eyeRadius: eyeR * sx,
          pupilRadius: pupilR * sx,
          blinkAmount: blinkAmount,
          eyePaint: eyeColor,
          pupilPaint: pupilPaint);

      _drawEye(canvas,
          center: rightCenter.translate(lx, ly),
          eyeRadius: eyeR * sx,
          pupilRadius: pupilR * sx,
          blinkAmount: blinkAmount,
          eyePaint: eyeColor,
          pupilPaint: pupilPaint);
    } else {
      // ---- ANGRY: slanted brows + rapid blink + inward pupils ----

      // Angry eyebrows forming V-shape
      canvas.drawLine(
          Offset(24 * sx, 16 * sy), Offset(52 * sx, 27 * sy), browPaint);
      canvas.drawLine(
          Offset(104 * sx, 16 * sy), Offset(76 * sx, 27 * sy), browPaint);

      // Left eye: pupil shifted inward (toward nose)
      _drawEye(canvas,
          center: Offset(38 * sx, 37 * sy),
          eyeRadius: eyeR * sx,
          pupilRadius: (pupilR - 0.5) * sx,
          blinkAmount: blinkAmount,
          eyePaint: eyeColor,
          pupilPaint: pupilPaint,
          pupilOffset: Offset(3.5 * sx, 1.5 * sy));

      // Right eye: pupil shifted inward (toward nose)
      _drawEye(canvas,
          center: Offset(90 * sx, 37 * sy),
          eyeRadius: eyeR * sx,
          pupilRadius: (pupilR - 0.5) * sx,
          blinkAmount: blinkAmount,
          eyePaint: eyeColor,
          pupilPaint: pupilPaint,
          pupilOffset: Offset(-3.5 * sx, 1.5 * sy));

      // Angry mouth bar — only visible when eyes are open
      if (blinkAmount < 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(64 * sx, 54 * sy),
              width: 28 * sx,
              height: 5 * sy,
            ),
            const Radius.circular(2),
          ),
          eyeColor,
        );
      }
    }
  }

  void _drawEye(
    Canvas canvas, {
    required Offset center,
    required double eyeRadius,
    required double pupilRadius,
    required double blinkAmount,
    required Paint eyePaint,
    required Paint pupilPaint,
    Offset pupilOffset = Offset.zero,
  }) {
    if (blinkAmount >= 0.97) {
      // Fully closed — just a horizontal line
      final linePaint = Paint()
        ..color = eyePaint.color
        ..strokeWidth = eyeRadius * 0.30
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center.translate(-eyeRadius * 0.85, 0),
        center.translate(eyeRadius * 0.85, 0),
        linePaint,
      );
      return;
    }

    final openness = (1.0 - blinkAmount).clamp(0.08, 1.0);

    canvas.save();
    canvas.clipRect(Rect.fromCenter(
      center: center,
      width: eyeRadius * 2.5,
      height: eyeRadius * 2.5,
    ));

    // Eye oval — squishes vertically when blinking
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: eyeRadius * 2,
        height: eyeRadius * 2 * openness,
      ),
      eyePaint,
    );

    // Pupil — shrinks and disappears as eye closes
    if (openness > 0.20) {
      canvas.drawCircle(
        center.translate(pupilOffset.dx, pupilOffset.dy),
        pupilRadius * openness,
        pupilPaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RobotEyesPainter old) =>
      old.isAngry != isAngry ||
      old.blinkAmount != blinkAmount ||
      old.lookOffset != lookOffset;
}