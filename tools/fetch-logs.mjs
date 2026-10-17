#!/usr/bin/env node
/**
 * 拉取 GitHub Actions 的纯文本日志，筛出编译错误。
 *   node tools/fetch-logs.mjs owner/repo [runId] [--all]
 */
const TOKEN = process.env.GITHUB_TOKEN;
const API = 'https://api.github.com';
const args = process.argv.slice(2);
const repo = args.find((a) => a.includes('/'));
const runIdArg = args.find((a) => /^\d+$/.test(a));
const showAll = args.includes('--all');

if (!TOKEN || !repo) {
  console.error('用法: GITHUB_TOKEN=xxx node tools/fetch-logs.mjs owner/repo [runId]');
  process.exit(1);
}

async function gh(path) {
  const res = await fetch(`${API}${path}`, {
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'lovetrack-logs',
    },
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { raw: text };
  }
  return { status: res.status, data, ok: res.ok };
}

async function fetchRaw(url) {
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      Accept: 'application/vnd.github+json',
      'User-Agent': 'lovetrack-logs',
    },
    redirect: 'manual',
  });
  if (res.status >= 300 && res.status < 400) {
    const loc = res.headers.get('location');
    const r2 = await fetch(loc);
    return await r2.text();
  }
  return await res.text();
}

let runId = runIdArg;
if (!runId) {
  const runs = await gh(`/repos/${repo}/actions/runs?per_page=1`);
  runId = String(runs.data.workflow_runs[0].id);
  console.log(`最新运行 #${runs.data.workflow_runs[0].run_number}: ${runs.data.workflow_runs[0].html_url}\n`);
}

const jobs = await gh(`/repos/${repo}/actions/runs/${runId}/jobs`);
if (!jobs.ok) {
  console.error('拿不到 job 列表:', jobs.status, jobs.data);
  process.exit(1);
}

for (const job of jobs.data.jobs) {
  if (job.conclusion === 'success') continue;
  console.log(`\n${'='.repeat(70)}\nJob: ${job.name}  (${job.conclusion})\n${'='.repeat(70)}`);
  const log = await fetchRaw(`${API}/repos/${repo}/actions/jobs/${job.id}/logs`);

  const lines = log.split('\n');
  if (showAll) {
    console.log(log);
    continue;
  }

  // 过滤：只留错误/警告/关键上下文
  const keep = [];
  for (let i = 0; i < lines.length; i += 1) {
    const l = lines[i];
    if (
      /error:/i.test(l) ||
      /\*\* BUILD FAILED \*\*/.test(l) ||
      /The following build commands failed/i.test(l) ||
      /Compiling .*\.swift/.test(l) && /error/i.test(l)
    ) {
      // 带上前后各 2 行
      for (let k = Math.max(0, i - 2); k <= Math.min(lines.length - 1, i + 2); k += 1) {
        keep.push(lines[k]);
      }
      keep.push('');
    }
  }

  if (keep.length === 0) {
    console.log('（没有匹配到 error:，显示最后 60 行）\n');
    console.log(lines.slice(-60).join('\n'));
  } else {
    // 去重保序
    const seen = new Set();
    const out = keep.filter((l) => {
      if (seen.has(l)) return false;
      seen.add(l);
      return true;
    });
    console.log(out.join('\n'));
  }
}
