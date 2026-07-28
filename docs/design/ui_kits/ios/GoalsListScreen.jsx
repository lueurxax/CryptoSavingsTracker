// GoalsListScreen.jsx — recreates GoalsListView + UnifiedGoalRowView
// shows emoji avatar, goal name, progress ring, status chip, amount, deadline

function GoalsListScreen({ dark, onOpenGoal }) {
  const goals = [
    { id: 1, emoji: '🏖️', name: 'Trip · Portugal', saved: 1980, target: 3000, deadline: 'Aug 2026', status: 'on' },
    { id: 2, emoji: '🏠', name: 'House deposit', saved: 112305, target: 180000, deadline: 'Apr 2029', status: 'warn' },
    { id: 3, emoji: '🚗', name: 'Car replacement', saved: 8200, target: 22000, deadline: 'Jan 2027', status: 'on' },
    { id: 4, emoji: '💍', name: 'Engagement ring', saved: 1500, target: 9000, deadline: 'Dec 2025', status: 'off' },
    { id: 5, emoji: '🎓', name: 'Masters programme', saved: 4600, target: 40000, deadline: 'Sep 2027', status: 'warn' },
    { id: 6, emoji: '✈️', name: 'Japan sabbatical', saved: 3750, target: 8000, deadline: 'Oct 2026', status: 'on' },
  ];

  const bg = dark ? '#000' : '#F2F2F7';
  const cardBg = dark ? '#1C1C1E' : '#FFFFFF';
  const fg1 = dark ? '#fff' : '#1A1A1A';
  const fg2 = dark ? 'rgba(235,235,245,0.6)' : '#6E6E73';
  const sep = dark ? 'rgba(84,84,88,0.35)' : 'rgba(60,60,67,0.12)';
  const primary = '#007ACC';

  const statusColor = {
    on: '#00875A', warn: '#B84D00', off: '#CC0000',
  };
  const statusLabel = {
    on: 'On Track', warn: 'At Risk', off: 'Off Track',
  };
  const statusIcon = {
    on: '✓', warn: '⚠', off: '✕',
  };

  const fmt = (n) => '$' + n.toLocaleString('en-US');

  return (
    <div style={{ background: bg, minHeight: '100%', padding: '8px 16px 120px' }}>
      {/* search bar */}
      <div style={{
        display:'flex', alignItems:'center', gap:8, height: 36,
        background: dark ? 'rgba(118,118,128,0.24)' : 'rgba(118,118,128,0.12)',
        borderRadius: 10, padding: '0 10px', marginBottom: 12,
      }}>
        <svg width="15" height="15" viewBox="0 0 15 15" fill="none"><circle cx="6.5" cy="6.5" r="5" stroke={fg2} strokeWidth="1.5"/><path d="M10.5 10.5l3.5 3.5" stroke={fg2} strokeWidth="1.5" strokeLinecap="round"/></svg>
        <span style={{ color: fg2, fontSize: 17, letterSpacing: -0.43 }}>Search goals</span>
      </div>

      {/* summary tile */}
      <div style={{
        background: cardBg, borderRadius: 16, padding: '16px 18px', marginBottom: 16,
        boxShadow: dark ? 'none' : '0 1px 2px rgba(0,0,0,0.05)',
      }}>
        <div style={{ color: fg2, fontSize: 12, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.6 }}>Total saved</div>
        <div style={{
          color: fg1, fontSize: 34, fontWeight: 700, letterSpacing: -0.6,
          fontVariantNumeric: 'tabular-nums', marginTop: 2,
        }}>$132,335.00</div>
        <div style={{ color: '#00875A', fontSize: 13, fontWeight: 600, marginTop: 2 }}>▲ $4,210.00 <span style={{ color: fg2, fontWeight: 400 }}>this month</span></div>
      </div>

      {/* section header */}
      <div style={{ color: fg2, fontSize: 13, fontWeight: 400, textTransform: 'uppercase', letterSpacing: -0.08, padding: '8px 16px 6px' }}>Active goals · {goals.length}</div>

      {/* list */}
      <div style={{ background: cardBg, borderRadius: 16, overflow: 'hidden' }}>
        {goals.map((g, i) => {
          const pct = Math.min(100, Math.round((g.saved / g.target) * 100));
          const color = statusColor[g.status];
          const r = 18, circ = 2 * Math.PI * r;
          return (
            <div key={g.id}
              onClick={() => onOpenGoal && onOpenGoal(g)}
              style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '12px 16px', cursor: 'pointer',
                borderTop: i === 0 ? 'none' : `0.5px solid ${sep}`,
              }}>
              <div style={{ width: 44, height: 44, borderRadius: 10, background: dark ? 'rgba(118,118,128,0.24)' : '#F2F2F7', display:'flex', alignItems:'center', justifyContent:'center', fontSize: 24 }}>{g.emoji}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ color: fg1, fontSize: 17, fontWeight: 600, letterSpacing: -0.43 }}>{g.name}</div>
                <div style={{ color: fg2, fontSize: 13, fontVariantNumeric: 'tabular-nums', marginTop: 2 }}>{fmt(g.saved)} <span style={{ opacity: 0.7 }}>/ {fmt(g.target)}</span> · {g.deadline}</div>
                <div style={{ display:'flex', alignItems:'center', gap: 8, marginTop: 6 }}>
                  <div style={{ flex: 1, height: 4, borderRadius: 2, background: dark ? 'rgba(118,118,128,0.24)' : '#E5E5EA', overflow: 'hidden' }}>
                    <div style={{ width: `${pct}%`, height: '100%', background: color, borderRadius: 2 }}/>
                  </div>
                  <div style={{
                    display:'inline-flex', alignItems:'center', gap:4,
                    padding:'2px 8px', borderRadius: 999, background: color + '1A', color,
                    fontSize: 11, fontWeight: 600,
                  }}>{statusIcon[g.status]} {statusLabel[g.status]}</div>
                </div>
              </div>
              {/* mini ring */}
              <svg width="44" height="44" viewBox="0 0 44 44" style={{ flexShrink: 0 }}>
                <circle cx="22" cy="22" r={r} stroke={dark ? 'rgba(118,118,128,0.3)' : '#EDEDEF'} strokeWidth="4" fill="none"/>
                <circle cx="22" cy="22" r={r} stroke={color} strokeWidth="4" fill="none" strokeLinecap="round"
                  strokeDasharray={circ}
                  strokeDashoffset={circ * (1 - pct / 100)}
                  transform="rotate(-90 22 22)"/>
                <text x="22" y="22" textAnchor="middle" dominantBaseline="central"
                  fontFamily="-apple-system, system-ui" fontSize="11" fontWeight="700"
                  fill={fg1}>{pct}%</text>
              </svg>
            </div>
          );
        })}
      </div>
    </div>
  );
}

window.GoalsListScreen = GoalsListScreen;
