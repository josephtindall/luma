class InstanceSettings {
  final String name;
  final String contentWidth; // "narrow" | "wide" | "max"
  final int passwordMinLength;
  final bool passwordRequireUppercase;
  final bool passwordRequireLowercase;
  final bool passwordRequireNumbers;
  final bool passwordRequireSymbols;
  final int passwordHistoryCount;
  final bool showGithubButton;
  final bool showDonateButton;

  const InstanceSettings({
    required this.name,
    required this.contentWidth,
    required this.passwordMinLength,
    required this.passwordRequireUppercase,
    required this.passwordRequireLowercase,
    required this.passwordRequireNumbers,
    required this.passwordRequireSymbols,
    required this.passwordHistoryCount,
    required this.showGithubButton,
    required this.showDonateButton,
  });

  factory InstanceSettings.fromJson(Map<String, dynamic> json) {
    return InstanceSettings(
      name: json['name'] as String? ?? '',
      contentWidth: json['content_width'] as String? ?? 'wide',
      passwordMinLength: json['password_min_length'] as int? ?? 8,
      passwordRequireUppercase:
          json['password_require_uppercase'] as bool? ?? false,
      passwordRequireLowercase:
          json['password_require_lowercase'] as bool? ?? false,
      passwordRequireNumbers: json['password_require_numbers'] as bool? ?? false,
      passwordRequireSymbols: json['password_require_symbols'] as bool? ?? false,
      passwordHistoryCount: json['password_history_count'] as int? ?? 0,
      showGithubButton: json['show_github_button'] as bool? ?? true,
      showDonateButton: json['show_donate_button'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'content_width': contentWidth,
        'password_min_length': passwordMinLength,
        'password_require_uppercase': passwordRequireUppercase,
        'password_require_lowercase': passwordRequireLowercase,
        'password_require_numbers': passwordRequireNumbers,
        'password_require_symbols': passwordRequireSymbols,
        'password_history_count': passwordHistoryCount,
        'show_github_button': showGithubButton,
        'show_donate_button': showDonateButton,
      };

  InstanceSettings copyWith({
    String? name,
    String? contentWidth,
    int? passwordMinLength,
    bool? passwordRequireUppercase,
    bool? passwordRequireLowercase,
    bool? passwordRequireNumbers,
    bool? passwordRequireSymbols,
    int? passwordHistoryCount,
    bool? showGithubButton,
    bool? showDonateButton,
  }) {
    return InstanceSettings(
      name: name ?? this.name,
      contentWidth: contentWidth ?? this.contentWidth,
      passwordMinLength: passwordMinLength ?? this.passwordMinLength,
      passwordRequireUppercase:
          passwordRequireUppercase ?? this.passwordRequireUppercase,
      passwordRequireLowercase:
          passwordRequireLowercase ?? this.passwordRequireLowercase,
      passwordRequireNumbers:
          passwordRequireNumbers ?? this.passwordRequireNumbers,
      passwordRequireSymbols:
          passwordRequireSymbols ?? this.passwordRequireSymbols,
      passwordHistoryCount: passwordHistoryCount ?? this.passwordHistoryCount,
      showGithubButton: showGithubButton ?? this.showGithubButton,
      showDonateButton: showDonateButton ?? this.showDonateButton,
    );
  }
}
