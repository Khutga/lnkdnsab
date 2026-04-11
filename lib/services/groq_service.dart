import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

class GroqService {
  static const _url = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'llama-3.3-70b-versatile';

  static Future<AnalysisResult> analyze({
    required String jobTitle,
    required String jobCompany,
    required String jobDescription,
    required String cvText,
    required String apiKey,
    String jobLocation = '',
    String jobUrl = '',
  }) async {
    final desc = jobDescription.length > 2500
        ? jobDescription.substring(0, 2500) : jobDescription;
    final cv = cvText.length > 2500
        ? cvText.substring(0, 2500) : cvText;

    final prompt = '''Sen bir CV analiz uzmanısın. İş ilanındaki gereksinimleri CV ile karşılaştır.

ÖNEMLİ KURALLAR:
- Bir skill ASLA hem matching hem missing listesinde olamaz.
- CV'de olan skill = matching. CV'de OLMAYAN skill = missing.
- Büyük/küçük harf ve eş anlamlılar dikkate al: "SQL" ve "sql" aynıdır, "Git" ve "Version Control (Git)" aynıdır.
- Sadece ilanda açıkça istenen teknik ve soft skill'leri listele.
- match_percentage: matching / (matching + missing) * 100 olarak hesapla.
- Türkçe yaz.

İŞ İLANI:
Pozisyon: $jobTitle
Şirket: $jobCompany
$desc

ADAY CV:
$cv

SADECE bu JSON formatında yanıt ver:
{
  "position": "$jobTitle",
  "company": "$jobCompany",
  "matching_skills": ["CV'de BULUNAN ilanda istenen skill'ler"],
  "missing_skills": ["CV'de BULUNMAYAN ilanda istenen skill'ler"],
  "match_percentage": 0,
  "suggestions": ["İş başvurusu için 2-3 somut öneri türkçe"],
  "cv_additions": ["CV'ye eklenmesi gereken 2-3 somut madde türkçe"],
  "summary": "2 cümlelik kısa değerlendirme türkçe"
}''';

    try {
      final resp = await _callWithRetry(apiKey, prompt);
      final data = jsonDecode(resp.body);

      if (resp.statusCode != 200) {
        return _errorResult(
          jobTitle, jobCompany, jobLocation, jobUrl,
          data['error']?['message'] ?? 'HTTP ${resp.statusCode}',
        );
      }

      final raw = data['choices'][0]['message']['content'] as String;
      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final parsed = jsonDecode(clean) as Map<String, dynamic>;

      parsed['_title'] = jobTitle;
      parsed['_company'] = jobCompany;
      parsed['_location'] = jobLocation;
      parsed['_url'] = jobUrl;

      return AnalysisResult.fromJson(parsed);
    } catch (e) {
      return _errorResult(jobTitle, jobCompany, jobLocation, jobUrl, e.toString());
    }
  }

  static Future<http.Response> _callWithRetry(String apiKey, String prompt, {int retries = 2}) async {
    for (int i = 0; i <= retries; i++) {
      final resp = await http.post(
        Uri.parse(_url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [{'role': 'user', 'content': prompt}],
          'temperature': 0.3,
          'response_format': {'type': 'json_object'},
        }),
      ).timeout(const Duration(seconds: 90));

      if (resp.statusCode == 429 && i < retries) {
        await Future.delayed(const Duration(seconds: 8));
        continue;
      }

      return resp;
    }

    throw Exception('Rate limit aşıldı');
  }

  static AnalysisResult _errorResult(String title, String company, String location, String url, String error) {
    return AnalysisResult(
      position: title,
      company: company,
      location: location,
      url: url,
      matchingSkills: [],
      missingSkills: [],
      matchPercentage: 0,
      suggestions: [],
      cvAdditions: [],
      summary: 'Hata: $error',
      error: error,
    );
  }

  /// CV'yi ilana göre yeniden düzenle ve geliştir
  static Future<String> improveCv({
    required String currentCv,
    required String jobTitle,
    required String jobCompany,
    required String jobDescription,
    required List<String> missingSkills,
    required List<String> matchingSkills,
    required List<String> suggestions,
    required String apiKey,
  }) async {
    final desc = jobDescription.length > 2000
        ? jobDescription.substring(0, 2000) : jobDescription;

    final prompt = '''Sen profesyonel bir CV yazarısın. Adayın mevcut CV'sini aşağıdaki iş ilanına göre optimize et.

KURALLAR:
- Mevcut CV'nin yapısını ve gerçek bilgileri koru. UYDURMA deneyim veya skill EKLEME.
- Adayın mevcut deneyimlerini ilanla alakalı hale getir — aynı deneyimleri ilana uygun anahtar kelimelerle yeniden ifade et.
- Summary/özet kısmını ilana özel yaz.
- Mevcut skill listesini ilana uygun sırala, ilgili olanları öne çıkar.
- Eğer adayın deneyimlerinde dolaylı olarak ilgili beceriler varsa bunları vurgula.
- Profesyonel, ATS-uyumlu format kullan.
- Türkçe ve İngilizce karışık olabilir (ilanın diline göre).

İŞ İLANI:
$jobTitle @ $jobCompany
$desc

ADAYIN MEVCUT CV'Sİ:
$currentCv

İLANDA İSTENEN AMA CV'DE EKSİK BECERİLER:
${missingSkills.join(', ')}

CV'DE ZATEN EŞLEŞEN BECERİLER:
${matchingSkills.join(', ')}

Şimdi adayın CV'sini bu ilana optimize edilmiş şekilde yeniden yaz. Sadece CV metnini yaz, açıklama ekleme.''';

    try {
      final resp = await http.post(
        Uri.parse(_url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [{'role': 'user', 'content': prompt}],
          'temperature': 0.4,
          'max_tokens': 2000,
        }),
      ).timeout(const Duration(seconds: 120));

      if (resp.statusCode == 429) {
        await Future.delayed(const Duration(seconds: 8));
        return improveCv(
          currentCv: currentCv, jobTitle: jobTitle, jobCompany: jobCompany,
          jobDescription: jobDescription, missingSkills: missingSkills,
          matchingSkills: matchingSkills, suggestions: suggestions, apiKey: apiKey,
        );
      }

      final data = jsonDecode(resp.body);
      if (resp.statusCode != 200) {
        throw Exception(data['error']?['message'] ?? 'HTTP ${resp.statusCode}');
      }

      return data['choices'][0]['message']['content'] as String;
    } catch (e) {
      throw Exception('CV oluşturma hatası: $e');
    }
  }
}