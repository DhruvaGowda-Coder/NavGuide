import 'dart:convert';
import 'dart:io';
import '../../domain/route_safety_models.dart';

/// Provider for real-time and forecast weather telemetry from Open-Meteo.
///
/// Fully open, scientific weather model without API key requirements.
class WeatherProvider {
  WeatherProvider({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// Fetches real-time weather and precipitation probability for given coordinates.
  Future<WeatherInfo> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current=temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,wind_speed_10m'
      '&hourly=precipitation_probability'
      '&forecast_days=1',
    );

    try {
      final request = await _client.getUrl(uri).timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return const WeatherInfo(
          weatherDescription: 'Station Unavailable',
          isLive: false,
          source: 'Open-Meteo (HTTP Error)',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final current = json['current'] as Map<String, dynamic>?;
      if (current == null) return WeatherInfo.unknown;

      final temp = (current['temperature_2m'] as num?)?.toDouble();
      final humidity = (current['relative_humidity_2m'] as num?)?.toDouble();
      final rain = (current['rain'] as num?)?.toDouble() ??
          (current['precipitation'] as num?)?.toDouble();
      final wind = (current['wind_speed_10m'] as num?)?.toDouble();
      final code = current['weather_code'] as int?;

      // Find current hour precipitation probability
      int? precipProb;
      final hourly = json['hourly'] as Map<String, dynamic>?;
      if (hourly != null) {
        final probs = hourly['precipitation_probability'] as List<dynamic>?;
        if (probs != null && probs.isNotEmpty) {
          final nowHour = DateTime.now().toUtc().hour;
          if (nowHour >= 0 && nowHour < probs.length) {
            precipProb = (probs[nowHour] as num?)?.toInt();
          } else {
            precipProb = (probs.first as num?)?.toInt();
          }
        }
      }

      return WeatherInfo(
        temperatureC: temp,
        relativeHumidity: humidity,
        rainfallMmPerHour: rain,
        precipitationProbabilityPercent: precipProb,
        windSpeedKmh: wind,
        wmoWeatherCode: code,
        weatherDescription: WeatherInfo.describeWmoCode(code),
        isSevereWeatherAlert: WeatherInfo.isSevereWmo(code),
        isLive: true,
        source: 'Open-Meteo ECMWF / DWD Model',
      );
    } catch (_) {
      return const WeatherInfo(
        weatherDescription: 'Network Timeout / Offline',
        isLive: false,
        source: 'Open-Meteo (Offline Fallback)',
      );
    }
  }

  /// Closes internal client when needed.
  void dispose() {
    _client.close(force: true);
  }
}
