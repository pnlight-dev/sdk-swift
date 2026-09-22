import DivKit
import XCTest
@testable import PNLightSDK

@MainActor
final class ProductVariablesTests: XCTestCase {
    private let cardId = DivCardID(rawValue: "products-test")
    private let selectionName = DivVariableName(rawValue: "selected_product")
    private let selectedName = DivVariableName(rawValue: "selected")
    private let productsName = DivVariableName(rawValue: "products")

    private func makeDocument() -> PNLightDocumentProducts {
        PNLightDocumentProducts(definitions: [
            PNLightProductDefinition(productId: "monthly", fallback: ["price": "$5"], selectedByDefault: false),
            PNLightProductDefinition(productId: "annual", fallback: ["price": "$40"], selectedByDefault: true),
        ], loadProducts: { [:] })
    }

    private func makeRoute(_ document: PNLightDocumentProducts) -> (PNLightProductVariables, DivVariablesStorage) {
        let binding = PNLightProductVariables()
        binding.attach(document)
        return (binding, DivVariablesStorage(outerStorage: binding.storage))
    }

    private func assertSelection(_ binding: PNLightProductVariables, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(binding.storage.getVariableValue(selectionName), .string(expected), file: file, line: line)
        guard case let .dict(selected)? = binding.storage.getVariableValue(selectedName),
              case let .array(products)? = binding.storage.getVariableValue(productsName) else {
            XCTFail("Expected product dictionaries", file: file, line: line)
            return
        }
        XCTAssertEqual(selected["id"], AnyHashable(expected), file: file, line: line)
        XCTAssertEqual(selected["is_selected"], AnyHashable(true), file: file, line: line)
        let entries = products.compactMap { $0.base as? [String: AnyHashable] }
        XCTAssertEqual(entries.filter { $0["is_selected"] == AnyHashable(true) }.count, 1, file: file, line: line)
        XCTAssertEqual(entries.first { $0["is_selected"] == AnyHashable(true) }?["id"], AnyHashable(expected), file: file, line: line)
    }

    func testSelectionReachesPreloadedAndNewRoutesInBothDirections() async {
        let document = makeDocument()
        let (plans, plansVariables) = makeRoute(document)
        let (checkout, checkoutVariables) = makeRoute(document)
        assertSelection(plans, "annual")
        assertSelection(checkout, "annual")

        // Uses the same DivKit update path as a card's set_variable action.
        plansVariables.update(cardId: cardId, name: selectionName, value: "monthly")
        assertSelection(plans, "monthly")
        assertSelection(checkout, "monthly")

        let (modal, _) = makeRoute(document)
        assertSelection(modal, "monthly")
        checkoutVariables.update(cardId: cardId, name: selectionName, value: "annual")
        assertSelection(plans, "annual")
        assertSelection(checkout, "annual")
        assertSelection(modal, "annual")
    }

    func testRemovingProductsClearsVariablesAndObserverWithoutClearingLayoutVariables() async {
        let document = makeDocument()
        let (route, variables) = makeRoute(document)
        let scale = DivVariableName(rawValue: "scaleX")
        variables.append(variables: [scale: .number(1.5)], triggerUpdate: false)

        for replacement in [nil, PNLightDocumentProducts(definitions: [], loadProducts: { [:] })] {
            route.attach(document)
            route.attach(replacement)
            for name in [selectionName, selectedName, productsName] {
                let value: DivVariableValue? = variables.getVariableValue(cardId: cardId, name: name)
                XCTAssertNil(value)
            }
            let scaleValue: DivVariableValue? = variables.getVariableValue(cardId: cardId, name: scale)
            XCTAssertEqual(scaleValue, .number(1.5))

            // A stale event must neither publish empty entries nor change the old flow.
            route.storage.put(name: selectionName, value: .string("monthly"))
            XCTAssertNil(route.storage.getVariableValue(productsName))
            XCTAssertEqual(document.selection, "annual")
        }
    }

    func testReplacementWithIdenticalProductsStartsFreshAndDetachesOldFlow() async {
        let original = makeDocument()
        let (reused, variables) = makeRoute(original)
        let (oldRoute, oldVariables) = makeRoute(original)
        variables.update(cardId: cardId, name: selectionName, value: "monthly")

        reused.attach(makeDocument())
        assertSelection(reused, "annual")
        oldVariables.update(cardId: cardId, name: selectionName, value: "annual")
        oldVariables.update(cardId: cardId, name: selectionName, value: "monthly")
        assertSelection(oldRoute, "monthly")
        assertSelection(reused, "annual")
    }

    func testReleasedRouteIsNotRetainedByDocumentObservers() async {
        let document = makeDocument()
        var route: PNLightProductVariables? = makeRoute(document).0
        weak var releasedRoute = route
        route = nil
        XCTAssertNil(releasedRoute)
        let (remaining, variables) = makeRoute(document)
        variables.update(cardId: cardId, name: selectionName, value: "monthly")
        assertSelection(remaining, "monthly")
    }

    func testPendingStoreLookupDoesNotRetainReplacedDocument() async {
        let started = expectation(description: "Store lookup started")
        var finishLookup: (() -> Void)?
        var document: PNLightDocumentProducts? = PNLightDocumentProducts(
            definitions: makeDocument().definitions,
            loadProducts: {
                await withCheckedContinuation { continuation in
                    finishLookup = { continuation.resume(returning: [:]) }
                    started.fulfill()
                }
            }
        )
        weak var oldDocument = document
        let binding = PNLightProductVariables()
        binding.attach(document)
        await fulfillment(of: [started], timeout: 2)
        binding.attach(makeDocument())
        document = nil
        XCTAssertNil(oldDocument)
        finishLookup?()
        assertSelection(binding, "annual")
    }

    func testApplyingEmptyMissingInvalidAndOlderDocumentsRemovesProductState() async {
        let renderer = PNLightRemoteUiRendererView(frame: .zero)
        let card = "\"card\":{\"log_id\":\"test\",\"states\":[{\"state_id\":0,\"div\":{\"type\":\"text\",\"text\":\"Test\"}}]}"
        let withProducts = "{\"schemaVersion\":6,\"products\":[\"monthly\"],\(card)}"
        let replacements: [String?] = [
            nil,
            "",
            "{\"schemaVersion\":6,\(card)}",
            "{\"schemaVersion\":6,\"products\":[],\(card)}",
            "{\"schemaVersion\":5,\"products\":[\"annual\"],\(card)}",
            "invalid json",
        ]
        for replacement in replacements {
            renderer.applyConfig(configJson: withProducts, cardId: "test")
            XCTAssertEqual(renderer.productVariables.storage.getVariableValue(selectionName), .string("monthly"))
            renderer.applyConfig(configJson: replacement, cardId: "test")
            for name in [selectionName, selectedName, productsName] {
                XCTAssertNil(renderer.productVariables.storage.getVariableValue(name))
            }
            XCTAssertNil(renderer.productVariables.document)
        }
    }
}
