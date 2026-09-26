import 'package:flutter/material.dart';

/// The StockHub app mark (rounded-square gradient box). Used in the sidebar
/// header, splash screen and the login brand panel.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 32, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * 0.22),
      child: Image.asset('assets/branding/logo_256.png', width: size, height: size, fit: BoxFit.cover),
    );
  }
}
