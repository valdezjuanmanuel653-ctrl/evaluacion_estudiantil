import 'package:flutter/material.dart';

class NoteRow extends StatelessWidget {
  final int index;
  final TextEditingController gradeController;
  final TextEditingController pesoController;
  final bool noAplica;
  final Function(bool) onToggleNoAplica;
  final Function(String) onGradeChanged;
  final Function(String) onPesoChanged;

  const NoteRow({
    super.key,
    required this.index,
    required this.gradeController,
    required this.pesoController,
    required this.noAplica,
    required this.onToggleNoAplica,
    required this.onGradeChanged,
    required this.onPesoChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Nota
        Expanded(
          child: TextField(
            controller: gradeController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Nota ${index + 1}',
            ),
            onChanged: onGradeChanged,
            enabled: !noAplica,
          ),
        ),

        const SizedBox(width: 10),

        // Peso
        SizedBox(
          width: 80,
          child: TextField(
            controller: pesoController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '%'),
            onChanged: onPesoChanged,
            enabled: !noAplica,
          ),
        ),

        const SizedBox(width: 10),

        // Check No Aplica
        Column(
          children: [
            const Text("N/A"),
            Checkbox(
              value: noAplica,
              onChanged: (v) => onToggleNoAplica(v ?? false),
            ),
          ],
        ),
      ],
    );
  }
}
