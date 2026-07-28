// LogContributionSheet.jsx — half-sheet modal overlaying the current screen.
// Matches AddTransactionView's structure: amount, asset picker, date, optional note.

function LogContributionSheet({ dark, onClose, onSave, goal }) {
  const cardBg = dark ? '#1C1C1E' : '#FFFFFF';
  const sheetBg = dark ? '#1C1C1E' : '#F2F2F7';
  const fg1 = dark ? '#fff' : '#1A1A1A';
  const fg2 = dark ? 'rgba(235,235,245,0.6)' : '#6E6E73';
  const sep = dark ? 'rgba(84,84,88,0.35)' : 'rgba(60,60,67,0.12)';
  const primary = '#007ACC';

  const [amount, setAmount] = React.useState('180');
  const [asset, setAsset] = React.useState('USDC');
  const [note, setNote] = React.useState('');

  return (
    <>
      <div onClick={onClose} style={{ position:'absolute', inset: 0, background:'rgba(0,0,0,0.32)', zIndex: 100 }}/>
      <div style={{
        position:'absolute', left: 0, right: 0, bottom: 0, zIndex: 101,
        background: sheetBg, borderTopLeftRadius: 20, borderTopRightRadius: 20,
        padding: '8px 0 120px',
        boxShadow: '0 -12px 32px rgba(0,0,0,0.18)',
        maxHeight: '85%', overflow: 'auto',
      }}>
        {/* grabber */}
        <div style={{ display:'flex', justifyContent:'center', padding:'6px 0 10px' }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: dark ? 'rgba(118,118,128,0.4)' : 'rgba(60,60,67,0.3)' }}/>
        </div>

        <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', padding:'0 16px 14px' }}>
          <button onClick={onClose} style={{ background:'none', border:'none', color: primary, fontSize: 17, cursor:'pointer' }}>Cancel</button>
          <div style={{ color: fg1, fontSize: 17, fontWeight: 600 }}>Log contribution</div>
          <button onClick={() => onSave({ amount: +amount, asset, note })} style={{ background:'none', border:'none', color: primary, fontSize: 17, fontWeight: 600, cursor:'pointer' }}>Save</button>
        </div>

        {/* goal context */}
        <div style={{ padding:'12px 16px', display:'flex', alignItems:'center', gap: 10, margin:'0 16px 12px', borderRadius: 12, background: cardBg }}>
          <div style={{ fontSize: 22 }}>{goal?.emoji || '🏖️'}</div>
          <div style={{ color: fg2, fontSize: 13 }}>Contributing to</div>
          <div style={{ color: fg1, fontSize: 15, fontWeight: 600 }}>{goal?.name || 'Trip · Portugal'}</div>
        </div>

        {/* amount hero */}
        <div style={{ textAlign:'center', padding: '24px 16px 8px' }}>
          <div style={{ color: fg2, fontSize: 13, textTransform:'uppercase', letterSpacing: 0.6, fontWeight: 600 }}>Amount ({asset})</div>
          <div style={{ color: fg1, fontSize: 48, fontWeight: 700, letterSpacing: -1, fontVariantNumeric:'tabular-nums', marginTop: 6 }}>
            ${amount || '0'}
          </div>
        </div>

        {/* form */}
        <div style={{ margin: '0 16px', background: cardBg, borderRadius: 12, overflow:'hidden' }}>
          <div style={{ display:'flex', alignItems:'center', padding:'12px 16px', gap: 10 }}>
            <div style={{ color: fg1, fontSize: 17 }}>Amount</div>
            <input value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g,''))}
              style={{ flex: 1, background:'transparent', border:'none', textAlign:'right', color: fg1, fontSize: 17, outline:'none', fontVariantNumeric:'tabular-nums' }}/>
          </div>
          <div style={{ height: 0.5, background: sep, marginLeft: 16 }}/>
          <div style={{ display:'flex', alignItems:'center', padding:'12px 16px', gap: 10 }}>
            <div style={{ color: fg1, fontSize: 17, flex: 1 }}>Asset</div>
            <div style={{ display:'flex', gap: 6 }}>
              {['USDC','BTC','ETH','SOL'].map(a => (
                <button key={a} onClick={() => setAsset(a)} style={{
                  padding:'6px 10px', borderRadius: 8, border:'none', cursor:'pointer',
                  background: asset === a ? primary : (dark ? 'rgba(118,118,128,0.24)' : '#EDEDEF'),
                  color: asset === a ? '#fff' : fg1,
                  fontSize: 13, fontWeight: 600,
                }}>{a}</button>
              ))}
            </div>
          </div>
          <div style={{ height: 0.5, background: sep, marginLeft: 16 }}/>
          <div style={{ display:'flex', alignItems:'center', padding:'12px 16px' }}>
            <div style={{ color: fg1, fontSize: 17, flex: 1 }}>Date</div>
            <div style={{ color: primary, fontSize: 17 }}>Apr 18, 2026</div>
          </div>
          <div style={{ height: 0.5, background: sep, marginLeft: 16 }}/>
          <div style={{ display:'flex', alignItems:'center', padding:'12px 16px' }}>
            <div style={{ color: fg1, fontSize: 17, flex: 1 }}>Note</div>
            <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="Optional"
              style={{ flex: 2, background:'transparent', border:'none', textAlign:'right', color: fg1, fontSize: 17, outline:'none' }}/>
          </div>
        </div>

        <div style={{ padding:'12px 16px', color: fg2, fontSize: 12, fontVariantNumeric:'tabular-nums' }}>
          You're on track to reach your goal by Nov 12, 2026.
        </div>
      </div>
    </>
  );
}

window.LogContributionSheet = LogContributionSheet;
