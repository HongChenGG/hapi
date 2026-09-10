import UIKit
import XCTest
@testable import HapiUI

@MainActor
final class TranscriptGeometryTests: XCTestCase {
    func testIndexedQueriesMatchLinearGeometryThroughWindowAndWidthChanges() throws {
        let layout = TranscriptLayout()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), collectionViewLayout: layout)
        var ids = (0..<800).map(String.init)
        var heights: [String: CGFloat] = [:]
        layout.setItems(ids, width: 390)
        layout.prepare()
        for index in stride(from: 0, to: ids.count, by: 7) {
            let height = CGFloat(20 + index % 19 * 87)
            heights[ids[index]] = height
            let original = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
            let preferred = original.copy() as! UICollectionViewLayoutAttributes
            preferred.size.height = height
            _ = layout.invalidationContext(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original)
        }
        layout.prepare()

        @MainActor func verify(width: CGFloat) {
            var y: CGFloat = 10
            let expected = ids.map { id -> CGRect in
                let frame = CGRect(x: 12, y: y, width: width - 24, height: heights[id] ?? 100)
                y = frame.maxY + 10
                return frame
            }
            let actualHeight = layout.collectionViewContentSize.height
            XCTAssertEqual(actualHeight, y, accuracy: 0.01)
            let rects = stride(from: -500, to: Int(y) + 500, by: 377).map {
                CGRect(x: 0, y: $0, width: Int(width), height: 844)
            } + [.zero, .null, .infinite, CGRect(x: 1000, y: 0, width: 100, height: 100000)]
            for rect in rects {
                let indices = expected.indices.filter { expected[$0].intersects(rect) }
                let actual = layout.layoutAttributesForElements(in: rect) ?? []
                XCTAssertEqual(actual.map(\.indexPath.item), indices)
                XCTAssertEqual(actual.map(\.frame), indices.map { expected[$0] })
            }
        }
        verify(width: 390)
        ids = (800..<820).map(String.init) + Array(ids.dropLast(20))
        layout.setItems(ids, width: 390)
        layout.prepare()
        verify(width: 390)
        // Width changes discard stale measurements but retain correct indices.
        heights.removeAll()
        layout.setItems(ids, width: 430)
        layout.prepare()
        verify(width: 430)
        layout.setItems([], width: 430)
        layout.prepare()
        XCTAssertTrue(layout.layoutAttributesForElements(in: .infinite)?.isEmpty == true)
        XCTAssertNil(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(collection.collectionViewLayout, layout)
    }

    #if DEBUG
    func testVisibleQueriesVisitOnlyAViewportSizedRange() {
        let layout = TranscriptLayout()
        layout.setItems((0..<800).map(String.init), width: 390)
        layout.prepare()
        for step in 0..<200 {
            let rect = CGRect(x: 0, y: 1000 + step * 350, width: 390, height: 844)
            let visible = layout.layoutAttributesForElements(in: rect) ?? []
            XCTAssertFalse(visible.isEmpty)
            XCTAssertTrue(visible.allSatisfy { $0.frame.intersects(rect) })
            XCTAssertLessThanOrEqual(visible.count, 9)
        }
        print("Transcript geometry: 800 rows / 200 viewport queries / \(layout.visibleQueryProbeCount) probes")
        // log2(800) + visible rows + a small boundary allowance, not 800
        // CGRect intersection tests on every frame.
        XCTAssertLessThanOrEqual(layout.visibleQueryProbeCount, 200 * 32)
    }

    func testMeasuringRowsDoesNotAllocateLayoutAttributesForTheWholeWindow() throws {
        let layout = TranscriptLayout()
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), collectionViewLayout: layout)
        layout.setItems((0..<800).map(String.init), width: 390)
        layout.prepare()
        let old = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 300, section: 0)))
        let oldFrame = old.frame
        let allocations = layout.attributeCreationCount
        for index in 0..<20 {
            let original = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
            let preferred = original.copy() as! UICollectionViewLayoutAttributes
            preferred.size.height += 20
            _ = layout.invalidationContext(forPreferredLayoutAttributes: preferred, withOriginalAttributes: original)
            layout.prepare()
        }
        let updated = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 300, section: 0)))
        XCTAssertEqual(updated.frame.minY, oldFrame.minY + 400, accuracy: 0.01)
        XCTAssertEqual(old.frame, oldFrame, "UIKit's previously returned attributes must remain immutable")
        XCTAssertEqual(collection.collectionViewLayout, layout)
        let created = layout.attributeCreationCount - allocations
        print("Transcript geometry: 20 self-sizing updates / \(created) attributes created")
        XCTAssertLessThanOrEqual(created, 40)
    }
    #endif
}
