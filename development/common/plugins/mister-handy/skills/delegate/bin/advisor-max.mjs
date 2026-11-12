// advisorMax: how many advisor calls a pi worker gets, from MISTER_HANDY_ADVISOR_MAX.
// Only unset, empty or invalid means the default of 4. 0 (or "0") is a real budget: no calls.
// Kept in plain ESM so the test suite can check it without loading pi.
export const ADVISOR_DEFAULT_MAX = 4;

export function advisorMax(value) {
	if (value === undefined || value === null) return ADVISOR_DEFAULT_MAX;
	const text = String(value).trim();
	if (text === "") return ADVISOR_DEFAULT_MAX;
	const n = Number(text);
	return Number.isFinite(n) && n >= 0 ? n : ADVISOR_DEFAULT_MAX;
}
