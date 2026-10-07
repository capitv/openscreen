import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { _electron as electron, expect } from "@playwright/test";

assert.equal(process.platform, "win32", "Verify the actual Windows package on Windows");
const packageDir = path.resolve("release/iriun-experimental/win-unpacked");
const executable = path.join(packageDir, "OpenScreen Iriun Experimental.exe");
const nativeDir = path.join(packageDir, "resources/electron/native/bin/win32-x64");
const sourceDir = path.resolve("electron/native/bin/win32-x64");
for (const name of fs
	.readdirSync(sourceDir)
	.filter((name) => /\.(exe|dll|node)$/i.test(name) && name !== "ffmpeg.exe")) {
	assert.deepEqual(
		createHash("sha256")
			.update(fs.readFileSync(path.join(nativeDir, name)))
			.digest("hex"),
		createHash("sha256")
			.update(fs.readFileSync(path.join(sourceDir, name)))
			.digest("hex"),
		`Package must ship the freshly built ${name}`,
	);
}
const minimalEnv = {
	...process.env,
	PATH: [path.join(process.env.SystemRoot, "System32"), process.env.SystemRoot].join(";"),
};
const stt = spawnSync(
	path.join(nativeDir, "whisper-stt-server.exe"),
	["--model", "__staging_load_check__"],
	{
		cwd: nativeDir,
		env: minimalEnv,
		encoding: "utf8",
		timeout: 60000,
	},
);
assert.ifError(stt.error);
assert.equal(stt.status, 3, stt.stdout + stt.stderr); // Documented missing-model exit, not a loader crash.
assert.match(
	stt.stdout + stt.stderr,
	/\[whisper-stt\] boot:/,
	"Packaged STT must reach main with only bundled and OS DLLs",
);
console.log(
	"PASS: packaged Whisper STT loaded with a minimal PATH (invalid model deliberately supplied)",
);
const addon = spawnSync(
	executable,
	[
		"-e",
		`const addon = require(${JSON.stringify(path.join(nativeDir, "compositor_view.node"))}); if (typeof addon.probeBackend !== 'function') throw Error('Missing compositor API'); console.log('COMPOSITOR_LOADED', addon.probeBackend());`,
	],
	{
		cwd: nativeDir,
		env: { ...minimalEnv, ELECTRON_RUN_AS_NODE: "1" },
		encoding: "utf8",
		timeout: 60000,
	},
);
assert.ifError(addon.error);
assert.equal(addon.status, 0, addon.stdout + addon.stderr);
assert.match(addon.stdout, /COMPOSITOR_LOADED/);
console.log(addon.stdout.trim());

const userData = fs.mkdtempSync(path.join(os.tmpdir(), "openscreen-iriun-smoke-"));
const appEnv = { ...process.env, HEADLESS: "true", LANG: "en_US.UTF-8" };
delete appEnv.ELECTRON_RUN_AS_NODE;
delete appEnv.VITE_DEV_SERVER_URL;
const app = await electron.launch({
	executablePath: executable,
	args: ["--no-sandbox", "--lang=en-US", `--user-data-dir=${userData}`],
	env: appEnv,
	timeout: 60000,
});
app.process().stdout?.on("data", (chunk) => process.stdout.write(chunk));
app.process().stderr?.on("data", (chunk) => process.stderr.write(chunk));
try {
	const identity = await app.evaluate(({ app }) => ({
		name: app.getName(),
		userData: app.getPath("userData"),
		packaged: app.isPackaged,
	}));
	assert.equal(identity.packaged, true);
	assert.equal(identity.name, "OpenScreen Iriun Experimental");
	assert.equal(path.resolve(identity.userData), path.resolve(userData));
	const hud = await app.firstWindow();
	await expect(hud.getByTestId("launch-open-studio-button")).toBeVisible({ timeout: 60000 });
	const nextWindow = app.waitForEvent("window", {
		predicate: (page) => page.url().includes("windowType=editor"),
		timeout: 30000,
	});
	await hud.getByTestId("launch-open-studio-button").click();
	const editor = await nextWindow;
	await expect(editor.getByRole("toolbar", { name: "Timeline tools" })).toBeVisible({
		timeout: 60000,
	});
	await expect(editor.getByTestId("preview")).toContainText("Start with a recording");
	console.log("PASS: packaged Electron opened Studio with isolated user data");
} finally {
	await app.close();
	fs.rmSync(userData, { recursive: true, force: true });
}
console.log("Iriun hardware/driver capture was NOT tested by this packaging smoke check.");
