import CoreLocation
import MapKit

actor GeocodingService {
    static let shared = GeocodingService()
    private var cache: [String: (city: String?, country: String?, countryCode: String?)] = [:]

    private func cacheKey(_ lat: Double, _ lng: Double) -> String {
        let rlat = (lat * 100).rounded() / 100
        let rlng = (lng * 100).rounded() / 100
        return "\(rlat),\(rlng)"
    }

    func reverseGeocode(lat: Double, lng: Double) async -> (city: String?, country: String?, countryCode: String?) {
        let key = cacheKey(lat, lng)
        if let cached = cache[key] { return cached }

        let location = CLLocation(latitude: lat, longitude: lng)
        do {
            let result: (String?, String?, String?)
            if #available(iOS 26, *) {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    return (nil, nil, nil)
                }
                let items = try await request.mapItems
                let item = items.first
                let addr = item?.addressRepresentations
                let regionCode = addr?.region?.identifier.uppercased()
                result = (addr?.cityName, addr?.regionName, regionCode)
            } else {
                let geocoder = CLGeocoder()
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                let pm = placemarks.first
                result = (pm?.locality, pm?.country, pm?.isoCountryCode?.uppercased())
            }
            cache[key] = result
            try await Task.sleep(for: .seconds(1))
            return result
        } catch {
            return (nil, nil, nil)
        }
    }
}
