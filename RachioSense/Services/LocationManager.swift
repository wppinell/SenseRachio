import Foundation
import CoreLocation
import os

/// Manages location services for weather fetching.
/// Falls back to user-configured location if permission denied.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    private static let logger = Logger(subsystem: "com.rachiosense", category: "LocationManager")
    
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    
    // Default fallback (Phoenix, AZ) — can be overridden in Settings
    private let defaultLatitudeKey = "weather_latitude"
    private let defaultLongitudeKey = "weather_longitude"
    
    private let phoenixLatitude = 33.4484
    private let phoenixLongitude = -112.0740
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // Don't need precise
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Public API
    
    /// Get the best available location: current location if permitted, else user-configured, else Phoenix.
    func getLocation() async -> CLLocationCoordinate2D {
        // If we have a cached current location from this session, use it
        if let current = currentLocation {
            return current
        }
        
        // Check authorization
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Request a fresh location
            if let location = await requestLocation() {
                currentLocation = location
                Self.logger.info("Using device location: \(location.latitude), \(location.longitude)")
                return location
            }
            
        case .notDetermined:
            // Request permission
            locationManager.requestWhenInUseAuthorization()
            // Don't block — fall through to configured/default
            
        case .denied, .restricted:
            Self.logger.info("Location permission denied, using fallback")
            
        @unknown default:
            break
        }
        
        // Fall back to user-configured or default
        return getConfiguredLocation()
    }
    
    /// Get the user-configured location (from Settings) or default Phoenix.
    func getConfiguredLocation() -> CLLocationCoordinate2D {
        let defaults = UserDefaults.standard
        let lat = defaults.double(forKey: defaultLatitudeKey)
        let lon = defaults.double(forKey: defaultLongitudeKey)
        
        if lat != 0 && lon != 0 {
            Self.logger.debug("Using configured location: \(lat), \(lon)")
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        Self.logger.debug("Using default Phoenix location")
        return CLLocationCoordinate2D(latitude: phoenixLatitude, longitude: phoenixLongitude)
    }
    
    /// Save a custom location to UserDefaults (from Settings).
    func setConfiguredLocation(latitude: Double, longitude: Double) {
        UserDefaults.standard.set(latitude, forKey: defaultLatitudeKey)
        UserDefaults.standard.set(longitude, forKey: defaultLongitudeKey)
        Self.logger.info("Saved configured location: \(latitude), \(longitude)")
    }
    
    /// Request permission explicitly (e.g., from Settings).
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Private
    
    private func requestLocation() async -> CLLocationCoordinate2D? {
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
            
            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let cont = locationContinuation {
                    locationContinuation = nil
                    cont.resume(returning: nil)
                    Self.logger.warning("Location request timed out")
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: location.coordinate)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: nil)
            }
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
