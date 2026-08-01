//
//  DeadlineUITests.swift
//  DeadlineUITests
//
//  Created by Сергей Родоманюк on 30.09.2025.
//

import XCTest

final class DeadlineUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddAndDeleteDeadline() throws {
        let app = launchApp()

        openAddForm(in: app)

        let uniqueTitle = "UI Test Deadline \(UUID().uuidString.prefix(8))"

        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(String(uniqueTitle))

        let addButton = app.buttons["confirmAddDeadlineButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let newDeadline = app.staticTexts[String(uniqueTitle)]
        XCTAssertTrue(newDeadline.waitForExistence(timeout: 10))

        let row = app.cells.containing(.staticText, identifier: String(uniqueTitle)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()

        let deleteButton = app.buttons["Удалить"].exists ? app.buttons["Удалить"] : app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        XCTAssertFalse(newDeadline.waitForExistence(timeout: 3))
    }

    @MainActor
    func testFilteredEmptyState() throws {
        let app = launchApp()

        let statusFilter = app.buttons["filterStatusPicker"]
        if statusFilter.waitForExistence(timeout: 5) {
            statusFilter.tap()
        } else {
            let completedOption = app.buttons["Выполнен"].exists ? app.buttons["Выполнен"] : app.buttons["Completed"]
            if completedOption.exists { completedOption.tap() }
        }

        let completedLabel = app.buttons["Выполнен"].exists ? "Выполнен" : "Completed"
        if app.buttons[completedLabel].waitForExistence(timeout: 3) {
            app.buttons[completedLabel].tap()
        }

        let emptyState = app.staticTexts["filteredEmptyState"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 8))
    }

    @MainActor
    func testAddDueSoonShowsHighPriorityBadge() throws {
        let app = launchApp()
        openAddForm(in: app)

        let uniqueTitle = "UI Critical \(UUID().uuidString.prefix(6))"
        let titleField = app.textFields["titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(uniqueTitle)

        let addButton = app.buttons["confirmAddDeadlineButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.staticTexts[uniqueTitle].waitForExistence(timeout: 10))

        let highLabel = app.staticTexts["Высокий"].exists ? app.staticTexts["Высокий"] : app.staticTexts["High"]
        let badge = app.otherElements["priorityBadge"]
        XCTAssertTrue(highLabel.waitForExistence(timeout: 5) || badge.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launchArguments += ["-ui-testing"]
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        let deadlinesTab = app.tabBars.buttons["Задачи"].exists
            ? app.tabBars.buttons["Задачи"]
            : (app.tabBars.buttons["Deadlines"].exists ? app.tabBars.buttons["Deadlines"] : app.tabBars.buttons["Дедлайны"])
        if deadlinesTab.exists {
            deadlinesTab.tap()
        }
        return app
    }

    @MainActor
    private func openAddForm(in app: XCUIApplication) {
        let openAddButton = app.buttons["openAddDeadlineButton"]
        if openAddButton.waitForExistence(timeout: 5) {
            openAddButton.tap()
            return
        }

        let localizedAddButton = app.buttons["Добавить задачу"].exists
            ? app.buttons["Добавить задачу"]
            : (app.buttons["Add deadline"].exists ? app.buttons["Add deadline"] : app.buttons["Add task"])
        XCTAssertTrue(localizedAddButton.waitForExistence(timeout: 5))
        localizedAddButton.tap()
    }
}
