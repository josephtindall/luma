class InstanceSettings {
  final String name;
  final int passwordMinLength;
  final bool passwordRequireUppercase;
  final bool passwordRequireLowercase;
  final bool passwordRequireNumbers;
  final bool passwordRequireSymbols;
  final int passwordHistoryCount;

  const InstanceSettings({
    required this.name,
    required this.passwordMinLength,
    required this.passwordRequireUppercase,
    required this.passwordRequireLowercase,
    required this.passwordRequireNumbers,
    required this.passwordRequireSymbols,
    required this.passwordHistoryCount,
  });

  factory InstanceSettings.fromJson(Map<String, dynamic> json) {
    return InstanceSettings(
      name: json['name'] as String? ?? '',
      passwordMinLength: json['password_min_length'] as int? ?? 8,
      passwordRequireUppercase:
          json['password_require_uppercase'] as bool? ?? false,
      passwordRequireLowercase:
          json['password_require_lowercase'] as bool? ?? false,
      passwordRequireNumbers: json['password_require_numbers'] as bool? ?? false,
      passwordRequireSymbols: json['password_require_symbols'] as bool? ?? false,
      passwordHistoryCount: json['password_history_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'password_min_length': passwordMinLength,
        'password_require_uppercase': passwordRequireUppercase,
        'password_require_lowercase': passwordRequireLowercase,
        'password_require_numbers': passwordRequireNumbers,
        'password_require_symbols': passwordRequireSymbols,
        'password_history_count': passwordHistoryCount,
      };

  InstanceSettings copyWith({
    String? name,
    int? passwordMinLength,
    bool? passwordRequireUppercase,
    bool? passwordRequireLowercase,
    bool? passwordRequireNumbers,
    bool? passwordRequireSymbols,
    int? passwordHistoryCount,
  }) {
    return InstanceSettings(
      name: name ?? this.name,
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
    );
  }
}
