//
//  ViewController.swift
//  UberIntegration
//
//  Created by ln-mac-03 on 03/02/17.
//  Copyright © 2017 ln-mac-03. All rights reserved.
//

import UIKit
import MapKit
import GooglePlaces
import GooglePlacePicker
import GoogleMaps
import UberRides

class ViewController: UIViewController {

    @IBOutlet var mapView: MKMapView!
    
    // Used for location buttons
    enum Location: Int {
        case Current = 0, Destination
    }
    
    var selectedLocation: Location = .Current
    
    @IBOutlet var currentLocationButton: UIButton!
    @IBOutlet var destinationButton: UIButton!
    @IBOutlet var requestRideButton: UIButton!
    
    @IBOutlet var pickupTimeLabel: UILabel!
    @IBOutlet var costLabel: UILabel!
    
    // Destination Annotation
    var destAnnotation: MKPointAnnotation = MKPointAnnotation()
    
    // Uber variables
    @IBOutlet var rideRequestView: UIView!
    
    var rideRequestButton = RideRequestButton()
    let ridesClient = RidesClient()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        LocationService.shareManager.delegate = self
        LocationService.shareManager.requestLocation()
        
        // Calculate request container view
        rideRequestView.layoutIfNeeded()
        
        // Size uber button to its container view
        var frame = rideRequestView.frame
        frame.origin = .zero
        rideRequestButton.frame = frame

        // Add uber button to its container view
        rideRequestView.addSubview(rideRequestButton)
        
        // Request button
        requestRideButton.addTarget(self, action: #selector(requestRide), for: .touchUpInside)
        
        // Show user location
        mapView.showsUserLocation = true
    }

    override func viewDidAppear(_ animated: Bool) {
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    @IBAction func changeAddressButton(_ sender: UIButton) {
        selectedLocation = Location(rawValue: sender.tag)!
        let autocompleteController = GMSAutocompleteViewController()
        autocompleteController.delegate = self
        present(autocompleteController, animated: true, completion: nil)
    }
}

extension ViewController: LocationServiceDelegate {
    func tracingLocation(currentLocation: CLLocation) {
        let center = CLLocationCoordinate2D(latitude: currentLocation.coordinate.latitude,
                                            longitude: currentLocation.coordinate.longitude)
        
        let region = MKCoordinateRegion(center: center,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01,
                                                               longitudeDelta: 0.01))
        
        self.mapView.setRegion(region, animated: true)
        
        updateEstLabels()
        
        // Update rideRequestButton with details with given location
        //        ridesClient.fetchCheapestProduct(pickupLocation: currentLocation, completion: { product, response in
        //            if let productID = product?.productID {
        //                let builder = RideParametersBuilder().setPickupLocation(currentLocation).setProductID(productID)
        //                self.rideRequestButton.rideParameters = builder.build()
        //                self.rideRequestButton.loadRideInformation()
        //
        //            }
        //        })
        
        // Set current address
        GMSPlacesClient().currentPlace(callback: { (likelihoodList, error) in
            if let error = error {
                print("Pick Place error: \(error.localizedDescription)")
                return
            }
            
            if let likelihoods = likelihoodList?.likelihoods {
                if let place: GMSPlace = likelihoods.first?.place {
                    if let address = place.formattedAddress {
                        self.currentLocationButton.setTitle(self.formatAddress(string: address), for: .normal)
                    }
                }
            }
        })
    }
    
    func tracingLocationDidFailWithError(error: NSError) {
        
    }
}

//MARK: - Google Autocomplete Delegate
extension ViewController: GMSAutocompleteViewControllerDelegate {
    func viewController(_ viewController: GMSAutocompleteViewController, didAutocompleteWith place: GMSPlace) {
        let loc = LocationService.shareManager
        
        if let address = place.formattedAddress {
            let formattedAddress = self.formatAddress(string: address)
            
            if selectedLocation == .Current {
                currentLocationButton.setTitle(formattedAddress, for: .normal)
                loc.startingLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            } else if selectedLocation == .Destination {
                destinationButton.setTitle(formattedAddress, for: .normal)
                loc.destinationLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
                
                destAnnotation.coordinate = place.coordinate
                destAnnotation.title = place.name
                destAnnotation.subtitle = place.formattedAddress
                
                mapView.addAnnotation(destAnnotation)
                
                if let startingLocation = loc.startingLocation?.coordinate {
                    routePolylines(source: startingLocation, destination: place.coordinate)
                }
            }
        }
        
        updateEstLabels()
        
        //        ridesClient.fetchCheapestProduct(pickupLocation: loc.startingLocation!, completion: { product, response in
        //            if let productID = product?.productID {
        //                let builder = RideParametersBuilder().setPickupLocation(loc.startingLocation!).setProductID(productID)
        //
        //                if let loc = loc.destinationLocation {
        //                    _ = builder.setDropoffLocation(loc)
        //                }
        //
        //                self.rideRequestButton.rideParameters = builder.build()
        //
        //                self.rideRequestButton.loadRideInformation()
        //            }
        //        })
        
        self.dismiss(animated: true, completion: nil)
    }
    
    func viewController(_ viewController: GMSAutocompleteViewController, didFailAutocompleteWithError error: Error) {
        print("Error: ", error.localizedDescription)
    }
    
    func wasCancelled(_ viewController: GMSAutocompleteViewController) {
        dismiss(animated: true, completion: nil)
    }
    
    // Show the network activity indicator.
    func didRequestAutocompletePredictions(_ viewController: GMSAutocompleteViewController) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
    }
    
    // Hide the network activity indicator.
    func didUpdateAutocompletePredictions(_ viewController: GMSAutocompleteViewController) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = false
    }
    
    func routePolylines(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) {
        let sourcePlacemark = MKPlacemark(coordinate: source, addressDictionary: nil)
        let destinationPlacemark = MKPlacemark(coordinate: destination, addressDictionary: nil)
        
        let sourceMapItem = MKMapItem(placemark: sourcePlacemark)
        let destinationMapItem = MKMapItem(placemark: destinationPlacemark)
        
        let directionRequest = MKDirectionsRequest()
        directionRequest.source = sourceMapItem
        directionRequest.destination = destinationMapItem
        directionRequest.transportType = .automobile
        
        // Calculate the direction
        let directions = MKDirections(request: directionRequest)
        
        directions.calculate {
            (response, error) -> Void in
            
            guard let response = response else {
                if let error = error {
                    print("Error: \(error)")
                }
                
                return
            }
            
            let route = response.routes[0]
            self.mapView.add((route.polyline), level: .aboveRoads)
            
            let rect = route.polyline.boundingMapRect
            self.mapView.setRegion(MKCoordinateRegionForMapRect(rect), animated: true)
        }
    }
}

//MARK: - Map View Delegate
extension ViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let polylineRenderer = MKPolylineRenderer(overlay: overlay)
        polylineRenderer.strokeColor = UIColor.blue
        polylineRenderer.lineWidth = 5
        
        return polylineRenderer
    }
    
}

//MARK: - Helper Methods
extension ViewController {
    
    // Used to update the users current location
    func updatecurrentLocation() -> Bool {
        if CLLocationManager.locationServicesEnabled() {
            LocationService.shareManager.requestLocation()
            return true
        }
        
        return false
    }
    
    func updateEstLabels() {
        if let A = LocationService.shareManager.startingLocation {
            // ** Update Pickup Time Est Label
            ridesClient.fetchTimeEstimates(pickupLocation: A, completion: { (timeEstimates, response) in
                if let est = timeEstimates.first {
                    let min = (est.estimate / 60)
                    self.GCDMainQueue {
                        self.pickupTimeLabel.text = "\(min)m"
                    }
                }
            })
            
            // ** Update Cost Est label
            if let B = LocationService.shareManager.destinationLocation {
                ridesClient.fetchPriceEstimates(pickupLocation: A, dropoffLocation: B, completion: { (priceEstimate, response) in
                    if let est = priceEstimate.first?.estimate {
                        self.GCDMainQueue {
                            self.costLabel.text = "\(est)"
                        }
                    }
                })
            }
        }
    }
    
    func requestRide() {
        let shareManager = LocationService.shareManager
        
        if let A = shareManager.startingLocation, let B = shareManager.destinationLocation {
            ridesClient.fetchCheapestProduct(pickupLocation: A) { product, response in
                if let productID = product?.productID {
                    let build = RideParametersBuilder().setPickupLocation(A).setDropoffLocation(B).setProductID(productID).build()
                    self.ridesClient.requestRide(build, completion: { (ride, response) in
                        if let error = response.error {
                            if error.status == 401 {
                                let loginManager = LoginManager(loginType: .implicit)
                                loginManager.login(requestedScopes: [.Request], presentingViewController: self, completion: { token, error in
                                    
                                })
                            }
                        }
                        
                        if ride != nil {
                            
                        }
                    })
                }
            }
        }
    }
    
    func formatAddress(string: String) -> (String) {
        let range = string.range(of: ", ")
        
        return string.replacingOccurrences(of: ", ", with: "\n", options: String.CompareOptions(rawValue: UInt(0)), range: range)
    }
    
    func GCDBackgroundQueue(block:@escaping (() -> Void)) {
        DispatchQueue.global(qos: .background).async(execute: block)
    }
    
    func GCDMainQueue(block:@escaping (() -> Void)) {
        DispatchQueue.main.async(execute: block)
    }
}

