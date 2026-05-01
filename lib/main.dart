import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/y300_app.dart';

void main() {
  runApp(const ProviderScope(child: Y300App()));
}