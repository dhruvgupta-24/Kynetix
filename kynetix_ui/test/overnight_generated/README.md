# Kynetix Overnight Generated Tests Directory

This directory is designated exclusively for autonomous overnight regression test generation.

## Rules of Engagement:
1. **Never Overwrite**: Never overwrite or delete existing tests in `test/`.
2. **Deterministic Setup**: Every test placed here must run hermetically with mock initial values (`SharedPreferences.setMockInitialValues({})`) and mock Supabase.
3. **Traceability**: Every test must specify:
   - `Finding ID` (e.g. `BUG-001`)
   - Description of the defect being reproduced
   - Assertions verifying the expected behavior rather than codifying a workaround.
