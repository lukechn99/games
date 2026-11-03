'use client'

/**
 * Explorer and monster figurines, drawn like single-color plastic minis
 * on round bases. Each explorer has their own silhouette and prop.
 * Units: base sits at y = +12, heads reach about y = -24.
 */

const INK = '#151018'
const SHINE = '#ffffff55'

function Base({ color }: { color: string }) {
  return (
    <>
      <ellipse cx="0" cy="13" rx="12" ry="4.5" fill="#00000077" />
      <ellipse cx="0" cy="11.5" rx="11" ry="4" fill={color} stroke={INK} strokeWidth="1.2" />
      <ellipse cx="-3" cy="10.5" rx="5" ry="1.2" fill={SHINE} />
    </>
  )
}

/** Generic standing body: legs, torso and head. `w` widens the shoulders. */
function Body({ color, w = 1, dress = false, robe = false, kid = false }: { color: string; w?: number; dress?: boolean; robe?: boolean; kid?: boolean }) {
  const s = kid ? 0.82 : 1
  return (
    <g transform={`scale(${s}) translate(0 ${kid ? 3 : 0})`}>
      {dress || robe ? (
        <path d={`M${-4 * w} -5 L${-(robe ? 7 : 8) * w} 11 L${(robe ? 7 : 8) * w} 11 L${4 * w} -5 Z`} fill={color} stroke={INK} strokeWidth="1.2" strokeLinejoin="round" />
      ) : (
        <>
          <path d="M-3.5 2 L-4 11 L-1 11 L-0.5 3 M0.5 3 L1 11 L4 11 L3.5 2" fill={color} stroke={INK} strokeWidth="1.2" strokeLinejoin="round" />
        </>
      )}
      <path d={`M${-5 * w} -8 Q0 ${-11} ${5 * w} -8 L${4 * w} ${dress || robe ? -4 : 3} L${-4 * w} ${dress || robe ? -4 : 3} Z`} fill={color} stroke={INK} strokeWidth="1.2" strokeLinejoin="round" />
      <path d={`M${-5 * w} -7.5 L${-6.5 * w} 1 M${5 * w} -7.5 L${6.5 * w} 1`} stroke={INK} strokeWidth="1.2" />
      <path d={`M${-5 * w} -7.5 L${-6.5 * w} 1 M${5 * w} -7.5 L${6.5 * w} 1`} stroke={color} strokeWidth="2.6" strokeLinecap="round" opacity="0.9" />
      <circle cy="-14" r="5" fill={color} stroke={INK} strokeWidth="1.2" />
      <ellipse cx="-1.8" cy="-15.5" rx="1.6" ry="1.1" fill={SHINE} />
    </g>
  )
}

const props: Record<string, (c: string) => React.ReactNode> = {
  // Documentary maker with a camcorder
  vera: (c) => (
    <>
      <Body color={c} dress />
      <rect x="5" y="-6" width="7" height="5" rx="1" fill={c} stroke={INK} strokeWidth="1.1" />
      <circle cx="12.5" cy="-3.5" r="1.8" fill={INK} />
    </>
  ),
  // Shopkeeper in a wide-brimmed hat
  odessa: (c) => (
    <>
      <Body color={c} dress />
      <ellipse cx="0" cy="-17.5" rx="9" ry="2" fill={c} stroke={INK} strokeWidth="1.1" />
      <path d="M-4 -18 Q0 -25 4 -18" fill={c} stroke={INK} strokeWidth="1.1" />
    </>
  ),
  // Kid detective: cap and magnifying glass
  milo: (c) => (
    <g transform="scale(0.82) translate(0 3)">
      <Body color={c} />
      <path d="M-5 -15.5 Q0 -22 5 -15.5 L9 -15 L5 -14.5 L-5 -14.5 Z" fill={c} stroke={INK} strokeWidth="1.1" />
      <circle cx="9" cy="-5" r="3" fill="none" stroke={INK} strokeWidth="1.4" />
      <path d="M6.8 -2.8 L5 0" stroke={INK} strokeWidth="1.6" />
    </g>
  ),
  // Little magician: top hat and wand
  theo: (c) => (
    <g transform="scale(0.82) translate(0 3)">
      <Body color={c} />
      <rect x="-3.5" y="-25" width="7" height="7.5" fill={c} stroke={INK} strokeWidth="1.1" />
      <rect x="-6" y="-18.5" width="12" height="1.8" fill={c} stroke={INK} strokeWidth="1" />
      <path d="M5 -1 L11 -9" stroke={INK} strokeWidth="1.8" strokeLinecap="round" />
      <circle cx="11" cy="-9" r="1" fill="#fff" />
    </g>
  ),
  // Team captain: ponytail and a stick
  rosa: (c) => (
    <>
      <Body color={c} />
      <path d="M3 -17 Q8 -16 7 -10" fill="none" stroke={INK} strokeWidth="3.2" strokeLinecap="round" />
      <path d="M3 -17 Q8 -16 7 -10" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" />
      <path d="M-6 2 L-10 -16" stroke={INK} strokeWidth="1.5" />
      <ellipse cx="-10.5" cy="-18" rx="2.5" ry="3" fill="none" stroke={INK} strokeWidth="1.2" />
    </>
  ),
  // DJ with headphones, one arm up
  kiki: (c) => (
    <>
      <Body color={c} />
      <path d="M-5.5 -14 Q0 -22 5.5 -14" fill="none" stroke={INK} strokeWidth="1.6" />
      <rect x="-7.2" y="-16" width="3" height="4.5" rx="1.2" fill={c} stroke={INK} strokeWidth="1" />
      <rect x="4.2" y="-16" width="3" height="4.5" rx="1.2" fill={c} stroke={INK} strokeWidth="1" />
      <path d="M5 -7 L9 -16" stroke={INK} strokeWidth="3.4" strokeLinecap="round" />
      <path d="M5 -7 L9 -16" stroke={c} strokeWidth="2" strokeLinecap="round" />
    </>
  ),
  // Big lad, broad shoulders
  dex: (c) => <Body color={c} w={1.4} />,
  // Runner: headband, mid-stride
  elliot: (c) => (
    <>
      <path d="M-1 3 L-6 11 M1 3 L5 9 L7 11" stroke={INK} strokeWidth="3.4" strokeLinecap="round" fill="none" />
      <path d="M-1 3 L-6 11 M1 3 L5 9 L7 11" stroke={c} strokeWidth="2" strokeLinecap="round" fill="none" />
      <g>
        <path d="M-4.5 -8 Q0 -11 4.5 -8 L3.5 3 L-3.5 3 Z" fill={c} stroke={INK} strokeWidth="1.2" />
        <circle cy="-14" r="5" fill={c} stroke={INK} strokeWidth="1.2" />
        <path d="M-5 -15 L5 -15" stroke={INK} strokeWidth="1.6" />
        <path d="M5 -15 L8 -13" stroke={INK} strokeWidth="1.2" />
        <path d="M-4.5 -7 L-8 -2 M4.5 -7 L7 -12" stroke={INK} strokeWidth="1.2" />
      </g>
    </>
  ),
  // Doctor: glasses and a medical bag
  harold: (c) => (
    <>
      <Body color={c} />
      <path d="M-3.5 -14.5 h2.6 M1 -14.5 h2.6 M-0.9 -14.5 h1.9" stroke={INK} strokeWidth="1.3" />
      <rect x="6" y="-2" width="7" height="5.5" rx="1" fill={c} stroke={INK} strokeWidth="1.1" />
      <path d="M8 -2 Q9.5 -4.5 11 -2 M9.5 -0.5 v3 M8 1 h3" stroke={INK} strokeWidth="1" fill="none" />
    </>
  ),
  // Priest: long robe, white collar, a book
  amos: (c) => (
    <>
      <Body color={c} robe />
      <rect x="-1.2" y="-9.5" width="2.4" height="1.8" fill="#fff" stroke={INK} strokeWidth="0.6" />
      <rect x="-9" y="-4" width="5" height="6" fill={c} stroke={INK} strokeWidth="1.1" />
      <path d="M-6.5 -3 v4 M-8 -1.5 h3" stroke={INK} strokeWidth="0.9" />
    </>
  ),
  // Spooky kid in a hood
  wren: (c) => (
    <g transform="scale(0.82) translate(0 3)">
      <Body color={c} />
      <path d="M-6.5 -9 Q-8 -21 0 -21 Q8 -21 6.5 -9" fill="none" stroke={INK} strokeWidth="3.6" />
      <path d="M-6.5 -9 Q-8 -21 0 -21 Q8 -21 6.5 -9" fill="none" stroke={c} strokeWidth="2.2" />
    </g>
  ),
  // Herbalist kid: pigtails and a jar
  lucia: (c) => (
    <g transform="scale(0.82) translate(0 3)">
      <Body color={c} />
      <circle cx="-6" cy="-12" r="2.2" fill={c} stroke={INK} strokeWidth="1.1" />
      <circle cx="6" cy="-12" r="2.2" fill={c} stroke={INK} strokeWidth="1.1" />
      <rect x="5" y="-4" width="4.5" height="6" rx="1" fill={c} stroke={INK} strokeWidth="1.1" />
      <rect x="5.5" y="-5.5" width="3.5" height="1.5" fill={INK} />
    </g>
  ),
}

export function ExplorerFigure({ explorerId, color, x = 0, y = 0, dead, me, scale = 1 }: {
  explorerId: string; color: string; x?: number; y?: number; dead?: boolean; me?: boolean; scale?: number
}) {
  const draw = props[explorerId] ?? ((c: string) => <Body color={c} />)
  return (
    <g transform={`translate(${x} ${y}) scale(${scale})`} opacity={dead ? 0.55 : 1}>
      {me && <ellipse cx="0" cy="12" rx="15" ry="6" fill="none" stroke="#fff" strokeWidth="1.6" strokeDasharray="3 2.5" />}
      <Base color={color} />
      {dead ? (
        // Fallen over
        <g transform="translate(0 6) rotate(-80)">{draw(color)}</g>
      ) : (
        draw(color)
      )}
    </g>
  )
}

export function MonsterFigure({ kind, x = 0, y = 0, stunned, selected, number }: {
  kind: string; x?: number; y?: number; stunned?: boolean; selected?: boolean; number?: string
}) {
  const red = '#5b0000'
  let body: React.ReactNode
  if (kind === 'shark') {
    body = (
      <g>
        <path d="M-14 6 Q-4 -2 6 2 Q12 4 15 0 L13 8 Q0 12 -14 6 Z" fill="#2b6cb0" stroke={INK} strokeWidth="1.2" />
        <path d="M-2 1 L3 -14 L8 2 Z" fill="#2b6cb0" stroke={INK} strokeWidth="1.2" strokeLinejoin="round" />
        <path d="M6 6 l2 -2 l2 2 l2 -2" stroke="#fff" strokeWidth="1" fill="none" />
        <path d="M-14 6 Q-20 2 -18 -2 Q-16 4 -12 4" fill="#2b6cb0" stroke={INK} strokeWidth="1.1" />
      </g>
    )
  } else if (kind === 'mannequin') {
    const c = '#d9c7b8'
    body = (
      <g>
        <path d="M0 2 V11 M-5 11 H5" stroke={INK} strokeWidth="1.6" />
        <path d="M-5 -8 Q0 -11 5 -8 L4 3 Q0 5 -4 3 Z" fill={c} stroke={INK} strokeWidth="1.2" />
        <path d="M-5 -7.5 L-7 1 M5 -7.5 L7 1" stroke={INK} strokeWidth="2.6" strokeLinecap="round" />
        <path d="M-5 -7.5 L-7 1 M5 -7.5 L7 1" stroke={c} strokeWidth="1.4" strokeLinecap="round" />
        <ellipse cy="-14" rx="4.2" ry="5.2" fill={c} stroke={INK} strokeWidth="1.2" />
        <path d="M-2 -10.5 Q0 -9.5 2 -10.5" stroke={red} strokeWidth="0.9" fill="none" />
      </g>
    )
  } else {
    // Wedding guest: a veiled, ghostly figure
    const c = '#e9e2f5'
    body = (
      <g opacity="0.92">
        <path d="M-8 11 Q-9 -4 -5 -10 Q0 -14 5 -10 Q9 -4 8 11 Q4 8 0 11 Q-4 8 -8 11 Z" fill={c} stroke={INK} strokeWidth="1.2" />
        <circle cy="-13" r="4.5" fill={c} stroke={INK} strokeWidth="1.2" />
        <path d="M-5 -15 Q0 -24 5 -15 Q9 -6 7 0" fill="none" stroke="#b9acd6" strokeWidth="1.6" />
        <circle cx="-1.6" cy="-13.5" r="0.9" fill={INK} />
        <circle cx="1.6" cy="-13.5" r="0.9" fill={INK} />
      </g>
    )
  }
  return (
    <g transform={`translate(${x} ${y})`} opacity={stunned ? 0.5 : 1}>
      {selected && <ellipse cx="0" cy="12" rx="16" ry="6.5" fill="none" stroke="#f6d860" strokeWidth="2.5" />}
      <ellipse cx="0" cy="13" rx="12" ry="4.5" fill="#00000077" />
      <ellipse cx="0" cy="11.5" rx="11" ry="4" fill="#3a0a0a" stroke={INK} strokeWidth="1.2" />
      {stunned ? <g transform="translate(0 6) rotate(75)">{body}</g> : body}
      {number && (
        <g transform="translate(10 -16)">
          <circle r="5.5" fill={red} stroke="#fff" strokeWidth="1" />
          <text y="3" textAnchor="middle" fontSize="7.5" fontWeight="800" fill="#fff">{number}</text>
        </g>
      )}
      {stunned && <text y="-22" textAnchor="middle" fontSize="9" fill="#fff">stunned</text>}
    </g>
  )
}
