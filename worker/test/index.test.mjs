// Run in worker/: node --test
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import worker, { validateFingerprint, fingerprintId } from "../src/index.js";

const FINGERPRINT = readFileSync(
  new URL("../../fingerprints/75a1aa13335d57eb.txt", import.meta.url),
  "utf8",
);
const ID = "75a1aa13335d57eb";
const POOL = "/repos/net-aigis/netaigis-dsm-modules";
const REPORTED = "/repos/net-aigis/netaigis-dsm-fingerprints";
const ENV = {
  POOL_REPO: "net-aigis/netaigis-dsm-modules",
  FINGERPRINT_REPO: "net-aigis/netaigis-dsm-fingerprints",
  GITHUB_TOKEN: "t",
};

// Simulated GitHub API: set of existing paths (with repository prefix),
// records requests.
function mockGitHub(existing) {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    const path = new URL(url).pathname;
    const method = init.method || "GET";
    calls.push({ method, path, body: init.body });
    if (method === "PUT") {
      if (existing.has(path)) return new Response("", { status: 422 });
      existing.add(path);
      return new Response("{}", { status: 201 });
    }
    return new Response("{}", { status: existing.has(path) ? 200 : 404 });
  };
  return calls;
}

function report(body, method = "POST") {
  return worker.fetch(
    new Request("https://w.example/v1/fingerprint", { method, body }),
    ENV,
  );
}

test("id matches scripts/fingerprint.sh", async () => {
  assert.equal(await fingerprintId(FINGERPRINT), ID);
});

test("valid fingerprint passes", () => {
  assert.equal(validateFingerprint(FINGERPRINT), null);
});

test("invalid fingerprints are rejected", () => {
  assert.match(validateFingerprint(FINGERPRINT.trimEnd()), /final newline/);
  assert.match(validateFingerprint(FINGERPRINT + "x=1\n"), /expected 9 or 10 lines/);
  assert.match(validateFingerprint(FINGERPRINT.replace("platform=", "model=")), /platform=/);
  assert.match(validateFingerprint(FINGERPRINT.replace("arch=x86_64", "arch=mips")), /arch/);
  assert.match(validateFingerprint(FINGERPRINT.replace("modules=ip_set_hash_net", "modules=evil")),
    /unknown module evil/);
  assert.match(validateFingerprint(FINGERPRINT.replace("dsm_build=86009", "dsm_build=86009;rm")), /dsm_build/);
});

// Productive DS2422+ loader fingerprint (no dsm_smallfix) — was HTTP 400.
const FP_ABI = [
  "netaigis-kmod-fingerprint=1",
  "arch=x86_64",
  "platform=v1000",
  "dsm_version=7.3",
  "dsm_build=86009",
  "kernel_release=4.4.302+",
  "kernel_version=#86009 SMP Wed Nov 26 18:19:20 CST 2025",
  "vermagic=4.4.302+ SMP mod_unload",
  "modules=ip_set_hash_net xt_u32 falco",
  "",
].join("\n");

test("ABI fingerprint without dsm_smallfix and with xt_u32 passes", () => {
  assert.equal(validateFingerprint(FP_ABI), null);
});

test("legacy fingerprint with dsm_smallfix and xt_u32 still passes", () => {
  const legacy = readFileSync(
    new URL("../../fingerprints/00793922c2599ac1.txt", import.meta.url),
    "utf8",
  );
  assert.equal(validateFingerprint(legacy), null);
});

test("POST ABI fingerprint queues instead of 400", async () => {
  const calls = mockGitHub(new Set());
  const res = await report(FP_ABI);
  assert.equal(res.status, 202);
  const body = await res.json();
  assert.equal(body.status, "queued");
  assert.equal(body.id, await fingerprintId(FP_ABI));
  assert.equal(body.id, "dbf1b5e24dd81a0c");
  assert.ok(calls.some((c) => c.method === "PUT"));
});
test("new fingerprint is committed and queued", async () => {
  const calls = mockGitHub(new Set());
  const res = await report(FINGERPRINT);
  assert.equal(res.status, 202);
  assert.deepEqual(await res.json(), { id: ID, status: "queued" });

  const put = calls.find((c) => c.method === "PUT");
  assert.equal(put.path, `${REPORTED}/contents/fingerprints/${ID}.txt`);
  assert.ok(calls.some((c) => c.path === `${POOL}/releases/tags/fp-${ID}`));
  assert.ok(!calls.some((c) => c.method !== "GET" && c.path.startsWith(POOL)));
  const body = JSON.parse(put.body);
  assert.equal(atob(body.content), FINGERPRINT);
  assert.equal(body.branch, "main");
});

test("known fingerprint is not committed again", async () => {
  const calls = mockGitHub(new Set([`${REPORTED}/contents/fingerprints/${ID}.txt`]));
  const res = await report(FINGERPRINT);
  assert.equal(res.status, 202);
  assert.ok(!calls.some((c) => c.method === "PUT"));
});

test("published fingerprint", async () => {
  const calls = mockGitHub(new Set([`${POOL}/releases/tags/fp-${ID}`]));
  const res = await report(FINGERPRINT);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { id: ID, status: "published" });
  assert.equal(calls.length, 1);
});

test("invalid fingerprint never reaches GitHub", async () => {
  const calls = mockGitHub(new Set());
  const res = await report("arch=x86_64\n");
  assert.equal(res.status, 400);
  assert.equal(calls.length, 0);
});

test("oversized body, wrong method and path", async () => {
  mockGitHub(new Set());
  assert.equal((await report("x".repeat(5000))).status, 413);
  assert.equal((await report(undefined, "GET")).status, 405);
  const other = await worker.fetch(new Request("https://w.example/"), ENV);
  assert.equal(other.status, 404);
});

test("rate limit", async () => {
  const calls = mockGitHub(new Set());
  const env = { ...ENV, REPORT_LIMITER: { limit: async () => ({ success: false }) } };
  const res = await worker.fetch(
    new Request("https://w.example/v1/fingerprint", { method: "POST", body: FINGERPRINT }),
    env,
  );
  assert.equal(res.status, 429);
  assert.equal(calls.length, 0);
});
