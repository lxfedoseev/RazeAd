/**
 * Copyright (c) 2018 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
 * distribute, sublicense, create a derivative work, and/or sell copies of the
 * Software in any work that is designed, intended, or marketed for pedagogical or
 * instructional purposes related to programming, coding, application development,
 * or information technology.  Permission for such use, copying, modification,
 * merger, publication, distribution, sublicensing, creation of derivative works,
 * or sale is expressly withheld.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import Foundation
import CoreLocation

protocol LocationManagerDelegate {
  func locationManager(_ locationManager: LocationManager, didEnterRegionId regionId: String)
  func locationManager(_ locationManager: LocationManager, didExitRegionId regionId: String)

  func locationManager(_ locationManager: LocationManager, didRangeBeacon beacon: CLBeacon)
  func locationManager(_ locationManager: LocationManager, didLeaveBeacon beacon: CLBeacon)
}

class LocationManager: NSObject {
  enum GeofencingError: Error {
    case notAuthorized
    case notSupported
  }

  var locationManager: CLLocationManager
  var delegate: LocationManagerDelegate?
  var trackedLocation: CLLocationCoordinate2D?

  override init() {
    locationManager = CLLocationManager()
    super.init()
  }
    
    func initialize() {
        // 1
        locationManager.delegate = self
        // 2
        locationManager.activityType = .otherNavigation
        // Geofencing requires always authorization
        // 3
        locationManager.requestAlwaysAuthorization()
        // 4
        locationManager.startUpdatingLocation()
    }
    
    func startMonitoring(location: CLLocationCoordinate2D,
                         radius: Double, identifier: String) throws {
        // 1
        guard CLLocationManager.isMonitoringAvailable(
            for: CLCircularRegion.self)
            else  { throw GeofencingError.notSupported }
        guard CLLocationManager.authorizationStatus() ==
            .authorizedAlways
            else { throw GeofencingError.notAuthorized }
        trackedLocation = location
        // 2
        let region = CLCircularRegion(center: location,
                                      radius: radius, identifier: identifier)
        // 3
        region.notifyOnEntry = true
        region.notifyOnExit = true
        // 4
        locationManager.startMonitoring(for: region)
        // 5
        // Delay state request by 1 second due to an old bug
        // http://www.openradar.me/16986842
        DispatchQueue.main
            .asyncAfter(deadline:  DispatchTime.now() +
                DispatchTimeInterval.seconds(1),
                        qos: .default, flags: []) {
                            self.locationManager.requestState(for: region)
        }
    }
    
    func stopMonitoringRegions() {
        trackedLocation = nil
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
    }
    
}

// MARK: - Beacons
extension LocationManager {
    
    // 1
    func startMonitoring(beacons: [CLBeaconRegion]) {
        for beacon in beacons {
            startMonitoring(beacon: beacon)
        }
    }
    // 2
    func startMonitoring(beacon: CLBeaconRegion) {
        guard CLLocationManager.isRangingAvailable() else {
            print("[ERROR] Beacon ranging is not available")
            return
        }
        locationManager.startMonitoring(for: beacon)
    }
    
    func stopMonitoring(beacons: [CLBeaconRegion]) {
        for beacon in beacons {
            stopMonitoring(beacon: beacon)
        }
    }
    func stopMonitoring(beacon: CLBeaconRegion) {
        locationManager.stopRangingBeacons(in: beacon)
        locationManager.stopMonitoring(for: beacon)
    }
    
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        // 1
        guard let currentLocation = locations.last else { return }
        // 2
        guard let trackedLocation = trackedLocation else { return }
        let location = CLLocation(latitude: trackedLocation.latitude,
                                  longitude: trackedLocation.longitude)
        // 3
        let distance = currentLocation.distance(from: location)
        print("Distance: \(distance)")
    }
    
    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        print("Authorization status changed to: \(status)")
    }
    
    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        print("Location manager failed with error: " +
            "\(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager,
                         didDetermineState state: CLRegionState,
                         for region: CLRegion) {
        switch state {
        // 1
        case .inside:
            locationManager(manager, didEnterRegion: region)
        // 2
        case .outside, .unknown:
            break
        } }
    
    func locationManager(_ manager: CLLocationManager,
                         didEnterRegion region: CLRegion) {
        if let region = region as? CLBeaconRegion {
            print("Entered in beacon region: \(region)")
            locationManager.startRangingBeacons(in: region)
        } else {
            print("Entered in region: \(region)")
            delegate?.locationManager(
                self, didEnterRegionId: region.identifier)
        }
    }
    
    func locationManager(_ manager: CLLocationManager,
                         didExitRegion region: CLRegion) {
        print("Left region \(region)")
        delegate?.locationManager(
            self, didExitRegionId: region.identifier)
    }
    
    func locationManager(_ manager: CLLocationManager,
                         monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        print("Geofencing monitoring failed for region " +
            "\(String(describing: region?.identifier))," +
            "error: \(error.localizedDescription)")
    }
    
    // MARK: Beacons
    // 1
    func locationManager(_ manager: CLLocationManager,
                         didRangeBeacons beacons: [CLBeacon],
                         in region: CLBeaconRegion) {
        for beacon in beacons {
            delegate?.locationManager(self, didRangeBeacon: beacon)
        }
    }
    // 2
    func locationManager(_ manager: CLLocationManager,
                         rangingBeaconsDidFailFor region: CLBeaconRegion,
                         withError error: Error) {
        print("Beacon ranging failed for region \(region) " +
            "with error: \(error.localizedDescription)")
    }
    
    
}
