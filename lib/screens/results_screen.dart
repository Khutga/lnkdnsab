import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../services/groq_service.dart';

class ResultsScreen extends StatelessWidget {
  final List<AnalysisResult> results;
  final String query;
  final String cvText;
  final String apiKey;

  const ResultsScreen({super.key, required this.results, required this.query, required this.cvText, required this.apiKey});

  @override
  Widget build(BuildContext context) {
    final avgMatch = results.isEmpty ? 0 :
      (results.map((r) => r.matchPercentage).reduce((a, b) => a + b) / results.length).round();

    // En çok istenen eksik beceriler
    final missingCount = <String, int>{};
    for (final r in results) {
      for (final s in r.missingSkills) {
        final k = s.toLowerCase();
        missingCount[k] = (missingCount[k] ?? 0) + 1;
      }
    }
    final topMissing = missingCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: Text('$query · ${results.length} sonuç', style: const TextStyle(fontSize: 15))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Özet
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [const Color(0xFF6366F1).withOpacity(0.08), const Color(0xFF8B5CF6).withOpacity(0.03)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Toplu Analiz', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0))),
              const SizedBox(height: 4),
              Text('${results.length} ilan · Ort. %$avgMatch uyum', style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13)),
            ]),
            _Gauge(value: avgMatch, size: 58),
          ]),
        ),

        // Eksik beceriler
        if (topMissing.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.12)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🔑 En Çok İstenen Eksik Beceriler', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: topMissing.take(12).map((e) =>
                _badge('${e.key} (${e.value}x)', false),
              ).toList()),
            ]),
          ),
        ],

        const SizedBox(height: 20),
        Text('İlanlar (uyuma göre)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[300])),
        const SizedBox(height: 10),

        ...results.map((r) => _JobCard(result: r, cvText: cvText, apiKey: apiKey)),
      ]),
    );
  }

  Widget _badge(String text, bool match) {
    final c = match ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withOpacity(0.25))),
      child: Text(text, style: TextStyle(fontSize: 11, color: c.withOpacity(0.85))),
    );
  }
}

class _Gauge extends StatelessWidget {
  final int value;
  final double size;
  const _Gauge({required this.value, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final c = value > 70 ? const Color(0xFF10B981) : value > 40 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(value: value / 100, strokeWidth: 3.5, backgroundColor: const Color(0xFF1E293B), color: c),
        Text('$value', style: TextStyle(color: c, fontSize: size * 0.3, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _JobCard extends StatefulWidget {
  final AnalysisResult result;
  final String cvText;
  final String apiKey;
  const _JobCard({required this.result, required this.cvText, required this.apiKey});
  @override
  State<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<_JobCard> {
  bool _open = false;
  bool _improving = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final pct = r.matchPercentage;
    final c = pct > 70 ? const Color(0xFF10B981) : pct > 40 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.position, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFE2E8F0))),
                const SizedBox(height: 2),
                Text('${r.company}${r.location.isNotEmpty ? ' · ${r.location}' : ''}',
                  style: const TextStyle(color: Color(0xFF818CF8), fontSize: 11)),
              ])),
              _Gauge(value: pct, size: 44),
            ]),

            // Expanded detail
            if (_open) ...[
              const Divider(color: Color(0xFF1E293B), height: 24),
              Text(r.summary, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5)),
              const SizedBox(height: 12),

              // Skills
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _skillBox('✓ Eşleşen', r.matchingSkills, true)),
                const SizedBox(width: 8),
                Expanded(child: _skillBox('✗ Eksik', r.missingSkills, false)),
              ]),

              // CV additions
              if (r.cvAdditions.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('📝 CV\'ye ekle:', style: TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...r.cvAdditions.map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26, borderRadius: BorderRadius.circular(6),
                    border: const Border(left: BorderSide(color: Color(0xFF6366F1), width: 2.5)),
                  ),
                  child: Text(s, style: const TextStyle(fontSize: 11, height: 1.5, color: Color(0xFFC9D1D9))),
                )),
              ],

              // Suggestions
              if (r.suggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('💡 Öneriler:', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...r.suggestions.asMap().entries.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26, borderRadius: BorderRadius.circular(6),
                    border: const Border(left: BorderSide(color: Color(0xFFF59E0B), width: 2.5)),
                  ),
                  child: Text('${e.key + 1}. ${e.value}', style: const TextStyle(fontSize: 11, height: 1.5, color: Color(0xFFC9D1D9))),
                )),
              ],

              // LinkedIn link
              if (r.url.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(r.url)),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('LinkedIn\'de Aç', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF818CF8),
                      side: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.25)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],

              // CV Geliştir butonu
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _improving ? null : _improveCv,
                  icon: _improving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_fix_high, size: 16),
                  label: Text(_improving ? 'CV düzenleniyor...' : '✨ Bu İlana Göre CV Düzenle', style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _improveCv() async {
    final r = widget.result;
    setState(() => _improving = true);

    try {
      final improved = await GroqService.improveCv(
        currentCv: widget.cvText,
        jobTitle: r.position,
        jobCompany: r.company,
        jobDescription: r.summary,
        missingSkills: r.missingSkills,
        matchingSkills: r.matchingSkills,
        suggestions: r.suggestions,
        apiKey: widget.apiKey,
      );

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF0D1117),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              // Handle bar
              Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),

              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('✨ Optimize Edilmiş CV', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0))),
                  const SizedBox(height: 4),
                  Text('${r.position} @ ${r.company}', style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
                ])),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: improved));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('CV kopyalandı!'), backgroundColor: Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ));
                  },
                  icon: const Icon(Icons.copy, color: Color(0xFF818CF8)),
                  tooltip: 'Kopyala',
                ),
              ]),
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0F),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: SelectableText(
                      improved,
                      style: const TextStyle(fontSize: 13, height: 1.7, color: Color(0xFFC9D1D9)),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: improved));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('CV kopyalandı!'), backgroundColor: Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ));
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('CV\'yi Kopyala'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Hata: $e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _improving = false);
    }
  }

  Widget _skillBox(String title, List<String> skills, bool match) {
    final c = match ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withOpacity(0.04), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title (${skills.length})', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: skills.map((s) =>
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Text(s, style: TextStyle(fontSize: 10, color: c.withOpacity(0.8))),
          ),
        ).toList()),
      ]),
    );
  }
}