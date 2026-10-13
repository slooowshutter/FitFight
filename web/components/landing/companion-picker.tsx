"use client";

import { useState } from "react";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";
import {
    companionPose,
    formatSteps,
    landingCopy,
    sampleTodaySteps,
} from "./landing-copy";

const maxSteps = 20000;
// Tapping a pose moves the slider into that pose's range.
const poseSteps = [1500, 4500, 8000, 12500, 17000];

export function CompanionPicker({ language }: { language: SiteLanguage }) {
    const text = landingCopy[language].companions;
    const [animal, setAnimal] = useState(text.animals[0]);
    const [steps, setSteps] = useState(sampleTodaySteps);
    const fill = (steps / maxSteps) * 100;

    return (
        <div className="lp-card lp-picker">
            <div className="lp-picker-pick">
                <p className="lp-picker-label">
                    <b>1</b>
                    {text.pick}
                </p>
                <div className="lp-picker-grid">
                    {text.animals.map((option) => (
                        <button
                            key={option.id}
                            type="button"
                            className={
                                option.id === animal.id ? "lp-on" : undefined
                            }
                            aria-label={option.name}
                            aria-pressed={option.id === animal.id}
                            onClick={() => setAnimal(option)}
                        >
                            <img
                                src={`/landing/companion-${option.id}-avatar.webp`}
                                alt=""
                                width={64}
                                height={64}
                                loading="lazy"
                            />
                        </button>
                    ))}
                </div>
                <p className="lp-picker-name">
                    <b>{animal.name}</b>
                    {animal.caption}
                </p>
            </div>
            <div className="lp-picker-walk">
                <p className="lp-picker-label">
                    <b>2</b>
                    {text.walk}
                </p>
                <div className="lp-picker-poses">
                    {text.poses.map((pose, index) => (
                        <button
                            key={pose}
                            type="button"
                            className={
                                index + 1 === companionPose(steps)
                                    ? "lp-on"
                                    : undefined
                            }
                            aria-label={`${pose}, ${text.ranges[index]}`}
                            onClick={() => setSteps(poseSteps[index])}
                        >
                            <img
                                src={`/landing/companion-${animal.id}-${index + 1}.webp`}
                                alt=""
                                width={132}
                                height={150}
                                loading="lazy"
                            />
                            <b>{pose}</b>
                            <small>{text.ranges[index]}</small>
                        </button>
                    ))}
                </div>
                <label className="lp-picker-slider">
                    <span>{text.stepsToday}</span>
                    <b>{formatSteps(steps, language)}</b>
                    <input
                        type="range"
                        className="lp-range"
                        min={0}
                        max={maxSteps}
                        value={steps}
                        aria-label={text.stepsToday}
                        style={{
                            background: `linear-gradient(to right, var(--gold) ${fill}%, var(--track) ${fill}%)`,
                        }}
                        onChange={(event) =>
                            setSteps(Number(event.target.value))
                        }
                    />
                </label>
            </div>
        </div>
    );
}
