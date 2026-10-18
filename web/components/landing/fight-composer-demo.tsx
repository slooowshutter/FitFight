"use client";

import { useState } from "react";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";
import { landingCopy } from "./landing-copy";
import { Icon, PhoneFrame } from "./landing-mocks";

const inviteCode = "K7QM";

// The five New fight steps of the app, then the invite. Nothing is saved.
export function FightComposerDemo({ language }: { language: SiteLanguage }) {
    const text = landingCopy[language].composer;
    const [step, setStep] = useState(1);
    const [length, setLength] = useState(text.lengths[1]);
    const [repeats, setRepeats] = useState(false);
    const [isPublic, setIsPublic] = useState(false);
    const [title, setTitle] = useState(text.defaultTitle);
    const [action, setAction] = useState(text.defaultAction);
    const trimmedTitle = title.trim();
    const trimmedAction = action.trim();
    const loserAction =
        trimmedAction.charAt(0).toLowerCase() + trimmedAction.slice(1);

    if (step === 6) {
        return (
            <PhoneFrame language={language}>
                <div className="lp-cp lp-cp-done">
                    <span className="lp-cp-check">
                        <Icon name="check" size={36} weight={2.6} />
                    </span>
                    <h3 className="lp-cp-h">{text.doneTitle}</h3>
                    <p className="lp-cp-p">{text.doneText(trimmedTitle)}</p>
                    <div className="lp-card lp-cp-link">
                        <span>fitfight.app/j/{inviteCode}</span>
                        <b>{inviteCode}</b>
                    </div>
                    <span className="lp-cp-button">
                        <Icon name="share" size={18} />
                        {text.share}
                    </span>
                    <button
                        type="button"
                        className="lp-cp-button lp-cp-secondary"
                        onClick={() => {
                            setStep(1);
                            setLength(text.lengths[1]);
                            setRepeats(false);
                            setIsPublic(false);
                            setTitle(text.defaultTitle);
                            setAction(text.defaultAction);
                        }}
                    >
                        {text.restart}
                    </button>
                </div>
            </PhoneFrame>
        );
    }

    return (
        <PhoneFrame language={language}>
            <div className="lp-cp">
                <div className="lp-cp-top">
                    <button
                        type="button"
                        onClick={() => setStep(Math.max(1, step - 1))}
                    >
                        <Icon name="back" size={18} weight={2.2} />
                        {text.back}
                    </button>
                    <span>{text.stepOf(step)}</span>
                </div>
                <div className="lp-cp-progress">
                    {[1, 2, 3, 4, 5].map((index) => (
                        <i
                            key={index}
                            className={index <= step ? "lp-on" : undefined}
                        />
                    ))}
                </div>
                <div className="lp-cp-body">
                    {step === 1 ? (
                        <>
                            <h3 className="lp-cp-h">{text.metricTitle}</h3>
                            <p className="lp-cp-p">{text.metricText}</p>
                            <div className="lp-card lp-cp-option">
                                <i>
                                    <Icon name="walk" size={20} />
                                </i>
                                <div>
                                    <b>{text.steps}</b>
                                    <small>{text.stepsDetail}</small>
                                </div>
                                <Icon name="check" weight={2.2} />
                            </div>
                        </>
                    ) : null}
                    {step === 2 ? (
                        <>
                            <h3 className="lp-cp-h">{text.lengthTitle}</h3>
                            <p className="lp-cp-p">{text.lengthText}</p>
                            <b className="lp-cp-label">{text.duration}</b>
                            <div className="lp-cp-grid">
                                {text.lengths.map((option) => (
                                    <button
                                        key={option}
                                        type="button"
                                        className={
                                            option === length
                                                ? "lp-cp-pill lp-on"
                                                : "lp-cp-pill"
                                        }
                                        onClick={() => setLength(option)}
                                    >
                                        {option}
                                    </button>
                                ))}
                            </div>
                            <span className="lp-cp-pill lp-cp-wide">
                                {text.custom}
                            </span>
                            <div className="lp-card lp-cp-toggle">
                                <div>
                                    <b>{text.repeat}</b>
                                    <small>{text.repeatDetail}</small>
                                </div>
                                <button
                                    type="button"
                                    className={
                                        repeats
                                            ? "lp-cp-switch lp-on"
                                            : "lp-cp-switch"
                                    }
                                    aria-label={text.repeat}
                                    aria-pressed={repeats}
                                    onClick={() => setRepeats(!repeats)}
                                >
                                    <i />
                                </button>
                            </div>
                        </>
                    ) : null}
                    {step === 3 ? (
                        <>
                            <h3 className="lp-cp-h">{text.joinTitle}</h3>
                            <p className="lp-cp-p">
                                {isPublic ? text.joinPublic : text.joinPrivate}
                            </p>
                            <div className="lp-card lp-cp-radio">
                                {[false, true].map((option) => (
                                    <button
                                        key={String(option)}
                                        type="button"
                                        className={
                                            option === isPublic
                                                ? "lp-on"
                                                : undefined
                                        }
                                        onClick={() => setIsPublic(option)}
                                    >
                                        <div>
                                            <b>
                                                {option
                                                    ? text.public
                                                    : text.private}
                                            </b>
                                            <small>
                                                {option
                                                    ? text.publicDetail
                                                    : text.privateDetail}
                                            </small>
                                        </div>
                                        <span />
                                    </button>
                                ))}
                            </div>
                            <b className="lp-cp-label">{text.username}</b>
                            <div className="lp-cp-user">
                                <span>{text.usernamePlaceholder}</span>
                                <span className="lp-cp-add">{text.add}</span>
                            </div>
                            <div className="lp-cp-chips">
                                <span>@leo</span>
                                <span>@nina</span>
                                <span>@sam</span>
                            </div>
                        </>
                    ) : null}
                    {step === 4 ? (
                        <>
                            <h3 className="lp-cp-h">{text.titleTitle}</h3>
                            <p className="lp-cp-p">{text.titleText}</p>
                            <label className="lp-cp-field">
                                <small>{text.title}</small>
                                <input
                                    value={title}
                                    placeholder={text.titlePlaceholder}
                                    maxLength={40}
                                    onChange={(event) =>
                                        setTitle(event.target.value)
                                    }
                                />
                            </label>
                            <label className="lp-cp-field">
                                <small>{text.action}</small>
                                <input
                                    value={action}
                                    placeholder={text.actionPlaceholder}
                                    maxLength={60}
                                    onChange={(event) =>
                                        setAction(event.target.value)
                                    }
                                />
                            </label>
                        </>
                    ) : null}
                    {step === 5 ? (
                        <>
                            <h3 className="lp-cp-h">{text.reviewTitle}</h3>
                            <p className="lp-cp-p">{text.reviewText}</p>
                            <div className="lp-card lp-cp-review">
                                <div>
                                    <b>{text.metric}</b>
                                    <span>{text.metricValue}</span>
                                </div>
                                <div>
                                    <b>{text.duration}</b>
                                    <span>
                                        {length}
                                        {repeats ? text.repeats : ""}
                                    </span>
                                </div>
                                <div>
                                    <b>
                                        {isPublic ? text.public : text.private}
                                    </b>
                                    <span>
                                        {isPublic
                                            ? text.publicDetail
                                            : text.privateValue}
                                    </span>
                                </div>
                                <div>
                                    <b>{text.title}</b>
                                    <span>{trimmedTitle}</span>
                                </div>
                                <div>
                                    <b>{text.action}</b>
                                    <span>{trimmedAction || text.none}</span>
                                </div>
                                <div>
                                    <b>{text.health}</b>
                                    <span className="lp-moss">
                                        {text.connected}
                                    </span>
                                </div>
                            </div>
                            <p className="lp-cp-summary">
                                <b>{text.versus}</b> {text.winner(length)}
                                {trimmedAction
                                    ? ` ${text.loserWill(loserAction)}`
                                    : ""}
                            </p>
                        </>
                    ) : null}
                </div>
                <button
                    type="button"
                    className="lp-cp-button"
                    disabled={step === 4 && !trimmedTitle}
                    onClick={() => setStep(step + 1)}
                >
                    {step === 5 ? text.start : text.next}
                </button>
            </div>
        </PhoneFrame>
    );
}
