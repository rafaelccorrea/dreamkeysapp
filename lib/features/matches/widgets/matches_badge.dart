import 'package:flutter/material.dart';
import '../services/match_service.dart';
import '../models/match_model.dart';

/// Badge que mostra quantidade de matches pendentes
class MatchesBadge extends StatefulWidget {
  final String? clientId;
  final String? propertyId;
  final VoidCallback? onClick;
  final Widget child;

  const MatchesBadge({
    super.key,
    this.clientId,
    this.propertyId,
    this.onClick,
    required this.child,
  });

  @override
  State<MatchesBadge> createState() => _MatchesBadgeState();
}

class _MatchesBadgeState extends State<MatchesBadge> {
  final MatchService _matchService = MatchService.instance;
  int _pendingCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    try {
      final response = await _matchService.getMatches(
        status: MatchStatus.pending,
        limit: 1,
        clientId: widget.clientId,
        propertyId: widget.propertyId,
      );

      if (mounted) {
        setState(() {
          _pendingCount = response.data?.total ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _pendingCount == 0) {
      return widget.child;
    }

    return GestureDetector(
      onTap: widget.onClick,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Center(
                child: Text(
                  _pendingCount > 99 ? '99+' : '$_pendingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

