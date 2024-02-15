//
//  TopPopoverView.swift
//  RMBT
//
//  Created by Jiri Urbasek on 2/15/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import SwiftUI

struct TopPopoverView: View {
    let text: String
    let backgroundColor: Color

    var body: some View {
        Text(text)
            .font(.headline)
            .fontWeight(.light)
            .offset(y: -4)
            .padding(16)
            .background(.white)
            .cornerRadius(8)
            .background(backgroundColor)
            .clipShape(
                PopupArrow(
                    cornerRadius: 8,
                    arrowEdge: .bottom,
                    arrowHeight: 8,
                    arrowOffset: 0
                )
            )
    }
}

struct PopupArrow: Shape {
    let cornerRadius: CGFloat
    let arrowHeight: CGFloat
    let arrowEdge: Edge
    let arrowOffset: CGFloat

    init(cornerRadius: CGFloat = 6, arrowEdge: Edge = .trailing, arrowHeight: CGFloat = 13, arrowOffset: CGFloat = 25) {
        self.cornerRadius = cornerRadius
        self.arrowHeight = arrowHeight
        self.arrowEdge = arrowEdge
        self.arrowOffset = arrowOffset
    }

    func path(in rect: CGRect) -> Path {
        var rect = rect
        var fit: ((CGPoint) -> (CGPoint)) = { point in return point }
        let arrow: CGSize = CGSize(width: (arrowHeight/811)*2000, height: arrowHeight)

        var clockwise = false
        var arc1 = (start: Angle.radians(-.pi*0.5), end: Angle.radians(.pi*0.0))
        var arc2 = (start: Angle.radians(.pi*0.0),  end: Angle.radians(.pi*0.5))
        var arc3 = (start: Angle.radians(.pi*0.5),  end: Angle.radians(.pi*1.0))
        var arc4 = (start: Angle.radians(.pi*1.0),  end: Angle.radians(-.pi*0.5))

        var path = Path()

        if arrowEdge == .leading || arrowEdge == .trailing {
            clockwise = true
            rect = CGRect(x: rect.origin.y, y: rect.origin.x, width: rect.height, height: rect.width)
            fit = { point in return CGPoint(x: point.y, y: point.x)}
            let newArc1 = (arc3.end, arc3.start)
            let newArc2 = (arc2.end, arc2.start)
            let newArc3 = (arc1.end, arc1.start)
            let newArc4 = (arc4.end, arc4.start)
            arc1 = newArc1; arc2 = newArc2; arc3 = newArc3; arc4 = newArc4
        }

        // Move to beginning of Arc 1

        rect = CGRect(x: rect.origin.x + arrowOffset, y: rect.origin.y, width: rect.width, height: rect.height)

        path.move(to: fit(CGPoint(x: rect.width*0.5 + arrow.width*0.5, y: arrow.height)) )

        // Step 1 (arc1)
        path.addArc(center: fit(CGPoint(x: rect.width - cornerRadius, y: cornerRadius + arrow.height)),
                    radius: cornerRadius,
                    startAngle: arc1.start,
                    endAngle: arc1.end,
                    clockwise: clockwise )
        // Step 2 (arc2)
        path.addArc(center: fit(CGPoint(x: rect.width - cornerRadius, y: rect.height - cornerRadius)),
                    radius: cornerRadius,
                    startAngle: arc2.start,
                    endAngle: arc2.end,
                    clockwise: clockwise )
        // Step 3 (arc3)
        path.addArc(center: fit(CGPoint(x: cornerRadius, y: rect.height - cornerRadius)),
                    radius: cornerRadius,
                    startAngle: arc3.start,
                    endAngle: arc3.end,
                    clockwise: clockwise )
        // Step 4 (arc4)
        path.addArc(center: fit(CGPoint(x: cornerRadius, y: cornerRadius + arrow.height)),
                    radius: cornerRadius,
                    startAngle: arc4.start,
                    endAngle: arc4.end,
                    clockwise: clockwise )

        // arrow points where x = distance from arrow center, y = distance from top of rect
        let apex = CGPoint(x: arrow.width*0.5*0.000, y: -arrow.height*0.1456)
        let peak = CGPoint(x: arrow.width*0.5*0.149, y: arrow.height*0.0864)
        let curv = CGPoint(x: arrow.width*0.5*0.600, y: arrow.height*0.7500)
        let ctrl = CGPoint(x: arrow.width*0.5*0.750, y: arrow.height*1.0000)
        let base = CGPoint(x: arrow.width*0.5*1.000, y: arrow.height*1.0000)

        // Step 5
        path.addLine(to: fit(CGPoint(x: rect.midX - base.x, y: base.y)))

        // Step 6
        path.addQuadCurve(
            to: fit(CGPoint(x: rect.midX - curv.x, y: curv.y)),
            control: fit(CGPoint(x: rect.midX - ctrl.x, y: ctrl.y))
        )

        // Step 7
        path.addLine(to: fit(CGPoint(x: rect.midX - peak.x, y: peak.y)))

        // Step 8
        path.addQuadCurve(
            to: fit(CGPoint(x: rect.midX + peak.x, y: peak.y)),
            control: fit(CGPoint(x: rect.midX + apex.x, y: apex.y))
        )

        // Step 9
        path.addLine(to: fit(CGPoint(x: rect.midX + curv.x, y: curv.y)))

        // Step 10
        path.addQuadCurve(
            to: fit(CGPoint(x: rect.midX + base.x, y: base.y)),
            control: fit(CGPoint(x: rect.midX + ctrl.x, y: ctrl.y))
        )

        var transform = CGAffineTransform(scaleX: 1, y: 1)
        let bounds = path.boundingRect
        if arrowEdge == .trailing {
            // flip horizontally
            transform = CGAffineTransform(scaleX: -1, y: 1)
            transform = transform.translatedBy(x: -bounds.width, y: 0)
        }
        if arrowEdge == .bottom {
            // flip vertically
            transform = CGAffineTransform(scaleX: 1, y: -1)
            transform = transform.translatedBy(x: 0, y: -bounds.height)
        }
        return path.applying(transform)
    }
}

#Preview {
    ZStack {
        Color.gray
        TopPopoverView(text: "Popover text message", backgroundColor: .white)
    }
}

//  MARK: - UIKit support

import UIKit

extension UIView {
    class func from<Content: View>(_ view: Content) -> UIView {
        let controller = UIHostingController(rootView: view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .clear
        return controller.view
    }
}
