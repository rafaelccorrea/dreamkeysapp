import 'package:flutter/material.dart';

/// Painter para desenhar a curva branca que preenche a área cortada
class WhiteCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();

    // Começa do canto inferior esquerdo
    path.moveTo(0, size.height);

    // Linha até o início da curva (mesma curva do ImageCurveClipper)
    path.lineTo(0, size.height * 0.82);

    // Curva S invertida (mesma do ImageCurveClipper, mas invertida)
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.92,
      size.width * 0.5,
      size.height * 0.81,
    );

    path.quadraticBezierTo(
      size.width * 0.65,
      size.height * 0.74,
      size.width,
      size.height * 0.8,
    );

    // Linha até o canto inferior direito
    path.lineTo(size.width, size.height);

    // Fecha o caminho
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}






