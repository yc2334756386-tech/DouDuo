import XCTest

/// 关注 / 粉丝列表翻页回归：验证列表能一路往下拉，越过首屏（17~20 条）拿到更多页。
/// 这两个接口的分页口径不同（粉丝靠 max_time、关注靠 offset），只看「首屏能显示」不够，
/// 必须真的滑到底触发第二次 loadMore，并确认条数增长。
final class DYRelationsPagingTests: XCTestCase {
    func testFollowersLoadsMoreThanFirstPage() throws { try verifyPaging(kind: "followers") }
    func testFollowingLoadsMoreThanFirstPage() throws { try verifyPaging(kind: "following") }

    private func verifyPaging(kind: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        addTeardownBlock { app.terminate() }
        app.launchEnvironment = ["DOUDUO_RELATIONS_PROBE": kind]
        app.launchArguments = ["-douyin_muted_v1", "YES", "-douyin_autoplay_v1", "NO"]
        app.launch()

        let rows = app.buttons.matching(identifier: "douyin.relations.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 40), "列表首屏没加载出来")
        let firstPage = rows.count
        XCTAssertGreaterThan(firstPage, 0, "首屏为空")
        attach(app, "relations-\(kind)-first")

        // 反复上滑直到行数不再增长（最多 12 次），模拟用户一直往下翻
        var last = firstPage
        var grew = false
        for _ in 0..<12 {
            app.swipeUp(velocity: .fast)
            _ = rows.firstMatch.waitForExistence(timeout: 2)
            // 给下一页请求留时间（抖音接口约 0.3–1s）
            Thread.sleep(forTimeInterval: 1.5)
            let now = rows.count
            if now > last { grew = true; last = now }
        }
        attach(app, "relations-\(kind)-after")
        XCTAssertTrue(grew, "\(kind) 列表只停留在首屏 \(firstPage) 条，翻页没生效（这是老板报的「只能显示 20 个人」）")
        XCTAssertGreaterThan(last, firstPage, "\(kind) 翻页后条数没有增加")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

final class DYPersonalLayoutTests: XCTestCase {
    func testCommentsBelowVideoAndPhoto() throws {
        continueAfterFailure = false
        for photos in [false, true] {
            let app = XCUIApplication()
            app.launchEnvironment = ["DOUDUO_CHROME_MODE": "classic", "DOUDUO_HASHTAG_FIXTURE": "1",
                                     "DOUDUO_APPEARANCE": "dark", "DOUDUO_PERSONAL_LAYOUT": "1",
                                     "DOUDUO_PLAYBACK_FIXTURE": "1",
                                     "DOUDUO_OFFLINE_FIXTURE_URL": "http://127.0.0.1:8765/video.mp4",
                                     "DOUDUO_PHOTO_FIXTURE_URL": "http://127.0.0.1:8765/photo.png"]
            if photos { app.launchEnvironment["DOUDUO_GRID_FIXTURE"] = "1" }
            app.launchArguments = ["-douyin_muted_v1", "YES", "-douyin_autoplay_v1", "YES",
                                   "-douduo_dismissed_update_v1", "9.9.9", "-duoduomain_tab_v1", "首页"]
            app.launch()
            let commentButtons = app.buttons.matching(identifier: "douyin.comments")
            XCTAssertTrue(commentButtons.firstMatch.waitForExistence(timeout: 20))
            let button = try XCTUnwrap(commentButtons.allElementsBoundByIndex.first { $0.isHittable })
            if !photos { XCTAssertTrue(waitForPlayingVideo(app), "Local test video must play before opening comments") }
            button.tap()
            let comments = app.scrollViews["douyin.comments.list"].firstMatch
            XCTAssertTrue(comments.waitForExistence(timeout: 10))
            let media = app.descendants(matching: .any).matching(identifier: "douyin.comments.mediaPane").firstMatch
            let panel = app.descendants(matching: .any).matching(identifier: "douyin.comments.panel").firstMatch
            XCTAssertTrue(media.exists)
            XCTAssertTrue(panel.exists)
            XCTAssertGreaterThan(media.frame.height, 100)
            XCTAssertLessThanOrEqual(media.frame.maxY, panel.frame.minY + 2)
            XCTAssertFalse(app.buttons["douyin.comment.send"].exists)
            XCTAssertFalse(app.buttons["douyin.comment.digg"].exists)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            if !photos { XCTAssertTrue(waitForPlayingVideo(app), "The same video must keep playing above comments") }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = photos ? "readonly-photo-comments" : "readonly-video-comments"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["douyin.comments.close"].firstMatch.tap()
            XCTAssertTrue(commentButtons.firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    private func waitForPlayingVideo(_ app: XCUIApplication) -> Bool {
        let probe = app.staticTexts["douyin.search.playbackProbe"].firstMatch
        let playing = NSPredicate { _, _ in
            guard probe.exists,
                  let snapshot = try? JSONSerialization.jsonObject(with: Data(probe.label.utf8)) as? [String: Any],
                  let players = snapshot["players"] as? [[String: Any]] else { return false }
            return players.contains { $0["id"] as? String == "hashtag-cat" && $0["ready"] as? Bool == true
                && $0["playing"] as? Bool == true && ($0["time"] as? Double ?? 0) > 0.5 }
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: nil)], timeout: 15) == .completed
    }

    func testCollectedMusicSurvivesBackground() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        addTeardownBlock { app.terminate() }
        app.launchEnvironment = ["DOUDUO_MUSIC_FIXTURE_URL": "http://127.0.0.1:8765/music.wav"]
        app.launch()
        let row = app.buttons["douyin.music.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let probe = app.staticTexts["douyin.music.playbackProbe"].firstMatch
        func state() -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(probe.label.utf8)) as? [String: Any]) ?? [:]
        }
        let playing = NSPredicate { _, _ in (state()["seconds"] as? Double ?? 0) > 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: nil)], timeout: 15), .completed)
        XCTAssertEqual(state()["title"] as? String, "Background audio test")
        XCTAssertEqual(state()["remoteOwner"] as? Bool, true)
        let before = try XCTUnwrap(state()["seconds"] as? Double)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        app.activate()
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(try XCTUnwrap(state()["seconds"] as? Double), before + 3)
        XCTAssertEqual(state()["rate"] as? Double, 1)
        XCTAssertEqual(state()["remoteOwner"] as? Bool, true)
        row.tap()
        XCTAssertEqual(row.value as? String, "播放")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "background-music-return"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
