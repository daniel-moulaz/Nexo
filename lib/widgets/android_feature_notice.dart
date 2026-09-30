import 'package:flutter/material.dart';

class AndroidFeatureNotice extends StatelessWidget {
  final String title;
  final String explanation;
  const AndroidFeatureNotice(
      {super.key, required this.title, required this.explanation});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.phone_android_outlined, size: 48),
                const SizedBox(height: 16),
                Text('Disponível no Android',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(explanation, textAlign: TextAlign.center),
              ])),
        )),
      );
}
