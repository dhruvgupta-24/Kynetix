"use client";
import * as React from "react";

// Lightweight headline markup, rendered on the canvas and in exports:
//   [word]  the accent colour (one emphasis word per headline)
//   {word}  the "shear": the word is cut through mid-cap, the top half slides
//           right and a thin accent line sits in the cut (the Kynetix wordmark motif)
// Everything else renders as typed. Newlines are kept by the caller's pre-wrap.

/** Font pairing's display face, if the screenshot font defines one. */
export const HeadlineFamilyContext = React.createContext<string | undefined>(undefined);

type Token = { kind: "plain" | "accent" | "shear"; text: string };

export function parseRich(text: string): Token[] {
  const tokens: Token[] = [];
  const re = /\[([^\]\n]+)\]|\{([^}\n]+)\}/g;
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    if (m.index > last) tokens.push({ kind: "plain", text: text.slice(last, m.index) });
    tokens.push(m[1] !== undefined ? { kind: "accent", text: m[1] } : { kind: "shear", text: m[2] });
    last = m.index + m[0].length;
  }
  if (last < text.length) tokens.push({ kind: "plain", text: text.slice(last) });
  return tokens;
}

export function hasRichMarkup(text: string) {
  return /\[[^\]\n]+\]|\{[^}\n]+\}/.test(text);
}

/** Strip markup, for places that only show plain text. */
export function plainRich(text: string) {
  return text.replace(/\[([^\]\n]+)\]|\{([^}\n]+)\}/g, (_m, a, b) => a ?? b);
}

// Geometry in em, tuned to Bricolage Grotesque (typo ascent .93, descent .27,
// cap height .66) at the caption's line-height of 0.96: mid-cap sits at
// 0.48em from the top of the line box. Proportions follow the wordmark SVG,
// with the gap and line thickened so they survive store thumbnails.
const cutFor = (lineHeight: number) => (lineHeight - 1.2) / 2 + 0.6;
const GAP = 0.06;
const LINE = 0.042;
const SHIFT = 0.09;

export function Shear({ text, accent, lineHeight = 0.96 }: { text: string; accent: string; lineHeight?: number }) {
  const CUT = cutFor(lineHeight);
  const half = GAP / 2;
  const common: React.CSSProperties = {
    position: "absolute",
    left: 0,
    top: 0,
    whiteSpace: "pre",
  };
  return (
    <span style={{ position: "relative", display: "inline-block", whiteSpace: "pre", lineHeight: "inherit" }}>
      <span style={{ visibility: "hidden" }}>{text}</span>
      <span
        aria-hidden
        style={{
          position: "absolute",
          left: "-0.24em",
          width: "0.86em",
          top: `${CUT - LINE / 2}em`,
          height: `${LINE}em`,
          borderRadius: `${LINE}em`,
          background: accent,
        }}
      />
      <span
        aria-hidden
        style={{
          ...common,
          clipPath: `polygon(-1em -1em, 100em -1em, 100em ${CUT - half}em, -1em ${CUT - half}em)`,
          transform: `translateX(${SHIFT}em)`,
        }}
      >
        {text}
      </span>
      <span
        aria-hidden
        style={{
          ...common,
          clipPath: `polygon(-1em ${CUT + half}em, 100em ${CUT + half}em, 100em 100em, -1em 100em)`,
        }}
      >
        {text}
      </span>
    </span>
  );
}

export function RichText({ text, accent, lineHeight }: { text: string; accent: string; lineHeight?: number }) {
  return (
    <>
      {parseRich(text).map((t, i) =>
        t.kind === "plain" ? (
          <React.Fragment key={i}>{t.text}</React.Fragment>
        ) : t.kind === "accent" ? (
          <span key={i} style={{ color: accent }}>
            {t.text}
          </span>
        ) : (
          <Shear key={i} text={t.text} accent={accent} lineHeight={lineHeight} />
        ),
      )}
    </>
  );
}
