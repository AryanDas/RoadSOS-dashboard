import 'dart:async';
import 'package:flutter/material.dart';

class PreventativeAlertsWidget extends StatefulWidget {
  final double currentSpeed;
  final bool isInteractingWithPhone;
  final bool isAssistantActive;
  final Function(bool active) onToggleAssistant;

  const PreventativeAlertsWidget({
    super.key,
    required this.currentSpeed,
    required this.isInteractingWithPhone,
    required this.isAssistantActive,
    required this.onToggleAssistant,
  });

  @override
  State<PreventativeAlertsWidget> createState() => _PreventativeAlertsWidgetState();
}

class _PreventativeAlertsWidgetState extends State<PreventativeAlertsWidget> {
  bool _flashingState = false;
  Timer? _flashTimer;
  String? _activeVoiceWarning;

  @override
  void didUpdateWidget(covariant PreventativeAlertsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isAssistantActive) {
      _stopWarning();
      return;
    }

    final exceedsSpeed = widget.currentSpeed > 80.0;
    final isTexting = widget.isInteractingWithPhone;

    if (exceedsSpeed || isTexting) {
      _startWarning(
        exceedsSpeed
            ? "⚠️ ALERT: SPEED LIMIT EXCEEDED. Please slow down immediately!"
            : "📵 WARNING: DISTRACTED DRIVING DETECTED. Keep eyes on the road!",
      );
    } else {
      _stopWarning();
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _startWarning(String text) {
    if (_activeVoiceWarning == text) return;
    
    setState(() {
      _activeVoiceWarning = text;
    });

    _flashTimer?.cancel();
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        _flashingState = !_flashingState;
      });
    });
  }

  void _stopWarning() {
    if (_activeVoiceWarning == null) return;
    _flashTimer?.cancel();
    setState(() {
      _activeVoiceWarning = null;
      _flashingState = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final warningColor = _flashingState ? const Color(0xFFFF3B30) : const Color(0xFFFF3B30).withValues(alpha: 0.1);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.isAssistantActive && _activeVoiceWarning != null
              ? warningColor
              : Colors.white.withValues(alpha: 0.05),
          width: 1.5,
        ),
        boxShadow: [
          if (widget.isAssistantActive && _activeVoiceWarning != null)
            BoxShadow(
              color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
              blurRadius: 15,
            )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (widget.isAssistantActive ? const Color(0xFF34C759) : Colors.white30)
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isAssistantActive ? Icons.spatial_audio_off_rounded : Icons.volume_off,
                      color: widget.isAssistantActive ? const Color(0xFF34C759) : Colors.white54,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Audio Safety Assistant",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isAssistantActive ? "Background Voice Shield Enabled" : "Shield Disarmed",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: widget.isAssistantActive,
                onChanged: widget.onToggleAssistant,
                activeColor: const Color(0xFF34C759),
              ),
            ],
          ),

          if (widget.isAssistantActive) ...[
            const SizedBox(height: 18),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),

            // Live Alert Box
            if (_activeVoiceWarning != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF3B30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.record_voice_over,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "REAL-TIME VOICE WARNING PLAYING",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFF3B30),
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _activeVoiceWarning!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF34C759).withValues(alpha: 0.15)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF34C759),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "DRIVE METRICS HEALTHY",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF34C759),
                              letterSpacing: 1.0,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Speeding and Distraction checks normal.",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
