#!/usr/bin/env python3
"""Exercise production notification routing and activity loading at network boundaries."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = (root / "FitFight/AppModel.swift").read_text()
activity = (root / "FitFight/FeedActivity.swift").read_text()
source = (root / "tests/FeedActivityTests.swift").read_text()
models = activity[activity.index("struct FeedPostLink:"):activity.index("struct FeedActivityView:")]
store_route = app[app.index("    static func storePendingFightRoute("):app.index("    private static var fightsCachePrefix:")]
consume_route = app[app.index("    private func consumePendingFightRoute("):app.index("    private static func mapFight(")]
source += "\n" + models
source += "\n" + (root / "tests/LegacyNotificationRoutes.swift").read_text()
source += "\nextension AppModel {\n" + store_route + consume_route
source += "    func consumeForTest(daily: Bool = false) { consumePendingFightRoute(showDailyStatusRecap: daily) }\n}\n"
api = (root / "FitFight/FitFightAPI.swift").read_text()
decoder = api[api.index("    private static let decoder:"):api.index("\n}\n\nprivate struct EmptyJSON:")]
source += "\nextension FitFightAPI {\n" + decoder
source += "\n    static func decodeActivityForTest(_ data: Data) throws -> FeedActivityList { try decoder.decode(FeedActivityList.self, from: data) }\n}\n"

with tempfile.TemporaryDirectory(prefix="fitfight-activity-tests-") as directory:
    generated = Path(directory) / "FeedActivityTests.swift"
    executable = Path(directory) / "feed-activity-tests"
    generated.write_text(source)
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(generated), "-o", str(executable)], check=True)
    subprocess.run([str(executable), str(root / "contracts/fixtures/feed-activity-response.json")], check=True, timeout=15)
