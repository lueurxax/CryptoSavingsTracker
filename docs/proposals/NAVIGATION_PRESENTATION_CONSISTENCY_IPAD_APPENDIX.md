# Navigation Presentation Consistency: iPad Appendix

This appendix operationalizes Section 12.1 defaults from:
`docs/proposals/NAVIGATION_PRESENTATION_CONSISTENCY_PROPOSAL.md`.

## iPad Minimum Defaults (`MOD-01...MOD-05`)

| Decision ID | iPad Default Container | Dismiss Rule | Notes |
|---|---|---|---|
| MOD-01 | Popover preferred, fallback `.sheet` for larger content | Tap outside allowed only when form is clean | Keep initiating context visible where possible |
| MOD-02 | `.sheet` with large-form presentation | Dirty state blocks dismiss and triggers explicit confirmation | Keyboard and primary CTA must remain visible |
| MOD-03 | `.fullScreenCover` only for true multi-step commit flow | Explicit cancel/confirm required | Preserve progress and confirmation context |
| MOD-04 | `confirmationDialog` anchored to invoking control | Cancel always visible | Destructive action visually isolated |
| MOD-05 | In-flow blocking panel or `.sheet` based on severity | No silent dismiss while blocking validation is unresolved | Recovery action must be explicit and testable |

## Compact-Width Guardrails on iPad Split View

For split-view and compact-width iPad contexts:

1. Keep one pinned primary action visible in toolbar/footer at all times.
2. Move tertiary controls to overflow menu.
3. Keep dismiss intent explicit (`Cancel`, `Done`, or destructive label).
4. Avoid dynamic numeric payload in title for `MOD-02`; place values in body.

## Verification Notes

Required evidence for iPad-ready sign-off:

1. One screenshot per `MOD-01...MOD-05` in regular width.
2. One screenshot per `MOD-02` and `MOD-03` in compact split-view.
3. VoiceOver focus order confirmation for toolbar primary action.
