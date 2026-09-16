#!/usr/bin/env python3
"""Run native async-state regressions with suspended HealthKit and HTTP boundaries.

The app has no XCTest target. Compile the actual store methods with small boundary
doubles and the real API models so tests exercise their ordering, not a rewritten
copy of the behavior. A missing method delimiter intentionally fails the runner.
"""

from pathlib import Path
import platform
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
app = (root / "FitFight/AppModel.swift").read_text()
feed = (root / "FitFight/FeedView.swift").read_text()
thread = (root / "FitFight/FightPostThread.swift").read_text()
app_methods = (
    app[app.index("    func refreshFights("):app.index("    private func performRefreshFights(")]
    + app[app.index("    private func holdRefreshPhase("):app.index("    func removeCachedFights(")]
)
feed_methods = feed[feed.index("    func activate("):feed.index("\n}\n\nprivate func postableFights(")]

source = (root / "tests/NativeStateTests.swift").read_text()
source += "\nextension AppModel {\n" + app_methods + "\n}\n"
source += "\nextension FeedStore {\n" + feed_methods + "\n}\n"
chrome = (root / "FitFight/DesignSystem/AppChrome.swift").read_text()
source += "\n" + chrome[chrome.index("struct FFRefreshConfig {"):chrome.index("/// Centered gold spinner")]
source += "\nextension FeedRefreshHarness {\n"
source += feed[feed.index("    private var feedRefresh:"):feed.index("    private var composeButton:")].replace("action: {", "action: { [self] in")
source += "    func refreshForTest() async { await feedRefresh.action() }\n}\n"
api = (root / "FitFight/FitFightAPI.swift").read_text()
source += "\nextension FeedRequestPaths {\n"
source += api[api.index("    func feed(scope:"):api.index("    func feedActivity(")]
source += api[api.index("    func fightPosts("):api.index("    func createFightPost(")]
source += "\n}\n"
source += "\nextension FightPostThreadState {\n"
source += thread[thread.index("    private var displayedComments:"):thread.index("    private func commentRow(")]
source += thread[thread.index("    private func loadComments("):thread.index("    private func firstEmoji(")]
source += "    func rowsForTest() -> [(UUID, Int)] { displayedComments.map { ($0.id, $0.depth) } }\n"
source += "    func loadForTest() async { await loadComments() }\n"
source += "    func sendForTest() async { await sendComment() }\n"
source += "    func reportForTest(_ comment: FitFightFightPostComment) async { await reportComment(comment) }\n"
source += "    func deleteForTest(_ comment: FitFightFightPostComment) async { await deleteComment(comment) }\n}\n"
count_change = thread.split(".onChange(of: post.commentCount) { previous, count in\n", 1)[1].split("\n        }\n", 1)[0]
source += "\nextension FightPostThreadState {\n    func countChangedForTest(previous: Int, count: Int) {\n" + count_change + "\n    }\n}\n"
source += thread[thread.index("private struct DisplayedFightComment:"):]

with tempfile.TemporaryDirectory(prefix="fitfight-state-tests-") as directory:
    generated = Path(directory) / "NativeStateTests.swift"
    generated.write_text(source)
    executable = Path(directory) / "native-state-tests"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-target", f"{platform.machine()}-apple-macosx13.0",
        str(root / "FitFight/Media.swift"), str(generated), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
