// GoalDashboardScreen.jsx — recreates Views/Dashboard/GoalDashboardScreen.swift
// Module order (fixed cross-platform):
// goal_snapshot → next_action → forecast_risk → contribution_activity → allocation_health → utilities

function GoalDashboardScreen({ dark, goal, onLogContribution }) {
  const g = goal || { emoji: '🏖️', name: 'Trip · Portugal', saved: 1980, target: 3000, deadline: 'Aug 2026', status: 'on' };

  const bg = dark ? '#000' : '#F2F2F7';
  const cardBg = dark ? '#1C1C1E' : '#FFFFFF';
  const fg1 = dark ? '#fff' : '#1A1A1A';
  const fg2 = dark ? 'rgba(235,235,245,0.6)' : '#6E6E73';
  const sep = dark ? 'rgba(84,84,88,0.35)' : 'rgba(60,60,67,0.12)';
  const primary = '#007ACC';
  const success = '#00875A';
  const warning = '#B84D00';

  const pct = Math.round((g.saved / g.target) * 100);
  const r = 56, circ = 2 * Math.PI * r;

  const sectionTitle = (text, aside) => (
    <div style={{ display:'flex', justifyContent:'space-between', alignItems:'baseline', padding: '16px 16px 8px' }}>
      <div style={{ color: fg1, fontSize: 20, fontWeight: 600, letterSpacing: -0.4 }}>{text}</div>
      {aside && <div style={{ color: primary, fontSize: 15, fontWeight: 500 }}>{aside}</div>}
    </div>
  );

  const card = (child, style = {}) => (
    <div style={{
      background: cardBg, borderRadius: 16, margin: '0 16px',
      boxShadow: dark ? 'none' : '0 1px 2px rgba(0,0,0,0.05)',
      ...style,
    }}>{child}</div>
  );

  // Fake forecast line data
  const forecastPts = [32, 30, 26, 28, 22, 18, 20, 14, 10, 12, 6];
  const pathFor = (arr) => arr.map((y, i) => `${i === 0 ? 'M' : 'L'} ${i * (260/(arr.length-1))} ${y}`).join(' ');

  // Bar data for contribution activity
  const contrib = [40, 60, 75, 55, 90, 110, 85, 120, 95, 70, 115, 140];
  const contribMax = Math.max(...contrib);

  return (
    <div style={{ background: bg, minHeight:'100%', paddingBottom: 120 }}>
      {/* === goal_snapshot === */}
      {card(
        <div style={{ padding: 20, display:'flex', gap: 16, alignItems: 'center' }}>
          <svg width="128" height="128" viewBox="0 0 128 128">
            <circle cx="64" cy="64" r={r} stroke={dark ? 'rgba(118,118,128,0.25)' : '#EDEDEF'} strokeWidth="10" fill="none"/>
            <circle cx="64" cy="64" r={r} stroke={success} strokeWidth="10" fill="none" strokeLinecap="round"
              strokeDasharray={circ} strokeDashoffset={circ * (1 - pct/100)}
              transform="rotate(-90 64 64)"/>
            <text x="64" y="58" textAnchor="middle" fill={fg1} fontFamily="-apple-system" fontSize="28" fontWeight="700" style={{ fontVariantNumeric:'tabular-nums' }}>{pct}%</text>
            <text x="64" y="78" textAnchor="middle" fill={fg2} fontFamily="-apple-system" fontSize="11" fontWeight="600" letterSpacing="0.6">COMPLETE</text>
          </svg>
          <div style={{ flex: 1 }}>
            <div style={{ display:'flex', alignItems:'center', gap: 8 }}>
              <span style={{ fontSize: 22 }}>{g.emoji}</span>
              <span style={{ color: fg1, fontSize: 17, fontWeight: 600 }}>{g.name}</span>
            </div>
            <div style={{ color: fg1, fontSize: 28, fontWeight: 700, letterSpacing: -0.5, fontVariantNumeric:'tabular-nums', marginTop: 4 }}>${g.saved.toLocaleString()}</div>
            <div style={{ color: fg2, fontSize: 13, fontVariantNumeric:'tabular-nums' }}>of ${g.target.toLocaleString()} · by {g.deadline}</div>
            <div style={{ display:'inline-flex', alignItems:'center', gap: 4, padding:'3px 10px', borderRadius: 999, background: success+'1A', color: success, fontSize: 12, fontWeight: 600, marginTop: 8 }}>
              ✓ On Track
            </div>
          </div>
        </div>
      )}

      {/* === next_action === */}
      {sectionTitle('Next action')}
      {card(
        <div style={{ padding: 16, display:'flex', gap: 12, alignItems:'center' }}>
          <div style={{ width: 40, height: 40, borderRadius: 10, background: primary + '1A', color: primary, display:'flex', alignItems:'center', justifyContent:'center', fontSize: 22, fontWeight: 600 }}>+</div>
          <div style={{ flex: 1 }}>
            <div style={{ color: fg1, fontSize: 17, fontWeight: 600, letterSpacing: -0.43 }}>Log this month's contribution</div>
            <div style={{ color: fg2, fontSize: 13 }}>Planned $180 · 12 days left this month</div>
          </div>
          <button onClick={onLogContribution} style={{
            background: primary, color: '#fff', border: 'none', borderRadius: 10,
            padding: '10px 16px', fontSize: 15, fontWeight: 600, letterSpacing: -0.24,
            fontFamily: '-apple-system, system-ui', cursor: 'pointer', minHeight: 44,
          }}>Log</button>
        </div>
      )}

      {/* === forecast_risk === */}
      {sectionTitle('Forecast', 'Details')}
      {card(
        <div style={{ padding: 16 }}>
          <div style={{ display:'flex', justifyContent:'space-between', alignItems:'baseline', marginBottom: 8 }}>
            <div>
              <div style={{ color: fg2, fontSize: 12, fontWeight: 600, textTransform:'uppercase', letterSpacing: 0.6 }}>Projected on deadline</div>
              <div style={{ color: fg1, fontSize: 22, fontWeight: 700, fontVariantNumeric:'tabular-nums', letterSpacing: -0.4, marginTop: 2 }}>$3,120</div>
            </div>
            <div style={{
              display:'inline-flex', alignItems:'center', gap:4, padding:'3px 10px',
              borderRadius: 999, background: success+'1A', color: success, fontSize: 12, fontWeight: 600,
            }}>✓ Above target</div>
          </div>
          <svg viewBox="0 0 260 50" width="100%" height="60">
            <defs>
              <linearGradient id="gf" x1="0" x2="0" y1="0" y2="1">
                <stop offset="0" stopColor={primary} stopOpacity="0.2"/>
                <stop offset="1" stopColor={primary} stopOpacity="0"/>
              </linearGradient>
            </defs>
            <path d={`${pathFor(forecastPts)} L 260 50 L 0 50 Z`} fill="url(#gf)"/>
            <path d={pathFor(forecastPts)} fill="none" stroke={primary} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
            <line x1="0" y1="24" x2="260" y2="24" stroke={fg2} strokeOpacity="0.3" strokeWidth="1" strokeDasharray="3 3"/>
          </svg>
          <div style={{ display:'flex', justifyContent:'space-between', color: fg2, fontSize: 11, marginTop: 4 }}>
            <span>now</span><span>3m</span><span>6m</span><span>Aug 2026</span>
          </div>
        </div>
      )}

      {/* === contribution_activity === */}
      {sectionTitle('Contributions', 'All time')}
      {card(
        <div style={{ padding: 16 }}>
          <div style={{ color: fg2, fontSize: 12, fontWeight: 600, textTransform:'uppercase', letterSpacing: 0.6 }}>Last 12 months</div>
          <div style={{ color: fg1, fontSize: 22, fontWeight: 700, letterSpacing: -0.4, fontVariantNumeric:'tabular-nums', marginTop: 2 }}>$1,055</div>
          <div style={{ display:'flex', gap: 6, alignItems:'flex-end', height: 72, marginTop: 10 }}>
            {contrib.map((v, i) => (
              <div key={i} style={{ flex: 1, height: `${(v / contribMax) * 100}%`, background: i === contrib.length - 1 ? primary : primary + '66', borderRadius: 3 }}/>
            ))}
          </div>
          <div style={{ display:'flex', justifyContent:'space-between', color: fg2, fontSize: 11, marginTop: 6, fontVariantNumeric:'tabular-nums' }}>
            <span>May</span><span>Jul</span><span>Sep</span><span>Nov</span><span>Jan</span><span>Mar</span><span>Apr</span>
          </div>
        </div>
      )}

      {/* === allocation_health === */}
      {sectionTitle('Allocation')}
      {card(
        <div style={{ padding: 16 }}>
          {[
            { label: 'BTC', pct: 52, color: '#0066CC' },
            { label: 'ETH', pct: 28, color: '#00875A' },
            { label: 'USDC', pct: 14, color: '#B84D00' },
            { label: 'SOL',  pct: 6,  color: '#7B2CBF' },
          ].map((a, i) => (
            <div key={a.label} style={{ display:'flex', alignItems:'center', gap:12, padding:'10px 0', borderTop: i ? `0.5px solid ${sep}` : 'none' }}>
              <div style={{ width: 10, height: 10, borderRadius: 3, background: a.color }}/>
              <div style={{ flex: 1, color: fg1, fontSize: 15, fontWeight: 500 }}>{a.label}</div>
              <div style={{ width: 120, height: 4, borderRadius: 2, background: dark ? 'rgba(118,118,128,0.24)' : '#EDEDEF', overflow:'hidden' }}>
                <div style={{ width: `${a.pct}%`, height: '100%', background: a.color }}/>
              </div>
              <div style={{ color: fg1, fontSize: 13, fontVariantNumeric:'tabular-nums', fontWeight: 600, width: 40, textAlign: 'right' }}>{a.pct}%</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

window.GoalDashboardScreen = GoalDashboardScreen;
