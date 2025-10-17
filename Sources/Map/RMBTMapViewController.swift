//
//  RMBTMapViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 19.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import MapKit

class RMBTMapViewController: UIViewController {

    private let showMapOptionsSegue = "show_map_options"
    private let showMapTypeSegue = "show_map_type"
    private let searchSegue = "searchSegue"
    
    @IBOutlet weak var searchButton: UIButton!
    @IBOutlet weak var layerOptionsButton: UIButton!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var mapOptionsButton: UIButton!
    @IBOutlet weak var myLocationButton: UIButton!
    @IBOutlet weak var mapView: MKMapView!
    
    @IBOutlet weak var measurementsListBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var measurementsListViewContainer: UIView!
    
    private var tileSize: CGSize = CGSize(width: 256, height: 256)
    private var pointDiameterSize: UInt = 12
    
    private var tileParamsDictionary: [String: Any] = [:]
    
    private var mapOptions: RMBTMapOptions?
    
    private var tileRenderer: MKTileOverlayRenderer?
    
    private var currentOverlay: RMBTMapOptionsOverlay = RMBTMapOptionsOverlayShapes
    
    private var currentPin: MKAnnotation?
    
    private lazy var mapResultsListViewController: RMBTMapResultsListViewController = {
        let vc = UIStoryboard(name: "MainStoryboard", bundle: nil).instantiateViewController(withIdentifier: "RMBTMapResultsListViewController") as! RMBTMapResultsListViewController
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        vc.onCloseHandler = { [weak self] in
            self?.hideResults()
        }
        vc.onDetailsHandler = { [weak self] measurement in
            self?.showInfo(for: measurement)
        }
        vc.onChooseHandler = { [weak self] measurement in
            self?.scroll(to: measurement)
        }
        return vc
    }()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 13.0, *) {
            return .darkContent
        } else {
            return .default
        }
    }
    
    // If set, blue pin will be shown at this location and map initially zoomed here. Used to
    // display a test on the map.
    public var initialLocation: CLLocation?
    public var initialZoom: Double = 12
    public var initialNetworkType: String?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.navigationController?.tabBarItem.title = " "
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.layerOptionsButton.isEnabled = false
        self.mapOptionsButton.isEnabled = false
        
        self.setNeedsStatusBarAppearanceUpdate()
        setupMapView()
        
        self.closeButton.isHidden = initialLocation == nil
        if initialLocation != nil {
            // TODO: Show back button
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(mapDidTap(_:)))
        self.mapView.addGestureRecognizer(tapGesture)
        
        self.reloadMapOptions()
        self.prepareResultListView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        setupInitLocation()
    }

    
    private func prepareResultListView() {
        let vc = self.mapResultsListViewController
        self.measurementsListViewContainer.addSubview(vc.view)
        NSLayoutConstraint.activate([
            measurementsListViewContainer.leftAnchor.constraint(equalTo: vc.view.leftAnchor),
            measurementsListViewContainer.rightAnchor.constraint(equalTo: vc.view.rightAnchor),
            measurementsListViewContainer.topAnchor.constraint(equalTo: vc.view.topAnchor),
            measurementsListViewContainer.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
        ])
//        self.hideResults()
    }
    
    private func hideResults() {
        UIView.animate(withDuration: 0.3) {
            self.measurementsListBottomConstraint.constant = -(self.measurementsListViewContainer.bounds.height + self.view.safeAreaInsets.bottom)
            self.view.layoutIfNeeded()
        }
    }
    
    private func showResults() {
        UIView.animate(withDuration: 0.3) {
            self.measurementsListBottomConstraint.constant = 5
            self.view.layoutIfNeeded()
        }
        
    }
    
    private func setupMapView() {
        self.mapView.showsBuildings = false
        self.mapView.showsUserLocation = true
        self.mapView.isRotateEnabled = false
        self.mapView.delegate = self
    }
    
    private func setupInitLocation() {
        if let initialLocation = initialLocation {
            // If test coordinates were provided, center map at the coordinates:
            self.mapView.setCenter(initialLocation.coordinate, zoom: initialZoom, animated: false)
            let icon = HistoryMapIcon.pinIcon(for: initialNetworkType, configuration: .large)
            let pin = RMBTMeasurementPin(id: "", title: "Pin", coordinate: initialLocation.coordinate, icon: icon)
            self.currentPin = pin
            self.mapView.addAnnotation(pin)
            self.mapView.selectAnnotation(pin, animated: true)
        } else if let location = RMBTLocationTracker.shared.location {
            // Otherwise, see if we have user's location available...
            self.mapView.setCenter(location.coordinate, animated: false)
        }
    }
    
    private func setupMapLayer() {
        if let overlay = self.mapOptions?.oldActiveOverlay {
            if overlay == RMBTMapOptionsOverlayAuto {
                if self.currentOverlay == RMBTMapOptionsOverlayHeatmap && Int32(mapView.getZoom()) > RMBTConfig.RMBT_MAP_AUTO_TRESHOLD_ZOOM {
                        self.currentOverlay = RMBTMapOptionsOverlayPoints
                } else if self.currentOverlay == RMBTMapOptionsOverlayPoints && Int32(mapView.getZoom()) < RMBTConfig.RMBT_MAP_AUTO_TRESHOLD_ZOOM {
                        self.currentOverlay = RMBTMapOptionsOverlayHeatmap
                    } else if self.currentOverlay != RMBTMapOptionsOverlayHeatmap {
                        self.currentOverlay = RMBTMapOptionsOverlayHeatmap
                    }
            } else {
                self.currentOverlay = overlay
            }
        }
        let template = RMBTMapServer.shared.getTileUrlTemplate(self.currentOverlay.identifier, params: tileParamsDictionary)
        let layer = MKTileOverlay(urlTemplate: template)
        
        layer.tileSize = tileSize
        
        if let overlay = tileRenderer?.overlay {
            mapView.removeOverlay(overlay)
        }
        tileRenderer = MKTileOverlayRenderer(overlay: layer)
        mapView.addOverlay(layer)
        tileRenderer?.reloadData()
    }

    private func reloadMapOptions() {
        RMBTControlServer.shared.updateWithCurrentSettings {
            RMBTMapServer.shared.getMapOptions { [weak self] response in
                self?.mapOptions = RMBTMapOptions(response: response)
                self?.layerOptionsButton.isEnabled = true
                self?.mapOptionsButton.isEnabled = true
                self?.setupMapLayer()
                self?.refresh()
            } error: { [weak self] error in
                Log.logger.error(error)
                self?.setupMapLayer()
                self?.refresh()
            }
        } error: { error in
            Log.logger.error(error)
        }        
    }
    
    private func refresh() {
        tileParamsDictionary = mapOptions?.mapFiltersDictionary ?? [:]
        tileParamsDictionary["size"] = "\(tileSize.width)"
        tileParamsDictionary["point_diameter"] = "\(pointDiameterSize)"
        setupMapLayer()
    }
    
    @IBAction func searchButtonClick(_ sender: Any) {
        self.performSegue(withIdentifier: searchSegue, sender: self)
    }
    
    @IBAction func myLocationButtonClick(_ sender: Any) {
        guard let location = RMBTLocationTracker.shared.location else { return }
        
        self.mapView.setCenter(location.coordinate, animated: true)
    }
    
    @IBAction func mapOptionsButtonClick(_ sender: Any) {
        self.performSegue(withIdentifier: showMapOptionsSegue, sender: self)
    }
    
    @IBAction func layerOptionsButtonClick(_ sender: Any) {
        self.performSegue(withIdentifier: "show_map_type", sender: self)
    }
    
    @IBAction func closeButtonClick(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == self.showMapOptionsSegue,
           let navController = segue.destination as? UINavigationController,
           let vc = navController.topViewController as? RMBTMapOptionsViewController {
            navController.modalPresentationStyle = .overFullScreen
            vc.modalPresentationStyle = .overFullScreen
            vc.mapOptions = self.mapOptions
            vc.delegate = self
        } else if segue.identifier == self.showMapTypeSegue,
           let vc = segue.destination as? RMBTMapOverlaysViewController {
            vc.mapOptions = self.mapOptions
            vc.delegate = self
        } else if segue.identifier == searchSegue,
                  let navController = segue.destination as? UINavigationController,
                  let vc = navController.topViewController as? RMBTSearchMapViewController {
            navController.modalPresentationStyle = .overCurrentContext
            vc.modalPresentationStyle = .overCurrentContext
            vc.onFindItem = { item in
                if let item = item {
                    self.mapView.setCenter(item.placemark.coordinate, zoom: 8, animated: true)
                }
            }
        }
    }
    
    private func deselectCurrentMarker() {
        guard let pin = self.currentPin else { return }
        self.mapView.deselectAnnotation(pin, animated: true)
        self.mapView.removeAnnotation(pin)
    }
    
    @objc var closeBarButtonItem: UIBarButtonItem {
        let closeBarButtonItem = UIBarButtonItem(image: .closeImage, style: .done, target: self, action: #selector(closeDetailsViewController(_:)))
        return closeBarButtonItem
    }
    
    @objc private func closeDetailsViewController(_ sender: Any) {
        self.presentedViewController?.dismiss(animated: true)
    }
    
    private func showInfo(for measurement: SpeedMeasurementResultResponse) {
        guard let uuid = measurement.openTestUuid else { return }
        
        RMBTMapServer.shared.getOpenTestUrl(uuid) { response in
            if let openURL = response,
               let url = URL(string: openURL) {
                let controller = RMBTWebViewController()
                controller.loadUrl(url: url)
                let navController = UINavigationController(rootViewController: controller)
                self.present(navController, animated: true)
                navController.navigationBar.topItem?.title = measurement.timeString
                navController.navigationBar.topItem?.leftBarButtonItem = self.closeBarButtonItem
                navController.navigationBar.tintColor = UIColor.black
            }
        }
    }
    
    private func scroll(to measurement: SpeedMeasurementResultResponse) {
        guard let uuid = measurement.openTestUuid,
              let lat = measurement.latitude,
              let long = measurement.longitude else { return }
        self.deselectCurrentMarker()
        
        let pin = RMBTMeasurementPin(id: uuid, title: measurement.timeString, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: long))
        self.currentPin = pin
        self.mapView.addAnnotation(pin)
        self.mapView.selectAnnotation(pin, animated: true)
    }
    
    @objc private func mapDidTap(_ sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        
        // If we're not showing points, ignore this tap
        guard self.currentOverlay == RMBTMapOptionsOverlayPoints else { return }
        
        let touchLocation = sender.location(in: mapView)
        let coordinate = mapView.convert(touchLocation, toCoordinateFrom: mapView)
        let zoom = mapView.getZoom()
        let params = self.mapOptions?.mapFiltersDictionary ?? [:]
        RMBTMapServer.shared.getMeasurementsAtCoordinate(coordinate, zoom: Int(zoom), params: params) { [weak self] response in
            guard let self = self else { return }
            
            self.deselectCurrentMarker()
            
            guard let measurement = response.first,
                  let uuid = measurement.openTestUuid,
                  let lat = measurement.latitude,
                  let long = measurement.longitude else {
                self.hideResults()
                return
            }
            
            let pin = RMBTMeasurementPin(id: uuid, title: "Pin", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: long))
            self.currentPin = pin
            self.mapResultsListViewController.measurements = response
            self.mapView.addAnnotation(pin)
            self.mapView.selectAnnotation(pin, animated: true)
//            self.showInfo(for: measurement)
            self.showResults()
        } error: { [weak self] error in
            Log.logger.error(error)
            guard let self = self else { return }
            
            self.deselectCurrentMarker()
        }
    }

}

extension RMBTMapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        return tileRenderer!
    }
    
    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        if self.mapOptions?.oldActiveOverlay == RMBTMapOptionsOverlayAuto {
            if self.currentOverlay == RMBTMapOptionsOverlayHeatmap && Int32(mapView.getZoom()) > RMBTConfig.RMBT_MAP_AUTO_TRESHOLD_ZOOM {
                self.setupMapLayer()
            } else if self.currentOverlay == RMBTMapOptionsOverlayPoints && Int32(mapView.getZoom()) < RMBTConfig.RMBT_MAP_AUTO_TRESHOLD_ZOOM {
                self.setupMapLayer()
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let measurementPin = annotation as? RMBTMeasurementPin {
            let identifier = "Pin"
            let fallbackImage = UIImage(named: "map_pin_icon")
            guard let image = measurementPin.icon ?? fallbackImage else { return nil }
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            
            annotationView.annotation = annotation
            annotationView.image = image
            annotationView.canShowCallout = false
            annotationView.centerOffset = CGPoint(x: 0, y: -image.size.height / 2)
            return annotationView
        }
        return nil
    }
}

extension RMBTMapViewController: RMBTMapOptionsViewControllerDelegate {
    func mapOptionsViewController(_ vc: RMBTMapOptionsViewController, willDisappearWithChange isChange: Bool) {
        guard isChange else { return }
        
        Log.logger.debug("Map options changed, refreshing...")
        mapOptions?.saveSelection()
        
        switch(mapOptions?.oldMapViewType) {
        case .hybrid: mapView.mapType = .hybrid
        case .satellite: mapView.mapType = .satellite
        case .standard: mapView.mapType = .standard
        default: mapView.mapType = .standard
        }
        self.refresh()
    }
}

extension RMBTMapViewController: RMBTMapOverlaysViewControllerDelegate {
    func mapOverlaysViewControllerMapTypeDidChange(_ vc: RMBTMapOverlaysViewController) {
        Log.logger.debug("Map options changed, refreshing...")
        mapOptions?.saveSelection()
        
        switch(mapOptions?.oldMapViewType) {
        case .hybrid: mapView.mapType = .hybrid
        case .satellite: mapView.mapType = .satellite
        case .standard: mapView.mapType = .standard
        default: mapView.mapType = .standard
        }
    }
    
    func mapOverlaysViewControllerOverlayDidChange(_ vc: RMBTMapOverlaysViewController) {
        Log.logger.debug("Map overlay changed, refreshing...")
        mapOptions?.saveSelection()
        self.refresh()
    }
}

private extension UIImage {
    static let closeImage = UIImage(named: "black_close_button")
}
