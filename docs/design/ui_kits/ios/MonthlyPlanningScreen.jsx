// MonthlyPlanningScreen.jsx — recreates Views/Planning/MonthlyPlanningContainer + CompactGoalRequirementRow
// Shows: month selector, total required, stale-draft banner (optional), goal rows, commit dock

function MonthlyPlanningScreen({ dark, onCommit }) {
  const bg = dark ? '#000' : '#F2F2F7';
  const cardBg = dark ? '#1C1C1E' : '#FFFFFF';
  const fg1 = dark ? '#fff' : '#1A1A1A';
  const fg2 = dark ? 'rgba(235,235,245,0.6)' : '#6E6E73';
  const sep = dark ? 'rgba(84,84,88,0.35)' : 'rgba(60,60,67,0.12)';
  const primary = '#007ACC';
  const warning = '#B84D00';

  const [edits, setEdits] = React.useState({});

  const goals = [
    { id: 1, emoji: '🏖️', name: 'Trip · Portugal', required: 180, suggested: 180 },
    { id: 2, emoji: '🏠', name: 'House deposit', required: 420, suggested: 520 },
    { id: 3, emoji: '🚗', name: 'Car replacement', required: 260, suggested: 260 },
    { id: 4, emoji: '🎓', name: 'Masters programme', required: 140, suggested: 100 },
  ];

  const amountFor = (g) => edits[g.id] !== undefined ? edits[g.id] : g.suggested;
  const total = goals.reduce((s, g) => s + amountFor(g), 0);
  const income = 4200;
  const pctIncome = Math.round((total / income) * 100);

  return (
    <div style={{ background: bg, minHeight:'100%', paddingBottom: 180 }}>
      {/* month selector */}
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', padding:'0 16px 12px' }}>
        <button style={{ background:'none', border:'none', color: primary, fontSize: 17, cursor:'pointer' }}>‹</button>
        <div style={{ color: fg1, fontSize: 17, fontWeight: 600 }}>April 2026</div>
        <button style={{ background:'none', border:'none', color: primary, fontSize: 17, cursor:'pointer' }}>›</button>
      </div>

      {/* stale banner */}
      <div style={{
        margin: '0 16px 12px', borderRadius: 12,
        background: warning + '1A', color: warning,
        padding: '10px 14px', display:'flex', gap: 10, alignItems:'flex-start',
      }}>
        <div style={{ fontWeight: 700, marginTop: -1 }}>⚠</div>
        <div>
          <div style={{ fontSize: 15, fontWeight: 600 }}>Goals changed, review this plan</div>
          <div style={{ fontSize: 13, opacity: 0.88, marginTop: 2 }}>Your deadlines were updated on Apr 14. Suggested amounts are recomputed.</div>
        </div>
      </div>

      {/* summary card */}
      <div style={{
        margin: '0 16px 16px', background: cardBg, borderRadius: 16, padding: '16px 18px',
        boxShadow: dark ? 'none' : '0 1px 2px rgba(0,0,0,0.05)',
      }}>
        <div style={{ color: fg2, fontSize: 12, fontWeight: 600, textTransform:'uppercase', letterSpacing: 0.6 }}>Monthly plan total</div>
        <div style={{ color: fg1, fontSize: 34, fontWeight: 700, letterSpacing: -0.6, fontVariantNumeric:'tabular-nums', marginTop: 2 }}>${total.toLocaleString()}</div>
        <div style={{ color: fg2, fontSize: 13, marginTop: 2, fontVariantNumeric:'tabular-nums' }}>
          {pctIncome}% of $4,200 income · {pctIncome > 30 ? <span style={{ color: warning, fontWeight: 600 }}>above 30% guideline</span> : <span style={{ color: '#00875A', fontWeight: 600 }}>within guideline</span>}
        </div>
        <div style={{ height: 6, borderRadius: 3, background: dark ? 'rgba(118,118,128,0.24)' : '#EDEDEF', overflow:'hidden', marginTop: 10 }}>
          <div style={{ width: `${Math.min(100, pctIncome)}%`, height: '100%', background: pctIncome > 30 ? warning : primary, borderRadius: 3 }}/>
        </div>
      </div>

      {/* section */}
      <div style={{ color: fg2, fontSize: 13, padding: '0 32px 6px', textTransform:'uppercase', letterSpacing: -0.08 }}>Required this month</div>

      <div style={{ margin: '0 16px', background: cardBg, borderRadius: 16, overflow:'hidden' }}>
        {goals.map((g, i) => {
          const amt = amountFor(g);
          const diff = amt - g.required;
          return (
            <div key={g.id} style={{ padding: '12px 16px', borderTop: i ? `0.5px solid ${sep}` : 'none' }}>
              <div style={{ display:'flex', alignItems:'center', gap: 12 }}>
                <div style={{ width: 36, height: 36, borderRadius: 8, background: dark ? 'rgba(118,118,128,0.24)' : '#F2F2F7', display:'flex', alignItems:'center', justifyContent:'center', fontSize: 20 }}>{g.emoji}</div>
                <div style={{ flex: 1 }}>
                  <div style={{ color: fg1, fontSize: 17, fontWeight: 500, letterSpacing: -0.43 }}>{g.name}</div>
                  <div style={{ color: fg2, fontSize: 12, fontVariantNumeric:'tabular-nums' }}>Required ${g.required} · Suggested ${g.suggested}</div>
                </div>
                <div style={{ color: fg1, fontSize: 17, fontVariantNumeric:'tabular-nums', fontWeight: 600 }}>${amt}</div>
              </div>
              {/* flex slider */}
              <div style={{ marginTop: 10, display:'flex', alignItems:'center', gap: 10 }}>
                <button
                  onClick={() => setEdits({ ...edits, [g.id]: Math.max(0, amt - 20) })}
                  style={{ width: 30, height: 30, borderRadius: 8, border:'none', background: dark ? 'rgba(118,118,128,0.24)' : '#F2F2F7', color: fg1, fontSize: 20, cursor:'pointer' }}>−</button>
                <input type="range" min="0" max="1000" step="10" value={amt}
                  onChange={(e) => setEdits({ ...edits, [g.id]: +e.target.value })}
                  style={{ flex: 1, accentColor: primary }}/>
                <button
                  onClick={() => setEdits({ ...edits, [g.id]: amt + 20 })}
                  style={{ width: 30, height: 30, borderRadius: 8, border:'none', background: dark ? 'rgba(118,118,128,0.24)' : '#F2F2F7', color: fg1, fontSize: 18, cursor:'pointer' }}>+</button>
                {diff !== 0 && (
                  <div style={{
                    fontSize: 11, fontWeight: 600, padding: '2px 8px', borderRadius: 999,
                    background: diff > 0 ? '#00875A1A' : warning + '1A',
                    color: diff > 0 ? '#00875A' : warning,
                    fontVariantNumeric:'tabular-nums',
                  }}>{diff > 0 ? '+' : ''}${diff}</div>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* commit dock — sticky at bottom of this scroll content */}
      <div style={{ position:'sticky', bottom: 0, marginTop: 16, padding: '12px 16px 20px', background: dark ? 'rgba(0,0,0,0.85)' : 'rgba(242,242,247,0.85)', backdropFilter:'blur(16px)', WebkitBackdropFilter:'blur(16px)', borderTop: `0.5px solid ${sep}` }}>
        <div style={{ display:'flex', gap: 10 }}>
          <button style={{ flex: 1, padding: '14px 16px', background: dark ? 'rgba(118,118,128,0.24)' : '#E5E5EA', color: fg1, border:'none', borderRadius: 12, fontSize: 16, fontWeight: 600, cursor:'pointer', minHeight: 44 }}>Save draft</button>
          <button onClick={onCommit} style={{ flex: 2, padding: '14px 16px', background: primary, color: '#fff', border:'none', borderRadius: 12, fontSize: 16, fontWeight: 600, cursor:'pointer', minHeight: 44 }}>Commit plan · ${total.toLocaleString()}</button>
        </div>
        <div style={{ color: fg2, fontSize: 12, textAlign:'center', marginTop: 6 }}>Commit locks this month's targets. You can still log contributions later.</div>
      </div>
    </div>
  );
}

window.MonthlyPlanningScreen = MonthlyPlanningScreen;
