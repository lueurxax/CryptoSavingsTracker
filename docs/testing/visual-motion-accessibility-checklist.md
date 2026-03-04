# Visual Motion + Accessibility Checklist

## Scope

Release-blocking flows:

1. Monthly Planning core flow
2. Dashboard core flow
3. Settings critical rows

## Required Scenarios

For each flow and platform (`iOS`, `Android`) run:

1. Default motion mode with screen reader off:
   - press feedback animation stays within 100-150ms.
   - loading -> recovery transition stays within 150-250ms.
2. Reduced Motion enabled with screen reader off:
   - transitions snap without decorative interpolation.
3. Reduced Motion enabled with screen reader on (`VoiceOver` / `TalkBack`):
   - state change announcements still fire.
   - focus order remains stable through loading/error/recovery transitions.
4. Error and warning states:
   - semantics are communicated by text/icon plus color (no color-only signaling).

## Evidence Format

For each scenario attach:

1. Screen recording or screenshot pair
2. Platform + OS version
3. Pass/fail note
4. Linked issue for each failure

Store evidence in:

- `docs/release/visual-system/<wave>/accessibility-motion-report.md`
- `docs/release/visual-system/<wave>/runtime-accessibility-assertions.json` (machine-readable gate input)
