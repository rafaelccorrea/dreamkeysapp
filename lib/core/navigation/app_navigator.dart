import 'package:flutter/material.dart';

/// Chave global do [Navigator] — toast, deep links e logout sem [BuildContext] da árvore.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
