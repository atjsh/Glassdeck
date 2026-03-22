@testable import Glassdeck
import XCTest

final class AppLaunchRoutingTests: XCTestCase {
    func testShouldScheduleDeferredRouteRequiresLaunchRequestAndPresentableSession() {
        XCTAssertTrue(AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: true,
            appliedLaunchRouting: false,
            launchRoutingScheduled: false,
            hasActiveSession: true,
            isActiveSessionPresentable: true
        ))

        XCTAssertFalse(AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: false,
            appliedLaunchRouting: false,
            launchRoutingScheduled: false,
            hasActiveSession: true,
            isActiveSessionPresentable: true
        ))

        XCTAssertFalse(AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: true,
            appliedLaunchRouting: false,
            launchRoutingScheduled: false,
            hasActiveSession: true,
            isActiveSessionPresentable: false
        ))
    }

    func testShouldScheduleDeferredRouteRejectsAlreadyScheduledOrAppliedRoute() {
        XCTAssertFalse(AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: true,
            appliedLaunchRouting: true,
            launchRoutingScheduled: false,
            hasActiveSession: true,
            isActiveSessionPresentable: true
        ))

        XCTAssertFalse(AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: true,
            appliedLaunchRouting: false,
            launchRoutingScheduled: true,
            hasActiveSession: true,
            isActiveSessionPresentable: true
        ))

        XCTAssertFalse(AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: true,
            appliedLaunchRouting: false,
            launchRoutingScheduled: false,
            hasActiveSession: false,
            isActiveSessionPresentable: true
        ))
    }

    func testShouldScheduleDeferredRouteAllowsHostBackedFallbackSession() {
        XCTAssertTrue(AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: true,
            appliedLaunchRouting: false,
            launchRoutingScheduled: false,
            hasActiveSession: false,
            isActiveSessionPresentable: true,
            allowHostBackedLaunchFallback: true
        ))
    }

    func testShouldNotScheduleDeferredRouteWhenOnlyFallbackUnavailable() {
        XCTAssertFalse(AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: true,
            appliedLaunchRouting: false,
            launchRoutingScheduled: false,
            hasActiveSession: false,
            isActiveSessionPresentable: true,
            allowHostBackedLaunchFallback: false
        ))
    }

    func testShouldNotScheduleDeferredRouteUntilSessionIsRouteable() {
        XCTAssertFalse(AppLaunchRouting.shouldScheduleDeferredRoute(
            shouldOpenActiveSessionOnLaunch: true,
            appliedLaunchRouting: false,
            launchRoutingScheduled: false,
            hasActiveSession: false,
            isActiveSessionPresentable: false,
            allowHostBackedLaunchFallback: true
        ))
    }
}
