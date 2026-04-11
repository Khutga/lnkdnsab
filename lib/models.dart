class JobListing {
  final String title;
  final String company;
  final String location;
  final String url;
  String? description;

  JobListing({
    required this.title,
    required this.company,
    required this.location,
    required this.url,
    this.description,
  });

  factory JobListing.fromJson(Map<String, dynamic> json) => JobListing(
    title: json['title'] ?? '?',
    company: json['company'] ?? '?',
    location: json['location'] ?? '',
    url: json['url'] ?? '',
    description: json['description'],
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'company': company,
    'location': location,
    'url': url,
    'description': description,
  };
}

class AnalysisResult {
  final String position;
  final String company;
  final String location;
  final String url;
  final List<String> matchingSkills;
  final List<String> missingSkills;
  final int matchPercentage;
  final List<String> suggestions;
  final List<String> cvAdditions;
  final String summary;
  final String? error;

  AnalysisResult({
    required this.position,
    required this.company,
    this.location = '',
    this.url = '',
    required this.matchingSkills,
    required this.missingSkills,
    required this.matchPercentage,
    required this.suggestions,
    required this.cvAdditions,
    required this.summary,
    this.error,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) => AnalysisResult(
    position: json['_title'] ?? json['position'] ?? '?',
    company: json['_company'] ?? json['company'] ?? '?',
    location: json['_location'] ?? '',
    url: json['_url'] ?? '',
    matchingSkills: List<String>.from(json['matching_skills'] ?? []),
    missingSkills: List<String>.from(json['missing_skills'] ?? []),
    matchPercentage: (json['match_percentage'] ?? 0).toInt(),
    suggestions: List<String>.from(json['suggestions'] ?? []),
    cvAdditions: List<String>.from(json['cv_additions'] ?? []),
    summary: json['summary'] ?? '',
    error: json['error'],
  );
}
