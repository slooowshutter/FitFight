"use client";

import { useEffect, useId, useRef, useState } from "react";

const TESTFLIGHT_URL = "https://testflight.apple.com/join/wcZKdwVZ";

function TestflightInstallSteps() {
  return (
    <ol className="install-steps">
      <li>
        <strong>First tap installs TestFlight.</strong> If you don&apos;t already
        have Apple&apos;s TestFlight app, this link installs TestFlight — not FitFight.
        That is expected.
      </li>
      <li>
        <strong>Tap the same link again to install FitFight.</strong> After
        TestFlight is on your iPhone, come back and open this same link a second
        time. That second tap is what adds FitFight.
      </li>
      <li>
        <strong>You do not need a code.</strong> If TestFlight asks for a
        redemption code, you skipped the second tap. Close that screen and open
        this same link again.
      </li>
    </ol>
  );
}

export function InviteDownload() {
  useEffect(() => {
    const isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent)
      || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    if (!isIOS) return;
    const timer = window.setTimeout(() => {
      if (document.visibilityState === "visible") {
        window.location.assign(TESTFLIGHT_URL);
      }
    }, 5000);
    return () => window.clearTimeout(timer);
  }, []);

  return (
    <section>
      <h2>Get FitFight</h2>
      <p>
        FitFight is a TestFlight beta, not on the App Store. On iPhone, this page
        opens the TestFlight link after a few seconds.
      </p>
      <TestflightInstallSteps />
      <p>
        <strong>Once FitFight is installed, return to your friend&apos;s message and tap that original FitFight link again.</strong>{" "}
        Sign in to continue with your referral or challenge. You still choose whether to join.
      </p>
      <a className="primary-action invite-download" href={TESTFLIGHT_URL} rel="noreferrer">
        Open this TestFlight link
      </a>
      <p>Already have FitFight? Reopen the link from your friend&apos;s message to open the app.</p>
    </section>
  );
}

export function TestflightInvite({
  label,
  kind,
}: {
  label: string;
  kind: "header" | "hero";
}) {
  const titleId = useId();
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        type="button"
        className={kind === "header" ? "header-action" : "primary-action"}
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => {
          dialogRef.current?.showModal();
          setOpen(true);
        }}
      >
        {label}
      </button>
      <dialog
        ref={dialogRef}
        className="testflight-dialog"
        aria-labelledby={titleId}
        onClose={() => setOpen(false)}
        onClick={(event) => {
          if (event.target === event.currentTarget) {
            event.currentTarget.close();
          }
        }}
      >
        <p className="eyebrow">BETA ON TESTFLIGHT</p>
        <h2 id={titleId}>How to install FitFight</h2>
        <p>
          FitFight isn&apos;t on the App Store yet. Apple uses TestFlight for this
          beta, and you tap the same link twice.
        </p>
        <TestflightInstallSteps />
        <a
          className="primary-action"
          href={TESTFLIGHT_URL}
          target="_blank"
          rel="noopener noreferrer"
        >
          Open this TestFlight link
        </a>
        <button
          type="button"
          className="dialog-dismiss"
          onClick={() => dialogRef.current?.close()}
        >
          Not now
        </button>
      </dialog>
    </>
  );
}
