// Receives device fingerprints for which the module pool (POOL_REPO) has no
// release yet and adds them as fingerprints/<id>.txt to FINGERPRINT_REPO.
// The Module pool workflow reads that repository as data, then builds,
// signs and publishes fp-<id>.
//
// Devices send nothing but the fingerprint, without login or token. The
// GitHub token stays in this worker (secret GITHUB_TOKEN) and can only
// write to FINGERPRINT_REPO, never to the build scripts.
//
// POST /v1/fingerprint   body: the fingerprint file (text/plain)
//   200 {"id", "status": "published"}  release fp-<id> exists
//   202 {"id", "status": "queued"}     fingerprint known, build pending
//   400 / 405 / 413 / 429 / 502        {"error"}

// Same keys, order and patterns as scripts/fingerprint.sh.
const FINGERPRINT_FIELDS = [
  ["netaigis-kmod-fingerprint", /^1$/],
  ["arch", /^(x86_64|aarch64)$/],
  ["platform", /^[a-z0-9]{1,32}$/],
  ["dsm_version", /^[0-9]{1,2}\.[0-9]{1,2}$/],
  ["dsm_build", /^[0-9]{1,6}$/],
  ["dsm_smallfix", /^[0-9]{1,3}$/],
  ["kernel_release", /^[0-9][0-9a-z.+_-]{0,63}$/],
  ["kernel_version", /^#[0-9A-Za-z :+._-]{1,127}$/],
  ["vermagic", /^[0-9A-Za-z .+_-]{1,127}$/],
  ["modules", /^[a-z0-9_]{1,32}( [a-z0-9_]{1,32}){0,15}$/],
];

// Modules listed in modules.conf; nothing else can be built.
const KNOWN_MODULES = new Set([
  "nfnetlink", "ip_set", "ip_set_hash_ip", "ip_set_hash_net", "x_tables", "xt_set",
]);

const MAX_BODY = 2048;

export function validateFingerprint(text) {
  if (!text.endsWith("\n")) return "missing final newline";

  const lines = text.slice(0, -1).split("\n");
  if (lines.length !== FINGERPRINT_FIELDS.length) {
    return `expected ${FINGERPRINT_FIELDS.length} lines`;
  }

  for (const [i, [key, pattern]] of FINGERPRINT_FIELDS.entries()) {
    const line = lines[i];
    const eq = line.indexOf("=");
    if (eq < 0 || line.slice(0, eq) !== key) return `line ${i + 1} must be ${key}=`;
    if (!pattern.test(line.slice(eq + 1))) return `invalid value for ${key}`;
  }

  const modules = lines[FINGERPRINT_FIELDS.length - 1].slice("modules=".length).split(" ");
  const unknown = modules.find((m) => !KNOWN_MODULES.has(m));
  if (unknown) return `unknown module ${unknown}`;
  if (new Set(modules).size !== modules.length) return "duplicate module";

  return null;
}

export async function fingerprintId(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16);
}

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function github(env, repo, path, init = {}) {
  return fetch(`https://api.github.com/repos/${repo}${path}`, {
    ...init,
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      "user-agent": "netaigis-kmod-report",
      "x-github-api-version": "2022-11-28",
      ...init.headers,
    },
  });
}

async function readBody(request) {
  const length = Number(request.headers.get("content-length") || 0);
  if (length > MAX_BODY) return null;
  const text = await request.text();
  return text.length > MAX_BODY ? null : text;
}

export async function handleReport(request, env) {
  if (request.method !== "POST") return json(405, { error: "POST only" });

  if (env.REPORT_LIMITER) {
    const key = request.headers.get("cf-connecting-ip") || "unknown";
    const { success } = await env.REPORT_LIMITER.limit({ key });
    if (!success) return json(429, { error: "too many requests" });
  }

  const text = await readBody(request);
  if (text === null) return json(413, { error: "fingerprint too large" });

  const problem = validateFingerprint(text);
  if (problem) return json(400, { error: `invalid fingerprint: ${problem}` });

  const id = await fingerprintId(text);
  const branch = env.GITHUB_BRANCH || "main";
  const file = `/contents/fingerprints/${id}.txt`;

  const release = await github(env, env.POOL_REPO, `/releases/tags/fp-${id}`);
  if (release.ok) return json(200, { id, status: "published" });
  if (release.status !== 404) return json(502, { error: `GitHub: ${release.status}` });

  const existing = await github(env, env.FINGERPRINT_REPO, `${file}?ref=${branch}`);
  if (existing.ok) return json(202, { id, status: "queued" });
  if (existing.status !== 404) return json(502, { error: `GitHub: ${existing.status}` });

  const created = await github(env, env.FINGERPRINT_REPO, file, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      message: `Add fingerprint ${id}`,
      content: btoa(text),
      branch,
    }),
  });

  // 422: created concurrently by another report.
  if (created.ok || created.status === 422) return json(202, { id, status: "queued" });
  return json(502, { error: `GitHub: ${created.status}` });
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (pathname !== "/v1/fingerprint") return json(404, { error: "not found" });
    return handleReport(request, env);
  },
};
