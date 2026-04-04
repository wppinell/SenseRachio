import Foundation
import CoreLocation

/// Weather service using Open-Meteo API (free, no API key required)
final class WeatherAPI {
    static let shared = WeatherAPI()

    private let session: URLSession
    private let baseURL = "https://api.open-meteo.com/v1/forecast"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }
    
    struct Forecast: Sendable {
        let current: CurrentWeather
        let daily: [DailyForecast]
    }
    
    struct CurrentWeather: Sendable {
        let temperature: Double  // Fahrenheit
        let humidity: Int
        let weatherCode: Int
        let description: String
        let icon: String
    }
    
    struct DailyForecast: Sendable, Identifiable {
        var id: Date { date }
        let date: Date
        let highTemp: Double  // Fahrenheit
        let lowTemp: Double   // Fahrenheit
        let weatherCode: Int
        let icon: String
        let precipitationInches: Double?
    }
    
    /// Fetch 7-day forecast for a location
    func fetchForecast(latitude: Double, longitude: Double) async throws -> Forecast {
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7")
        ]

        guard let url = components?.url else {
            throw WeatherError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherError.apiError(statusCode: nil)
        }
        guard httpResponse.statusCode == 200 else {
            throw WeatherError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Parse current weather
        guard let currentData = json?["current"] as? [String: Any],
              let currentTemp = currentData["temperature_2m"] as? Double,
              let humidity = currentData["relative_humidity_2m"] as? Int,
              let weatherCode = currentData["weather_code"] as? Int else {
            throw WeatherError.parseError(field: "current")
        }
        
        let current = CurrentWeather(
            temperature: currentTemp,
            humidity: humidity,
            weatherCode: weatherCode,
            description: weatherDescription(for: weatherCode),
            icon: weatherIcon(for: weatherCode)
        )
        
        // Parse daily forecast
        guard let dailyData = json?["daily"] as? [String: Any],
              let dates = dailyData["time"] as? [String],
              let highs = dailyData["temperature_2m_max"] as? [Double],
              let lows = dailyData["temperature_2m_min"] as? [Double],
              let codes = dailyData["weather_code"] as? [Int],
              let precip = dailyData["precipitation_sum"] as? [Double] else {
            throw WeatherError.parseError(field: "daily")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var daily: [DailyForecast] = []
        for i in 0..<min(dates.count, 7) {
            guard let date = dateFormatter.date(from: dates[i]) else { continue }
            let precipAmount = precip[i] > 0 ? precip[i] : nil
            daily.append(DailyForecast(
                date: date,
                highTemp: highs[i],
                lowTemp: lows[i],
                weatherCode: codes[i],
                icon: weatherIcon(for: codes[i]),
                precipitationInches: precipAmount
            ))
        }
        
        return Forecast(current: current, daily: daily)
    }
    
    // MARK: - Weather Code Mapping (WMO codes)
    
    private func weatherIcon(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"                    // Clear sky
        case 1, 2, 3: return "cloud.sun.fill"            // Partly cloudy
        case 45, 48: return "cloud.fog.fill"             // Fog
        case 51, 53, 55: return "cloud.drizzle.fill"     // Drizzle
        case 56, 57: return "cloud.sleet.fill"           // Freezing drizzle
        case 61, 63, 65: return "cloud.rain.fill"        // Rain
        case 66, 67: return "cloud.sleet.fill"           // Freezing rain
        case 71, 73, 75: return "cloud.snow.fill"        // Snow
        case 77: return "cloud.snow.fill"                // Snow grains
        case 80, 81, 82: return "cloud.heavyrain.fill"   // Rain showers
        case 85, 86: return "cloud.snow.fill"            // Snow showers
        case 95: return "cloud.bolt.fill"                // Thunderstorm
        case 96, 99: return "cloud.bolt.rain.fill"       // Thunderstorm with hail
        default: return "cloud.fill"
        }
    }
    
    private func weatherDescription(for code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }
    
    enum WeatherError: Error, LocalizedError {
        case invalidURL
        case apiError(statusCode: Int?)
        case parseError(field: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Could not construct a valid URL for the weather API."
            case .apiError(let code):
                if let code { return "Weather API returned HTTP \(code)." }
                return "Invalid response from weather API."
            case .parseError(let field):
                return "Failed to parse '\(field)' from weather API response."
            }
        }
    }
}
