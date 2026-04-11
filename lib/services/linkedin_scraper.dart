import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../../models.dart';

class LinkedInScraper {
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,tr;q=0.8',
    'Accept-Encoding': 'gzip, deflate',
    'Connection': 'keep-alive',
  };

  /// LinkedIn'de iş ara — public guest API kullanır, login gerektirmez
  static Future<List<JobListing>> searchJobs(
    String query,
    String location, {
    int maxResults = 25,
    Function(int loaded)? onProgress,
  }) async {
    final jobs = <JobListing>[];
    final seenUrls = <String>{};

    for (int start = 0; start < maxResults; start += 25) {
      final q = Uri.encodeComponent(query);
      final loc = Uri.encodeComponent(location);
      final url = 'https://www.linkedin.com/jobs-guest/jobs/api/sideBarJobCount?keywords=$q&location=$loc&start=$start';

      // Ana sayfa ilanlarını çek
      final searchUrl = 'https://www.linkedin.com/jobs/search?keywords=$q&location=$loc&start=$start';

      try {
        final resp = await http.get(Uri.parse(searchUrl), headers: _headers)
            .timeout(const Duration(seconds: 30));

        if (resp.statusCode != 200) break;

        final doc = html_parser.parse(resp.body);
        final cards = doc.querySelectorAll('div.base-card, li.result-card, div.job-search-card');

        if (cards.isEmpty) break;

        for (final card in cards) {
          final titleEl = card.querySelector('h3, h4, a.base-card__full-link');
          final linkEl = card.querySelector('a[href*="/jobs/view/"]');
          final companyEl = card.querySelector('h4.base-search-card__subtitle, a.hidden-nested-link');
          final locEl = card.querySelector('span.job-search-card__location');

          final jobUrl = linkEl?.attributes['href']?.split('?').first ?? '';
          if (jobUrl.isEmpty || seenUrls.contains(jobUrl)) continue;
          seenUrls.add(jobUrl);

          jobs.add(JobListing(
            title: titleEl?.text.trim() ?? '?',
            company: companyEl?.text.trim() ?? '?',
            location: locEl?.text.trim() ?? '',
            url: jobUrl,
          ));

          if (jobs.length >= maxResults) break;
        }

        onProgress?.call(jobs.length);
        if (jobs.length >= maxResults) break;

        // Rate limit
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        break;
      }
    }

    return jobs;
  }

  /// İlan detayını çek — public sayfa
  static Future<JobListing> scrapeJobDetail(JobListing job) async {
    if (job.url.isEmpty) return job;

    try {
      final resp = await http.get(Uri.parse(job.url), headers: _headers)
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) return job;

      final doc = html_parser.parse(resp.body);

      // Açıklama
      final descEl = doc.querySelector(
        'div.description__text, '
        'div.show-more-less-html__markup, '
        'div.jobs-description__content, '
        'section.show-more-less-html'
      );

      if (descEl != null) {
        job.description = descEl.text.trim();
      }

      // Başlık güncelle
      final titleEl = doc.querySelector('h1.top-card-layout__title, h1.topcard__title, h1');
      if (titleEl != null && titleEl.text.trim().isNotEmpty) {
        job = JobListing(
          title: titleEl.text.trim(),
          company: job.company,
          location: job.location,
          url: job.url,
          description: job.description,
        );
      }
    } catch (_) {}

    return job;
  }

  /// JSON dosyasından ilanları yükle (scraper çıktısı)
  static List<JobListing> loadFromJson(String jsonString) {
    final data = jsonDecode(jsonString);
    final list = data is List ? data : [data];
    return list.map((j) => JobListing.fromJson(j as Map<String, dynamic>)).toList();
  }
}
