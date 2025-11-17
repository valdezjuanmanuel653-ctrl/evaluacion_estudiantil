import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

import '../logic/grade_logic.dart';
import '../widgets/note_row.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String modo = 'universidad';
  int numCortes = 3;
  double notaMin = 3.0;
  String nombre = '';

  // listas de control
  final List<TextEditingController> gradeCtrls = [];
  final List<TextEditingController> pesoCtrls = [];
  final List<bool> noAplica = [];
  List<NoteEntry> notas = [];

  // historial
  List<Map<String, dynamic>> historial = [];

  @override
  void initState() {
    super.initState();
    _initNotas();
    _loadHistorial();
  }

  void _initNotas() {
    // reinicia estructuras según numCortes
    gradeCtrls.clear();
    pesoCtrls.clear();
    noAplica.clear();
    notas.clear();

    List<int> defaultPesos;
    if (modo == 'universidad') {
      defaultPesos = [30, 30, 40];
    } else {
      final v = (100 / numCortes).floor();
      defaultPesos = List.generate(numCortes, (_) => v);
      int suma = defaultPesos.reduce((a, b) => a + b);
      defaultPesos[defaultPesos.length - 1] += (100 - suma);
    }

    for (int i = 0; i < numCortes; i++) {
      gradeCtrls.add(TextEditingController());
      pesoCtrls.add(TextEditingController(text: defaultPesos[i].toString()));
      noAplica.add(false);
      notas.add(NoteEntry(grade: null, peso: defaultPesos[i], noAplica: false));
    }
    setState(() {});
  }

  Future<void> _loadHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('historial_v1');
    if (jsonStr != null) {
      final List<dynamic> list = json.decode(jsonStr);
      historial = List<Map<String, dynamic>>.from(list);
      setState(() {});
    }
  }

  Future<void> _saveHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('historial_v1', json.encode(historial));
  }

  void _modoCambio(String nuevo) {
    modo = nuevo;
    if (modo == 'universidad') numCortes = 3;
    _initNotas();
  }

  void _cambiarNumCortes(String v) {
    numCortes = int.tryParse(v) ?? 4;
    _initNotas();
  }

  // suma pesos aplicables
  int _sumarPesosAplicables() {
    int s = 0;
    for (int i = 0; i < notas.length; i++) {
      if (noAplica[i]) continue;
      s += int.tryParse(pesoCtrls[i].text) ?? 0;
    }
    return s;
  }

  void _normalizarPesos() {
    final aplicables = <int>[];
    for (int i = 0; i < notas.length; i++) {
      if (!noAplica[i]) aplicables.add(i);
    }
    if (aplicables.isEmpty) return;
    final base = (100 / aplicables.length).floor();
    int suma = 0;
    for (int k = 0; k < aplicables.length; k++) {
      final i = aplicables[k];
      if (k == aplicables.length - 1) {
        pesoCtrls[i].text = (100 - suma).toString();
      } else {
        pesoCtrls[i].text = base.toString();
        suma += base;
      }
    }
    setState(() {});
  }

  bool _validarPesos() {
    final s = _sumarPesosAplicables();
    if (s != 100) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('La suma de pesos aplicables debe ser 100% (actual: $s%).')));
      return false;
    }
    return true;
  }

  void _toggleNoAplica(int idx, bool val) {
    noAplica[idx] = val;
    if (val) {
      gradeCtrls[idx].text = '';
      pesoCtrls[idx].text = '0';
    } else {
      // si quedó 0 y ya no aplica = false, normalizar
      if (_sumarPesosAplicables() == 0) _normalizarPesos();
    }
    setState(() {});
  }

  void _calcular() {
    if (!_validarPesos()) return;

    // construir notas con los datos de los controllers
    notas = List.generate(notas.length, (i) {
      final g = double.tryParse(gradeCtrls[i].text);
      final p = int.tryParse(pesoCtrls[i].text) ?? 0;
      return NoteEntry(grade: g, peso: p, noAplica: noAplica[i]);
    });

    final necesidad = analizarNecesidad(notas);
    final pesoRestante = necesidad.pesoRestante;
    final sumaContrib = notas.fold<double>(0.0, (acc, n) => acc + ((n.noAplica || n.grade == null) ? 0 : (n.grade! * n.peso)));
    final promedioActual = pesoRestante == 0 ? (sumaContrib / 100.0) : (sumaContrib / (100 - pesoRestante));
    String texto = '';

    if (pesoRestante == 0) {
      final estado = promedioActual >= notaMin ? 'Aprobado' : 'Reprobado';
      texto = '${estado == 'Aprobado' ? '🎉 ¡Felicidades, aprobaste!' : '❌ No alcanzaste la nota mínima.'} — Promedio: ${promedioActual.toStringAsFixed(2)}';
    } else {
      final requiredTotal = notaMin * 100;
      final neededSum = requiredTotal - sumaContrib;
      final neededAvg = neededSum / pesoRestante;
      if (neededAvg <= 0) {
        texto = 'Con las notas registradas ya alcanzas la nota mínima (${notaMin}). Promedio actual aproximado: ${(sumaContrib / 100).toStringAsFixed(2)}.';
      } else if (neededAvg > 5) {
        texto = 'Imposible: incluso con 5.0 en las notas faltantes no alcanzarías ${notaMin}. Nota requerida (ponderada en faltantes): ${neededAvg.toStringAsFixed(2)}.';
      } else {
        texto = 'Necesitas un promedio ponderado de ${neededAvg.toStringAsFixed(2)} en las notas faltantes para llegar a ${notaMin}.';
        final faltantes = <int>[];
        for (int i = 0; i < notas.length; i++) {
          if (!notas[i].noAplica && notas[i].grade == null) faltantes.add(i + 1);
        }
        if (faltantes.length == 1) {
          final idx = faltantes.first - 1;
          final reqSpecific = neededSum / notas[idx].peso;
          texto += ' (Solo falta la Nota ${idx + 1}, necesitas ${reqSpecific.toStringAsFixed(2)}).';
        } else {
          texto += ' (Si faltan varias notas, esa es la media ponderada entre ellas).';
        }
      }
    }

    // mostrar en dialog
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resultado'),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
    setState(() {});
  }

  void _guardarHistorial() {
    // validar y calcular promedio parcial (sumaContrib/100)
    if (!_validarPesos()) return;
    notas = List.generate(notas.length, (i) {
      final g = double.tryParse(gradeCtrls[i].text);
      final p = int.tryParse(pesoCtrls[i].text) ?? 0;
      return NoteEntry(grade: g, peso: p, noAplica: noAplica[i]);
    });

    double sumaContrib = 0.0;
    int pesoRestante = 0;
    for (final n in notas) {
      if (n.noAplica) continue;
      if (n.grade != null) sumaContrib += n.grade! * n.peso;
      else pesoRestante += n.peso;
    }
    final promedioFinal = (sumaContrib / 100.0);
    String estado = 'Incompleto';
    if (pesoRestante == 0) estado = promedioFinal >= notaMin ? 'Aprobado' : 'Reprobado';

    final row = {
      'nombre': nombre.isEmpty ? 'Sin nombre' : nombre,
      'modo': modo,
      'promedio': promedioFinal.toStringAsFixed(2),
      'estado': estado,
      'timestamp': DateTime.now().toIso8601String(),
    };
    historial.insert(0, row);
    _saveHistorial();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado en historial.')));
    setState(() {});
  }

  void _limpiar() {
    nombre = '';
    notaMin = 3.0;
    for (final c in gradeCtrls) c.clear();
    for (final p in pesoCtrls) p.text = '0';
    for (int i = 0; i < noAplica.length; i++) noAplica[i] = false;
    _initNotas();
  }

  // -> datos para gráfico simple
  List<BarChartGroupData> _graficoData() {
    final barras = <BarChartGroupData>[];
    for (int i = 0; i < notas.length; i++) {
      final val = double.tryParse(gradeCtrls[i].text) ?? 0.0;
      final color = val >= 3.0 ? Colors.green : Colors.red;
      barras.add(
        BarChartGroupData(x: i, barRods: [
          BarChartRodData(toY: val, width: 18, color: color),
        ]),
      );
    }
    return barras;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // background similar to your HTML: a top colored bar
      appBar: AppBar(
        title: const Text('Sistema de Evaluación Estudiantil'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Configuración
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: modo,
                  decoration: const InputDecoration(labelText: 'Modo'),
                  items: const [
                    DropdownMenuItem(value: 'universidad', child: Text('Universidad (3 cortes)')),
                    DropdownMenuItem(value: 'colegio', child: Text('Colegio (4-6 cortes)')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    _modoCambio(v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              if (modo == 'colegio')
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<int>(
                    value: numCortes,
                    decoration: const InputDecoration(labelText: 'N° cortes'),
                    items: const [
                      DropdownMenuItem(value: 4, child: Text('4')),
                      DropdownMenuItem(value: 5, child: Text('5')),
                      DropdownMenuItem(value: 6, child: Text('6')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      _cambiarNumCortes(v.toString());
                    },
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(labelText: 'Nombre del estudiante'),
              onChanged: (v) => nombre = v,
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: 'Nota mínima para aprobar (0.0-5.0)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              controller: TextEditingController(text: notaMin.toStringAsFixed(1)),
              onChanged: (v) {
                notaMin = double.tryParse(v) ?? 3.0;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(onPressed: _initNotas, child: const Text('Generar formulario de notas')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _normalizarPesos, child: const Text('Normalizar pesos')),
              ],
            ),
            const SizedBox(height: 12),

            // Notas dinamicas
            Column(
              children: List.generate(notas.length, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: NoteRow(
                    index: i,
                    gradeController: gradeCtrls[i],
                    pesoController: pesoCtrls[i],
                    noAplica: noAplica[i],
                    onToggleNoAplica: (v) => _toggleNoAplica(i, v),
                    onGradeChanged: (_) => setState(() {}),
                    onPesoChanged: (_) => setState(() {}),
                  ),
                );
              }),
            ),

            const SizedBox(height: 12),
            Row(children: [
              ElevatedButton(onPressed: _calcular, child: const Text('Calcular')),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _guardarHistorial, child: const Text('Guardar')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _limpiar, child: const Text('Limpiar')),
            ]),

            const SizedBox(height: 18),
            // Grafico simple con fl_chart
            SizedBox(
              height: 240,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: 5,
                      barGroups: _graficoData(),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
                            final idx = v.toInt();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text('N${idx + 1}'),
                            );
                          }),
                        ),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                      ),
                      gridData: FlGridData(show: true),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),
            // Historial
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    const Text('Historial', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 180,
                      child: historial.isEmpty
                          ? const Center(child: Text('No hay registros'))
                          : ListView.builder(
                              itemCount: historial.length,
                              itemBuilder: (_, i) {
                                final r = historial[i];
                                return ListTile(
                                  title: Text(r['nombre']),
                                  subtitle: Text('${r['modo']} • ${r['promedio']}'),
                                  trailing: Text(r['estado']),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            historial.clear();
                            _saveHistorial();
                            setState(() {});
                          },
                          child: const Text('Borrar historial'),
                        )
                      ],
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

