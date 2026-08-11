#!/usr/bin/env node
/**
 * Parse a react-doctor --json report into GITHUB_OUTPUT + a markdown summary.
 *
 * Usage:
 *   node parse-report.mjs <report.json> <summary.md>
 *
 * Env (optional):
 *   GITHUB_OUTPUT — if set, writes action outputs
 *   GITHUB_STEP_SUMMARY — unused here; caller can cat the summary file
 *   REACT_DOCTOR_HEAD_SHA — short commit attribution in footer
 *   GITHUB_SERVER_URL / GITHUB_REPOSITORY — blob links for file paths
 */

import fs from "node:fs";
import path from "node:path";

const [reportPath, summaryPath] = process.argv.slice(2);
if (!reportPath || !summaryPath) {
  console.error("usage: parse-report.mjs <report.json> <summary.md>");
  process.exit(2);
}

const MARKER = "<!-- react-doctor:summary -->";
const BRAND = "https://react.doctor";

function readReport(file) {
  if (!fs.existsSync(file)) {
    return {
      ok: false,
      error: { message: `Report file missing: ${file}` },
      diagnostics: [],
      summary: {
        errorCount: 0,
        warningCount: 0,
        affectedFileCount: 0,
        totalDiagnosticCount: 0,
        score: null,
      },
    };
  }
  const raw = fs.readFileSync(file, "utf8").trim();
  if (!raw) {
    return {
      ok: false,
      error: { message: "Report file was empty" },
      diagnostics: [],
      summary: {
        errorCount: 0,
        warningCount: 0,
        affectedFileCount: 0,
        totalDiagnosticCount: 0,
        score: null,
      },
    };
  }
  try {
    return JSON.parse(raw);
  } catch (error) {
    return {
      ok: false,
      error: { message: `Invalid JSON report: ${error.message}` },
      diagnostics: [],
      summary: {
        errorCount: 0,
        warningCount: 0,
        affectedFileCount: 0,
        totalDiagnosticCount: 0,
        score: null,
      },
    };
  }
}

function summarize(report) {
  const diagnostics = Array.isArray(report.diagnostics) ? report.diagnostics : [];
  const fromSummary = report.summary && typeof report.summary === "object" ? report.summary : null;

  let errorCount = Number(fromSummary?.errorCount);
  let warningCount = Number(fromSummary?.warningCount);
  let affectedFileCount = Number(fromSummary?.affectedFileCount);
  let totalDiagnosticCount = Number(fromSummary?.totalDiagnosticCount);
  let score = fromSummary?.score ?? report.score ?? null;

  if (!Number.isFinite(errorCount) || !Number.isFinite(warningCount)) {
    errorCount = diagnostics.filter((d) => d?.severity === "error").length;
    warningCount = diagnostics.length - errorCount;
  }
  if (!Number.isFinite(totalDiagnosticCount)) {
    totalDiagnosticCount = diagnostics.length;
  }
  if (!Number.isFinite(affectedFileCount)) {
    affectedFileCount = new Set(
      diagnostics.map((d) => d?.normalizedFilePath || d?.filePath).filter(Boolean),
    ).size;
  }
  if (score === undefined || score === "") score = null;

  // Prefer project score when top-level is null but a single project has one.
  if (score == null && Array.isArray(report.projects) && report.projects.length === 1) {
    score = report.projects[0]?.score ?? null;
  }

  return {
    ok: report.ok !== false,
    mode: report.mode || "",
    version: report.version || "",
    errorCount,
    warningCount,
    affectedFileCount,
    totalDiagnosticCount,
    score: score == null ? "" : String(score),
    diagnostics,
    errorMessage: report.error?.message || report.error || "",
  };
}

function pluralize(count, noun) {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

function fileLink(filePath, line) {
  const server = (process.env.GITHUB_SERVER_URL || "https://github.com").replace(/\/$/, "");
  const repo = process.env.GITHUB_REPOSITORY || "";
  const sha = process.env.REACT_DOCTOR_HEAD_SHA || process.env.GITHUB_SHA || "";
  const normalized = String(filePath || "")
    .replace(/\\/g, "/")
    .replace(/^\.\//, "");
  if (!repo || !sha || !normalized) {
    return line > 0 ? `\`${normalized}:${line}\`` : `\`${normalized}\``;
  }
  const url =
    line > 0
      ? `${server}/${repo}/blob/${sha}/${normalized}#L${line}`
      : `${server}/${repo}/blob/${sha}/${normalized}`;
  const label = line > 0 ? `${normalized}:${line}` : normalized;
  return `[${label}](${url})`;
}

function groupByRule(diagnostics) {
  const map = new Map();
  for (const d of diagnostics) {
    const key = `${d.plugin || "unknown"}/${d.rule || "unknown"}`;
    if (!map.has(key)) {
      map.set(key, { key, severity: d.severity || "warning", items: [] });
    }
    map.get(key).items.push(d);
  }
  return [...map.values()].sort((a, b) => {
    if (a.severity !== b.severity) return a.severity === "error" ? -1 : 1;
    return b.items.length - a.items.length;
  });
}

function buildMarkdown(stats) {
  const lines = [MARKER, ""];

  if (!stats.ok) {
    lines.push("**React Doctor** could not complete this scan.");
    if (stats.errorMessage) {
      lines.push("");
      lines.push("```");
      lines.push(String(stats.errorMessage).slice(0, 2000));
      lines.push("```");
    }
    lines.push("");
    lines.push(`<sub>Zondax React Doctor action · [docs](${BRAND})</sub>`);
    return lines.join("\n");
  }

  const issues = stats.totalDiagnosticCount;
  const scorePart = stats.score !== "" ? ` · score **${stats.score}/100**` : "";
  const scopePart = stats.mode ? ` · \`${stats.mode}\`` : "";

  if (issues === 0) {
    lines.push(`**React Doctor** found no issues. 🎉${scorePart}${scopePart}`);
  } else {
    lines.push(
      `**React Doctor** found **${pluralize(issues, "issue")}** in ${pluralize(
        stats.affectedFileCount,
        "file",
      )} (${pluralize(stats.errorCount, "error")}, ${pluralize(
        stats.warningCount,
        "warning",
      )})${scorePart}${scopePart}`,
    );
  }

  const groups = groupByRule(stats.diagnostics);
  const maxGroups = 25;
  const maxPerGroup = 8;

  for (const group of groups.slice(0, maxGroups)) {
    const icon = group.severity === "error" ? "❌" : "⚠️";
    lines.push("");
    lines.push(
      `### ${icon} \`${group.key}\` (${pluralize(group.items.length, "site")})`,
    );
    const sample = group.items[0];
    if (sample?.message) {
      lines.push("");
      lines.push(sample.message);
    }
    if (sample?.help) {
      lines.push("");
      lines.push(`**Fix** → ${sample.help}`);
    }
    lines.push("");
    for (const item of group.items.slice(0, maxPerGroup)) {
      const line = Number(item.line) > 0 ? Number(item.line) : 0;
      lines.push(`- ${fileLink(item.normalizedFilePath || item.filePath, line)}`);
    }
    if (group.items.length > maxPerGroup) {
      lines.push(`- _…${group.items.length - maxPerGroup} more_`);
    }
    lines.push("");
    lines.push(`[Rule docs](${BRAND}/docs/rules/${group.key})`);
  }

  if (groups.length > maxGroups) {
    lines.push("");
    lines.push(`_…${groups.length - maxGroups} more rules not shown_`);
  }

  const sha = (process.env.REACT_DOCTOR_HEAD_SHA || process.env.GITHUB_SHA || "").slice(0, 7);
  const version = stats.version ? ` · react-doctor@${stats.version}` : "";
  const commit = sha ? ` · \`${sha}\`` : "";
  lines.push("");
  lines.push(
    `<sub>Zondax React Doctor action${version}${commit} · [react.doctor](${BRAND})</sub>`,
  );

  return `${lines.join("\n")}\n`;
}

function writeOutput(stats, summaryFile) {
  const out = process.env.GITHUB_OUTPUT;
  if (!out) return;
  const payload = {
    score: stats.score,
    "total-issues": String(stats.totalDiagnosticCount),
    "error-count": String(stats.errorCount),
    "warning-count": String(stats.warningCount),
    "affected-files": String(stats.affectedFileCount),
    ok: stats.ok ? "true" : "false",
    version: stats.version,
    mode: stats.mode,
    "summary-file": summaryFile,
  };
  const lines = Object.entries(payload).map(([k, v]) => `${k}=${v ?? ""}`);
  fs.appendFileSync(out, `${lines.join("\n")}\n`);
}

const report = readReport(reportPath);
const stats = summarize(report);
const markdown = buildMarkdown(stats);

fs.mkdirSync(path.dirname(summaryPath), { recursive: true });
fs.writeFileSync(summaryPath, markdown, "utf8");
writeOutput(stats, summaryPath);

console.log(
  `React Doctor parse: ok=${stats.ok} errors=${stats.errorCount} warnings=${stats.warningCount} score=${stats.score || "n/a"}`,
);
