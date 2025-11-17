class NoteEntry {
  double? grade; // null = no ingresada
  int peso; // porcentaje
  bool noAplica;
  NoteEntry({this.grade, required this.peso, this.noAplica = false});

  Map<String, dynamic> toJson() => {
        'grade': grade,
        'peso': peso,
        'noAplica': noAplica,
      };

  factory NoteEntry.fromJson(Map<String, dynamic> j) => NoteEntry(
        grade: j['grade'] == null ? null : (j['grade'] as num).toDouble(),
        peso: j['peso'] as int,
        noAplica: j['noAplica'] as bool,
      );
}

// calcula promedio ponderado (0.0-5.0). Devuelve null si no hay suficientes datos para un promedio final
double calcularPromedioPonderado(List<NoteEntry> notas) {
  double suma = 0.0;
  int pesoAplicable = 0;
  for (final n in notas) {
    if (n.noAplica) continue;
    pesoAplicable += n.peso;
    if (n.grade != null) suma += (n.grade! * n.peso);
  }
  if (pesoAplicable == 0) return 0.0;
  return suma / pesoAplicable;
}

// devuelve objeto con info necesaria para determinar necesidad en faltantes
class NecesidadResult {
  final double promedioActual; // tomando 0 por faltantes (escala 0-5)
  final bool completado; // si no hay notas faltantes (todas ingresadas o noAplica)
  final int pesoRestante;
  NecesidadResult(this.promedioActual, this.completado, this.pesoRestante);
}

NecesidadResult analizarNecesidad(List<NoteEntry> notas) {
  double sumaContrib = 0.0;
  int pesoRestante = 0;
  int pesoAplicable = 0;
  for (final n in notas) {
    if (n.noAplica) continue;
    pesoAplicable += n.peso;
    if (n.grade != null) {
      sumaContrib += n.grade! * n.peso;
    } else {
      pesoRestante += n.peso;
    }
  }
  final promedioActual = pesoAplicable == 0 ? 0.0 : sumaContrib / pesoAplicable;
  final completado = pesoRestante == 0;
  return NecesidadResult(promedioActual, completado, pesoRestante);
}
