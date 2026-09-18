/** Requests reviews using trusted PR metadata without executing the PR's code. */
module.exports = async ({ github, context, core, triggerTokenAvailable }) => {
    const repository = context.repo;
    const { data: pull } = await github.rest.pulls.get({
        ...repository,
        pull_number: context.issue.number,
    });

    if (pull.state !== "open" || pull.draft) {
        core.info("Bugbot is deferred until the PR is open and ready for review.");
        return;
    }

    const cursorLabel = pull.labels.some((label) => label.name === "origin:cursor");
    const cursorBranch =
        pull.head.repo?.full_name === pull.base.repo.full_name &&
        pull.head.ref.startsWith("cursor/");
    const release = ["preview", "main"].includes(pull.base.ref);

    if (!release && !cursorLabel && !cursorBranch) {
        core.info("Bugbot is optional for this development PR.");
        return;
    }

    if (!triggerTokenAvailable) {
        throw new Error("Selected review needs the BUGBOT_GITHUB_TOKEN repository secret.");
    }

    // Cursor comment triggers need a user identity with Bugbot access.
    const { data: account } = await github.rest.users.getAuthenticated();
    if (account.type !== "User") {
        throw new Error("BUGBOT_GITHUB_TOKEN must belong to a GitHub user with Bugbot access.");
    }

    const marker = `<!-- fitfight-bugbot:${pull.number}:${pull.head.sha}:${pull.base.ref}:${pull.base.sha} -->`;
    const comments = await github.paginate(github.rest.issues.listComments, {
        ...repository,
        issue_number: pull.number,
        per_page: 100,
    });
    if (comments.some((comment) => comment.user?.login === account.login && comment.body?.includes(marker))) {
        core.info("Bugbot was already requested for this PR diff.");
        return;
    }

    const { data: current } = await github.rest.pulls.get({
        ...repository,
        pull_number: pull.number,
    });
    if (
        current.state !== "open" ||
        current.draft ||
        current.head.sha !== pull.head.sha ||
        current.base.ref !== pull.base.ref ||
        current.base.sha !== pull.base.sha
    ) {
        core.info("The PR changed while processing; its next event will select the current diff.");
        return;
    }

    if (cursorBranch && !cursorLabel) {
        await github.rest.issues.addLabels({
            ...repository,
            issue_number: pull.number,
            labels: ["origin:cursor"],
        });
    }

    await github.rest.issues.createComment({
        ...repository,
        issue_number: pull.number,
        body: `cursor review\n\n${marker}`,
    });
    core.info(`Requested Bugbot for PR #${pull.number}.`);
};
