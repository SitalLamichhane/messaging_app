import 'package:flutter/material.dart';

import '../../domain/call_models.dart';
import '../../infrastructure/call_api_service.dart';

class OngoingCallBanner extends StatefulWidget {
  final int conversationId;
  final CallApiService api;
  final Future<void> Function(CallSessionDto call) onJoin;

  const OngoingCallBanner({
    super.key,
    required this.conversationId,
    required this.api,
    required this.onJoin,
  });

  @override
  State<OngoingCallBanner> createState() =>
      _OngoingCallBannerState();
}

class _OngoingCallBannerState
    extends State<OngoingCallBanner>
    with WidgetsBindingObserver {
  CallSessionDto? _active;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didUpdateWidget(
    covariant OngoingCallBanner oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.conversationId !=
        widget.conversationId) {
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);

    try {
      final result = await widget.api
          .getActiveGroupCall(widget.conversationId);

      if (!mounted) return;

      setState(() {
        _active =
            result.active ? result.call : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _active = null;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _active == null) {
      return const SizedBox.shrink();
    }

    final call = _active!;

    return Material(
      color: const Color(0xFF075E54),
      child: InkWell(
        onTap: () => widget.onJoin(call),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 11,
          ),
          child: Row(
            children: [
              Icon(
                call.isVideo
                    ? Icons.videocam
                    : Icons.call,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ongoing group call',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Tap to join',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
