//
//  RMBTHistoryMapCell.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 09.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import MapKit

class RMBTHistoryMapCell: UITableViewCell {

    static let ID = "RMBTHistoryMapCell"
    
    @IBOutlet weak var fullScreenButton: UIButton!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var rootView: UIView!
    
    var onFullScreenHandler: (_ zoom: Double) -> Void = { _ in }
    
    var coordinate: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid {
        didSet { updateAnnotation() }
    }
    
    var networkType: String? {
        didSet { updateAnnotation() }
    }
    
    @IBAction func fullScreenButtonClick(_ sender: Any) {
        onFullScreenHandler(mapView.getZoom())
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.rootView.layer.cornerRadius = 8
        self.mapView.delegate = self
        self.mapView.isUserInteractionEnabled = false
    }
    
    private func updateAnnotation() {
        guard mapView != nil else { return }
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        
        let annotationsToRemove = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(annotationsToRemove)
        
        let icon = HistoryMapIcon.pinIcon(for: networkType, configuration: .small)
        let pin = RMBTMeasurementPin(id: "", title: "Pin", coordinate: coordinate, icon: icon)
        mapView.addAnnotation(pin)
        mapView.selectAnnotation(pin, animated: false)
        mapView.setCenter(coordinate, zoom: 12, animated: false)
    }
}

extension RMBTHistoryMapCell: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let measurementPin = annotation as? RMBTMeasurementPin {
            let fallbackImage = UIImage(named: "map_pin_small_icon")
            guard let image = measurementPin.icon ?? fallbackImage else { return nil }
            let identifier = "Pin"
            let scaleFactor = 0.8
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            
            annotationView.annotation = annotation
            annotationView.image = image
            annotationView.canShowCallout = false
            annotationView.centerOffset = CGPoint(x: 0, y: -image.size.height / 5 )
            annotationView.transform = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
            return annotationView
        }
        return nil
    }
}


private extension RMBTNetworkTypeConstants.NetworkType {
    func mapPinIcon(for baseImage: UIImage, configuration: HistoryMapIcon.MapPinConfiguration) -> UIImage {
        guard let glyph = icon?.withTintColor(UIColor.white, renderingMode: .alwaysOriginal) else {
            return baseImage
        }

        let baseSize = baseImage.size
        guard baseSize.width > 0, baseSize.height > 0 else { return baseImage }

        let glyphSize = glyph.size
        guard glyphSize.width > 0, glyphSize.height > 0 else { return baseImage }

        let maxGlyphSize = CGSize(width: baseSize.width * configuration.glyphMaxScaleRatio,
                                  height: baseSize.height * configuration.glyphMaxScaleRatio)
        let scaleRatio = min(maxGlyphSize.width / glyphSize.width,
                             maxGlyphSize.height / glyphSize.height,
                             1.0)
        let targetGlyphSize = CGSize(width: glyphSize.width * scaleRatio,
                                     height: glyphSize.height * scaleRatio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = baseImage.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: baseSize, format: format)
        let composedImage = renderer.image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: baseSize))

            let glyphOrigin = CGPoint(
                x: (baseSize.width - targetGlyphSize.width) / 2.0,
                y: (baseSize.height * configuration.glyphCenterHeightRatio) - targetGlyphSize.height / 2.0 + configuration.glyphVerticalOffset
            )
            glyph.draw(in: CGRect(origin: glyphOrigin, size: targetGlyphSize))
        }

        return composedImage.withRenderingMode(.alwaysOriginal)
    }
}

enum HistoryMapIcon {
    private static let mapPinCache = NSCache<NSString, UIImage>()

    enum MapPinConfiguration {
        case small
        case large

        fileprivate var baseImageName: String {
            switch self {
            case .small: return "map_pin_small_icon"
            case .large: return "map_pin_icon"
            }
        }

        fileprivate var glyphMaxScaleRatio: CGFloat {
            switch self {
            case .small: return 0.30
            case .large: return 0.30
            }
        }

        fileprivate var glyphCenterHeightRatio: CGFloat {
            switch self {
            case .small: return 0.30
            case .large: return 0.30
            }
        }

        fileprivate var glyphVerticalOffset: CGFloat {
            switch self {
            case .small: return 8.0
            case .large: return 11.0
            }
        }
    }

    static func pinIcon(for networkType: String?, configuration: MapPinConfiguration) -> UIImage? {
        let cacheKey = NSString(string: "\(networkType ?? "nil")|\(configuration.baseImageName)")
        if let cached = mapPinCache.object(forKey: cacheKey) {
            return cached
        }

        guard let baseImage = UIImage(named: configuration.baseImageName) else { return nil }
        guard let networkType = networkType else {
            mapPinCache.setObject(baseImage, forKey: cacheKey)
            return baseImage
        }

        guard let resolvedType = resolvedNetworkType(for: networkType) else {
            mapPinCache.setObject(baseImage, forKey: cacheKey)
            return baseImage
        }

        let composed = resolvedType.mapPinIcon(for: baseImage, configuration: configuration)
        mapPinCache.setObject(composed, forKey: cacheKey)
        return composed
    }

    private static func resolvedNetworkType(for identifier: String) -> RMBTNetworkTypeConstants.NetworkType? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = RMBTNetworkTypeConstants.networkTypeDictionary[trimmed] {
            return direct
        }
        if let insensitive = RMBTNetworkTypeConstants.networkTypeDictionary.first(where: { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame })?.value {
            return insensitive
        }
        if let fromCellular = RMBTNetworkTypeConstants.cellularCodeDescriptionDictionary.first(where: { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame })?.value {
            return fromCellular
        }
        return nil
    }
}


