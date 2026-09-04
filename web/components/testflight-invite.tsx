"use client";

import { useId, useRef, useState } from "react";

const TESTFLIGHT_URL = "https://testflight.apple.com/join/wcZKdwVZ";

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
        <h2 id={titleId}>Get FitFight on your iPhone</h2>
        <p>
          FitFight isn&apos;t on the App Store yet. Apple uses TestFlight for beta
          apps — that&apos;s the official way to try an iPhone app before it&apos;s public.
        </p>
        <ol>
          <li>Open this on your iPhone and tap Open TestFlight.</li>
          <li>Install Apple&apos;s TestFlight app if you don&apos;t have it yet.</li>
          <li>Accept the invite, install FitFight, then open it.</li>
        </ol>
        <a
          className="primary-action"
          href={TESTFLIGHT_URL}
          target="_blank"
          rel="noopener noreferrer"
        >
          Open TestFlight
        </a>
        <p className="testflight-link-line">
          Or copy this link on your phone:{" "}
          <a href={TESTFLIGHT_URL} target="_blank" rel="noopener noreferrer">
            testflight.apple.com/join/wcZKdwVZ
          </a>
        </p>
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
