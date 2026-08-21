// SPDX-FileCopyrightText: 2026 Window Layouts contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import WindowLayouts

struct ScreenCoordinateConverterTests {
    private let converter = ScreenCoordinateConverter(referenceTop: 900)

    @Test func convertsBetweenBottomLeftAndTopLeftCoordinates() {
        let appKit = CGRect(x: 100, y: 100, width: 500, height: 200)
        let accessibility = converter.accessibilityRect(fromAppKit: appKit)
        #expect(accessibility == CGRect(x: 100, y: 600, width: 500, height: 200))
        #expect(converter.appKitRect(fromAccessibility: accessibility) == appKit)
    }

    @Test func convertsPointerCoordinatesAtTheAppKitBoundary() {
        let appKit = CGPoint(x: -240, y: 125)
        let accessibility = converter.accessibilityPoint(fromAppKit: appKit)

        #expect(accessibility == CGPoint(x: -240, y: 775))
        #expect(converter.appKitPoint(fromAccessibility: accessibility) == appKit)
    }

    @Test func supportsDisplaysInEveryDirection() {
        let frames = [
            CGRect(x: -1_920, y: -180, width: 1_920, height: 1_080),
            CGRect(x: 1_440, y: 0, width: 1_280, height: 720),
            CGRect(x: 0, y: 900, width: 1_440, height: 900),
            CGRect(x: 0, y: -1_080, width: 1_440, height: 1_080),
        ]
        for frame in frames {
            let converted = converter.accessibilityRect(fromAppKit: frame)
            #expect(converter.appKitRect(fromAccessibility: converted) == frame)
        }
        #expect(converter.accessibilityRect(fromAppKit: frames[2]).minY == -900)
        #expect(converter.accessibilityRect(fromAppKit: frames[3]).minY == 900)
    }

    @Test func primaryReferenceDoesNotDependOnScreenArrayOrder() {
        let primary = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let external = CGRect(x: 1_512, y: -98, width: 1_920, height: 1_080)

        #expect(ScreenCoordinateConverter.referenceTop(
            forAppKitFrames: [external, primary]
        ) == primary.maxY)
        #expect(ScreenCoordinateConverter.referenceTop(
            forAppKitFrames: [primary, external]
        ) == primary.maxY)
        #expect(ScreenCoordinateConverter.referenceTop(forAppKitFrames: []) == nil)
    }

    @Test func stableReferenceKeepsExternalBottomInsideItsFrame() throws {
        let primary = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let external = CGRect(x: 1_512, y: -98, width: 1_920, height: 1_080)
        let referenceTop = try #require(
            ScreenCoordinateConverter.referenceTop(
                forAppKitFrames: [external, primary]
            )
        )
        let converter = ScreenCoordinateConverter(referenceTop: referenceTop)
        let externalAXFrame = converter.accessibilityRect(fromAppKit: external)
        let bottomThird = try NormalizedRect(
            x: 0,
            y: 2.0 / 3.0,
            width: 2.0 / 3.0,
            height: 1.0 / 3.0
        )

        let destination = LayoutEngine.rectangle(
            for: bottomThird,
            in: externalAXFrame
        )

        #expect(destination.maxY == externalAXFrame.maxY)
        #expect(destination.minY >= externalAXFrame.minY)
    }
}
