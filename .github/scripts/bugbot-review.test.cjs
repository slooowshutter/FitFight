const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");
const requestReview = require("./bugbot-review.cjs");

function fixture({ base = "develop", branch = "feature/example", labels = [], fork = false, draft = false, state = "open", token = true, accountType = "User" } = {}) {
    const pull = {
        number: 42,
        state,
        draft,
        labels: labels.map((name) => ({ name })),
        head: {
            ref: branch,
            sha: "head-commit",
            repo: { full_name: fork ? "someone/FitFight" : "slooowshutter/FitFight" },
        },
        base: { ref: base, sha: "base-commit", repo: { full_name: "slooowshutter/FitFight" } },
    };
    const comments = [];
    const writes = [];
    const responses = [pull, pull];
    const issues = {
        listComments: "listComments",
        createComment: async (input) => writes.push({ kind: "comment", ...input }),
        addLabels: async (input) => writes.push({ kind: "label", ...input }),
    };
    const input = {
        context: { repo: { owner: "slooowshutter", repo: "FitFight" }, issue: { number: 42 } },
        core: { info() {} },
        triggerTokenAvailable: token,
        github: {
            rest: {
                pulls: { get: async () => ({ data: responses.shift() }) },
                users: { getAuthenticated: async () => ({ data: { login: "slooowshutter", type: accountType } }) },
                issues,
            },
            paginate: async (method) => {
                assert.equal(method, issues.listComments);
                return comments;
            },
        },
    };
    return { input, pull, comments, writes, responses };
}

for (const scenario of [
    { name: "Conductor development PR", token: false, expected: 0 },
    { name: "Cursor branch", branch: "cursor/fix-steps", expected: 1 },
    { name: "renamed Cursor branch", labels: ["origin:cursor"], expected: 1 },
    { name: "preview release", base: "preview", expected: 1 },
    { name: "production release", base: "main", expected: 1 },
    { name: "fork cannot claim Cursor origin by branch name", branch: "cursor/spam", fork: true, expected: 0 },
    { name: "explicitly labeled fork", labels: ["origin:cursor"], fork: true, expected: 1 },
    { name: "fork release", base: "preview", fork: true, expected: 1 },
    { name: "draft release", base: "main", draft: true, expected: 0 },
    { name: "closed release", base: "main", state: "closed", expected: 0 },
]) {
    test(scenario.name, async () => {
        const { input, writes } = fixture(scenario);
        await requestReview(input);
        const requested = writes.filter((write) => write.kind === "comment");
        assert.equal(requested.length, scenario.expected);
        if (scenario.expected) {
            assert.equal(requested[0].issue_number, 42);
            assert.match(requested[0].body, /^cursor review\n\n<!-- fitfight-bugbot:42:head-commit:/);
        }
        assert.equal(writes.filter((write) => write.kind === "label").length, scenario.name === "Cursor branch" ? 1 : 0);
    });
}

test("selected review fails without its credential", async () => {
    const { input, writes } = fixture({ base: "preview", token: false });
    await assert.rejects(requestReview(input), /BUGBOT_GITHUB_TOKEN/);
    assert.deepEqual(writes, []);
});

test("bot credentials cannot send review triggers", async () => {
    const { input, writes } = fixture({ base: "preview", accountType: "Bot" });
    await assert.rejects(requestReview(input), /GitHub user/);
    assert.deepEqual(writes, []);
});

for (const previous of [
    { name: "duplicate diff", login: "slooowshutter", head: "head-commit", base: "preview", baseSha: "base-commit", expected: 0 },
    { name: "new commit", login: "slooowshutter", head: "old-head", base: "preview", baseSha: "base-commit", expected: 1 },
    { name: "changed destination", login: "slooowshutter", head: "head-commit", base: "develop", baseSha: "base-commit", expected: 1 },
    { name: "updated base", login: "slooowshutter", head: "head-commit", base: "preview", baseSha: "old-base", expected: 1 },
    { name: "untrusted duplicate marker", login: "someone-else", head: "head-commit", base: "preview", baseSha: "base-commit", expected: 1 },
]) {
    test(previous.name, async () => {
        const { input, comments, writes } = fixture({ base: "preview" });
        comments.push({
            user: { login: previous.login },
            body: `cursor review\n\n<!-- fitfight-bugbot:42:${previous.head}:${previous.base}:${previous.baseSha} -->`,
        });
        await requestReview(input);
        assert.equal(writes.filter((write) => write.kind === "comment").length, previous.expected);
    });
}

test("a commit arriving during processing does not receive a stale marker", async () => {
    const { input, pull, responses, writes } = fixture({ base: "preview" });
    responses[1] = { ...pull, head: { ...pull.head, sha: "new-head" } };
    await requestReview(input);
    assert.deepEqual(writes, []);
});

test("a failed comment request remains retryable", async () => {
    const { input, comments } = fixture({ base: "preview" });
    input.github.rest.issues.createComment = async () => { throw new Error("GitHub unavailable"); };
    await assert.rejects(requestReview(input), /GitHub unavailable/);
    assert.deepEqual(comments, []);
});

test("release protection is staged only for preview and main", () => {
    const ruleset = JSON.parse(readFileSync(path.join(__dirname, "../bugbot-release-ruleset.json"), "utf8"));
    assert.equal(ruleset.enforcement, "disabled");
    assert.deepEqual(ruleset.conditions.ref_name, {
        include: ["refs/heads/preview", "refs/heads/main"],
        exclude: [],
    });
    const checkRule = ruleset.rules.find((rule) => rule.type === "required_status_checks");
    assert.deepEqual(checkRule.parameters.required_status_checks, [
        { context: "Cursor Bugbot", integration_id: 1210556 },
    ]);
    const pullRule = ruleset.rules.find((rule) => rule.type === "pull_request");
    assert.equal(pullRule.parameters.required_review_thread_resolution, true);
});
