import 'package:flutter/material.dart';

/// Clipper para criar curva suave na parte inferior da imagem
class ImageCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    // Inicia no topo esquerdo
    path.moveTo(0, 0);

    // Linha reta até o canto superior direito
    path.lineTo(size.width, 0);

    // Linha reta até o início da curva
    path.lineTo(size.width, size.height * 0.8);

    // Curva S muito suave, quase imperceptível
    path.quadraticBezierTo(
      size.width * 0.65,
      size.height * 0.74, // Muito sutil
      size.width * 0.5,
      size.height * 0.81,
    );

    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.92, // Muito sutil
      0,
      size.height * 0.82,
    );

    // Linha reta até o canto inferior esquerdo
    path.lineTo(0, size.height);

    // Fecha o caminho
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}





