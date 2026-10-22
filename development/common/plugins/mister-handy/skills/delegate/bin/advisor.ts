import { spawn } from "node:child_process";
import { appendFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Type } from "@earendil-works/pi-ai";
import { convertToLlm, defineTool, serializeConversation, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SYSTEM_PROMPT =
	"You are the advisor for a cheaper coding agent working on the task below. It cannot see you except through this reply. " +
	"Give concrete, prioritised advice: what to do next, what is wrong, what to verify. " +
	"No code blocks longer than a few lines; it writes the code.";
const MAX_CHARS = 150_000;
const HEAD_CHARS = 20_000;
const TIMEOUT_MS = 5 * 60 * 1000;

function clip(text: string): string {
	if (text.length <= MAX_CHARS) return text;
	const tail = MAX_CHARS - HEAD_CHARS;
	return `${text.slice(0, HEAD_CHARS)}\n\n[... middle of the conversation omitted ...]\n\n${text.slice(-tail)}`;
}

function askClaude(model: string, transcript: string): Promise<{ advice: string; cost: number }> {
	return new Promise((resolve, reject) => {
		const env = { ...process.env };
		for (const k of ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "TYPESAFE_API_KEY"]) delete env[k];
		const child = spawn(
			"claude",
			["-p", "--model", model, "--output-format", "json", "--tools", "", "--no-session-persistence", "--strict-mcp-config", "--disable-slash-commands", "--system-prompt", SYSTEM_PROMPT],
			{ cwd: mkdtempSync(join(tmpdir(), "advisor-")), env, stdio: ["pipe", "pipe", "pipe"] },
		);
		let out = "";
		let err = "";
		const timer = setTimeout(() => {
			child.kill("SIGKILL");
			reject(new Error(`advisor timed out after ${TIMEOUT_MS / 1000}s`));
		}, TIMEOUT_MS);
		child.stdout.on("data", (d) => (out += d));
		child.stderr.on("data", (d) => (err += d));
		child.on("error", (e) => {
			clearTimeout(timer);
			reject(new Error(`advisor could not start claude: ${e.message}`));
		});
		child.on("close", (code) => {
			clearTimeout(timer);
			if (code !== 0) return reject(new Error(`advisor: claude exited ${code}: ${err.trim().slice(0, 300)}`));
			try {
				const j = JSON.parse(out);
				if (j.is_error || typeof j.result !== "string" || !j.result.trim()) throw new Error("empty or error result");
				resolve({ advice: j.result, cost: Number(j.total_cost_usd) || 0 });
			} catch (e) {
				reject(new Error(`advisor: unusable claude output (${(e as Error).message})`));
			}
		});
		child.stdin.on("error", () => {});
		child.stdin.end(transcript);
	});
}

export default function (pi: ExtensionAPI) {
	let calls = 0;
	pi.registerTool(
		defineTool({
			name: "advisor",
			label: "Advisor",
			description:
				"Consult a stronger reviewer model that sees your whole conversation so far. Takes no parameters. Call it before substantive work (after orienting), when stuck, and when you believe the task is done (after making the result durable).",
			parameters: Type.Object({}),
			async execute(_id, _params, _signal, _onUpdate, ctx) {
				const max = Number(process.env.MISTER_HANDY_ADVISOR_MAX) || 4;
				if (calls >= max) {
					return { content: [{ type: "text", text: "advisor budget used up; continue on your own" }], details: { calls, max } };
				}
				calls++;
				const started = Date.now();
				const messages = ctx.sessionManager
					.getBranch()
					.flatMap((e) => (e.type === "message" ? [e.message] : []));
				const transcript = clip(serializeConversation(convertToLlm(messages)));
				const { advice, cost } = await askClaude(process.env.MISTER_HANDY_ADVISOR || "opus", transcript);
				const secs = Math.round((Date.now() - started) / 1000);
				const log = process.env.MISTER_HANDY_ADVISOR_LOG;
				if (log) {
					const d = new Date();
					const hm = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
					try {
						appendFileSync(log, `${hm} advisor call ${calls}/${max} $${cost.toFixed(4)} ${secs}s\n`);
					} catch {}
				}
				return { content: [{ type: "text", text: advice }], details: { calls, max, cost, secs } };
			},
		}),
	);
}
