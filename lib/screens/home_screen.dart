import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models.dart';
import '../services/linkedin_scraper.dart';
import '../services/groq_service.dart';
import 'results_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Controllers
  final _queryCtrl = TextEditingController();
  final _locationCtrl = TextEditingController(text: 'istanbul');
  final _cvCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();

  // State
  int _step = 0; // 0=jobs, 1=cv, 2=analyzing
  int _maxResults = 10;
  bool _loading = false;
  String _statusText = '';
  String _statusSub = '';
  double _progress = 0;
  String _cvFileName = '';

  // Data
  List<JobListing> _jobs = [];
  String _jobSource = ''; // 'search', 'json', 'paste'

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyCtrl.text = prefs.getString('groq_key') ?? '';
      _cvCtrl.text = prefs.getString('cv_text') ?? '';
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('groq_key', _apiKeyCtrl.text.trim());
    prefs.setString('cv_text', _cvCtrl.text.trim());
  }

  // ===== JOB LOADING =====

  Future<void> _searchLinkedIn() async {
    if (_queryCtrl.text.trim().isEmpty) return;
    setState(() { _loading = true; _statusText = 'LinkedIn taranıyor...'; _statusSub = ''; });

    try {
      final jobs = await LinkedInScraper.searchJobs(
        _queryCtrl.text.trim(),
        _locationCtrl.text.trim(),
        maxResults: _maxResults,
        onProgress: (n) {
          if (mounted) setState(() { _statusSub = '$n ilan bulundu'; });
        },
      );

      setState(() {
        _jobs = jobs;
        _jobSource = 'search';
        _loading = false;
        if (jobs.isNotEmpty) _step = 1;
      });

      if (jobs.isEmpty) {
        _showSnack('İlan bulunamadı. Farklı arama deneyin.');
      }
    } catch (e) {
      setState(() { _loading = false; });
      _showSnack('Hata: $e');
    }
  }

  Future<void> _pickCvFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'pdf'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) return;

      final file = result.files.single;
      final bytes = file.bytes!;

      String text = '';
      if (file.extension?.toLowerCase() == 'pdf') {
        try {
          final document = PdfDocument(inputBytes: bytes);
          final extractor = PdfTextExtractor(document);
          // Her sayfayı ayrı ayrı çek
          for (int i = 0; i < document.pages.count; i++) {
            text += extractor.extractText(startPageIndex: i, endPageIndex: i);
            text += '\n';
          }
          document.dispose();
        } catch (e) {
          _showSnack('PDF okuma hatası: $e');
          return;
        }

        if (text.trim().length < 20) {
          _showSnack('PDF\'den yeterli metin çıkarılamadı. Lütfen kopyala-yapıştır yapın.');
          return;
        }
      } else {
        text = utf8.decode(bytes);
      }

      setState(() {
        _cvCtrl.text = text.trim();
        _cvFileName = file.name;
      });

      _showSnack('✓ ${file.name} yüklendi (${text.trim().length} karakter)');
    } catch (e) {
      _showSnack('Dosya okuma hatası: $e');
    }
  }

  // ===== ANALYSIS =====

  Future<void> _startAnalysis() async {
    final apiKey = _apiKeyCtrl.text.trim();
    final cvText = _cvCtrl.text.trim();

    if (apiKey.isEmpty) { _showSnack('Groq API key gerekli'); return; }
    if (cvText.isEmpty) { _showSnack('CV bilgisi gerekli'); return; }

    await _savePrefs();
    setState(() { _step = 2; _progress = 0; });

    final results = <AnalysisResult>[];

    for (int i = 0; i < _jobs.length; i++) {
      var job = _jobs[i];

      setState(() {
        _statusText = job.title;
        _statusSub = '${job.company} · ${i + 1}/${_jobs.length}';
        _progress = (i + 1) / _jobs.length;
      });

      // İlan detayı yoksa çek
      if ((job.description ?? '').isEmpty && job.url.isNotEmpty) {
        setState(() { _statusSub += ' · detay çekiliyor...'; });
        job = await LinkedInScraper.scrapeJobDetail(job);
        _jobs[i] = job;
      }

      final desc = job.description ?? '';
      if (desc.isEmpty) {
        results.add(AnalysisResult(
          position: job.title, company: job.company,
          location: job.location, url: job.url,
          matchingSkills: [], missingSkills: [],
          matchPercentage: 0, suggestions: [], cvAdditions: [],
          summary: 'İlan detayı alınamadı',
        ));
        continue;
      }

      // AI analiz
      setState(() { _statusSub = '${job.company} · AI analiz...'; });
      final result = await GroqService.analyze(
        jobTitle: job.title,
        jobCompany: job.company,
        jobDescription: desc,
        cvText: cvText,
        apiKey: apiKey,
        jobLocation: job.location,
        jobUrl: job.url,
      );
      results.add(result);

      // Rate limit
      if (i < _jobs.length - 1) {
        await Future.delayed(const Duration(milliseconds: 2500));
      }
    }

    if (!mounted) return;

    results.sort((a, b) => b.matchPercentage.compareTo(a.matchPercentage));

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ResultsScreen(
        results: results,
        query: _queryCtrl.text,
        cvText: _cvCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
      ),
    )).then((_) {
      setState(() { _step = 0; });
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: const Color(0xFF1E293B),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Text('CV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 10),
          const Text('CV Analyzer', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          // Step indicators
          ...List.generate(3, (i) {
            final labels = ['İlanlar', 'CV', 'Analiz'];
            final isActive = _step == i;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: Text(labels[i], style: TextStyle(fontSize: 10, color: isActive ? const Color(0xFF818CF8) : const Color(0xFF475569))),
                backgroundColor: isActive ? const Color(0xFF6366F1).withOpacity(0.12) : Colors.transparent,
                side: BorderSide(color: isActive ? const Color(0xFF6366F1).withOpacity(0.25) : Colors.transparent),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
          }),
          const SizedBox(width: 4),
        ],
      ),
      body: _step == 2 ? _buildAnalyzing() : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildApiKeySection(),
          const SizedBox(height: 24),
          if (_step == 0) _buildJobStep(),
          if (_step == 1) _buildCvStep(),
        ]),
      ),
    );
  }

  Widget _buildApiKeySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Groq API Key', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _apiKeyCtrl,
          decoration: const InputDecoration(hintText: 'gsk_...', isDense: true),
          style: const TextStyle(fontSize: 13),
          obscureText: true,
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _launchUrl('https://console.groq.com/keys'),
          child: const Text('Ücretsiz key al → console.groq.com/keys',
            style: TextStyle(color: Color(0xFF475569), fontSize: 11, decoration: TextDecoration.underline)),
        ),
      ]),
    );
  }

  Widget _buildJobStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('İş İlanları', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0))),
      const SizedBox(height: 4),
      const Text('LinkedIn\'de iş ilanı arayın', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
      const SizedBox(height: 20),

      // === SEARCH ===
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🔍 LinkedIn\'de Ara', style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _queryCtrl,
            decoration: const InputDecoration(hintText: 'software engineer, flutter developer...', prefixIcon: Icon(Icons.search, size: 20, color: Color(0xFF475569))),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _locationCtrl,
            decoration: const InputDecoration(hintText: 'istanbul, turkey, remote...', prefixIcon: Icon(Icons.location_on_outlined, size: 20, color: Color(0xFF475569))),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text('Maks: $_maxResults', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
            Expanded(
              child: Slider(
                value: _maxResults.toDouble(), min: 5, max: 25, divisions: 4,
                activeColor: const Color(0xFF6366F1),
                onChanged: (v) => setState(() => _maxResults = v.toInt()),
              ),
            ),
          ]),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _searchLinkedIn,
              child: _loading
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    const SizedBox(width: 10),
                    Text(_statusSub.isNotEmpty ? _statusSub : 'Aranıyor...'),
                  ])
                : const Text('Ara'),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildCvStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(
          onPressed: () => setState(() => _step = 0),
          icon: const Icon(Icons.arrow_back, size: 20, color: Color(0xFF64748B)),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('CV Bilgisi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0))),
          Text('${_jobs.length} ilan hazır · CV\'nizi girin', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
        ])),
      ]),
      const SizedBox(height: 16),

      // Job summary
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.15)),
        ),
        child: Row(children: [
          const Icon(Icons.work_outline, color: Color(0xFF818CF8), size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(
            '${_jobs.length} ilan · "${_queryCtrl.text}" · ${_locationCtrl.text}',
            style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12),
          )),
        ]),
      ),

      const SizedBox(height: 16),

      // File upload
      InkWell(
        onTap: _pickCvFile,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Row(children: [
            const Icon(Icons.upload_file, color: Color(0xFF818CF8), size: 28),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _cvFileName.isNotEmpty ? '📄 $_cvFileName' : '📄 CV Dosyası Yükle',
                style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              const Text('PDF, TXT, MD desteklenir', style: TextStyle(color: Color(0xFF475569), fontSize: 11)),
            ])),
          ]),
        ),
      ),

      const SizedBox(height: 10),
      const Center(child: Text('— veya yapıştırın —', style: TextStyle(color: Color(0xFF334155), fontSize: 11))),
      const SizedBox(height: 10),

      TextField(
        controller: _cvCtrl,
        maxLines: 14,
        decoration: const InputDecoration(hintText: 'CV içeriğinizi buraya yapıştırın...\n\nİsim, pozisyon, deneyim, beceriler...'),
        style: const TextStyle(fontSize: 12, height: 1.6),
      ),

      const SizedBox(height: 16),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _cvCtrl.text.trim().isNotEmpty ? _startAnalysis : null,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text('${_jobs.length} İlanı Analiz Et'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ),

      const SizedBox(height: 8),
      const Center(child: Text('CV kaydedilir, bir daha girmenize gerek kalmaz', style: TextStyle(color: Color(0xFF334155), fontSize: 11))),
    ]);
  }

  Widget _buildAnalyzing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 80, height: 80,
            child: CircularProgressIndicator(
              value: _progress > 0 ? _progress : null,
              strokeWidth: 4,
              color: const Color(0xFF6366F1),
              backgroundColor: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 28),
          Text(_statusText, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 16, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(_statusSub, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13)),
          const SizedBox(height: 16),
          Text('${(_progress * 100).toInt()}%', style: const TextStyle(color: Color(0xFF475569), fontSize: 12)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress, minHeight: 6,
              color: const Color(0xFF6366F1), backgroundColor: const Color(0xFF1E293B),
            ),
          ),
        ]),
      ),
    );
  }

  void _launchUrl(String url) async {
    // url_launcher kullan
  }
}