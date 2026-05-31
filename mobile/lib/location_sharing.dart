import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocationSharingWidget extends StatefulWidget {
  final VoidCallback? onToggleSharing;

  const LocationSharingWidget({super.key, this.onToggleSharing});

  @override
  State<LocationSharingWidget> createState() => _LocationSharingWidgetState();
}

class _LocationSharingWidgetState extends State<LocationSharingWidget> with SingleTickerProviderStateMixin {
  bool _isBroadcasting = false;
  late AnimationController _pulseController;
  final String _trackingUrl = "https://roadsos.live/track/aarya-2026";

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleBroadcasting(bool value) {
    setState(() {
      _isBroadcasting = value;
      if (_isBroadcasting) {
        _pulseController.repeat();
      } else {
        _pulseController.stop();
      }
    });
    if (widget.onToggleSharing != null) {
      widget.onToggleSharing!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isBroadcasting
              ? Colors.blueAccent
              : Colors.white.withValues(alpha: 0.05),
          width: 1.5,
        ),
        boxShadow: [
          if (_isBroadcasting)
            BoxShadow(
              color: Colors.blueAccent.withValues(alpha: 0.15),
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
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_isBroadcasting)
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Container(
                              width: 36 * _pulseController.value,
                              height: 36 * _pulseController.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blueAccent.withValues(alpha: 1.0 - _pulseController.value),
                              ),
                            );
                          },
                        ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (_isBroadcasting ? Colors.blueAccent : Colors.white30)
                              .withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isBroadcasting ? Icons.radar_rounded : Icons.location_off_rounded,
                          color: _isBroadcasting ? Colors.blueAccent : Colors.white54,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Voluntary Location Sharing",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isBroadcasting ? "Active Family Tracking Link Shared" : "Sharing Inactive",
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
                value: _isBroadcasting,
                onChanged: _toggleBroadcasting,
                activeColor: Colors.blueAccent,
              ),
            ],
          ),

          if (_isBroadcasting) ...[
            const SizedBox(height: 18),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),

            // Link Display & Copy Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, color: Colors.blueAccent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _trackingUrl,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Colors.white38, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _trackingUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("📋 Tracking link copied to clipboard!"),
                          backgroundColor: Colors.blueAccent,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Family Contacts Receiving
            const Text(
              "SHARING FEED WITH",
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: Colors.white30,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildContactChip("Mom (Family Contact)", Icons.favorite),
                const SizedBox(width: 10),
                _buildContactChip("Dad (Emergency)", Icons.shield),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactChip(String name, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.blueAccent, size: 12),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
        ],
      ),
    );
  }
}
