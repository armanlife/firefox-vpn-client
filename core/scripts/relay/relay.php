<?php
// API relay for the VPN client, as one PHP file (PHP 7.3 or later, with
// the curl extension, on any host that serves HTTPS).
//
// When Mozilla's sign-in, Guardian, or server list cannot be reached from
// your network, the client sends those requests (never the VPN traffic)
// through this relay: upload the file, then set its URL in the app's
// Settings > Connection > "If Mozilla is blocked" > "Cloudflare Worker" (the
// dashboard's Settings > "If Mozilla is blocked"), for example
// https://example.com/relay.php?secret=SECRET
// Opened in a browser, the URL shows whether the relay works.
//
// The client asks for relay.php?url=<target>; the relay sends the same
// method, headers, and body to the target and answers with its response.
// Only the hosts below are relayed, so the relay is not an open proxy for
// others.

// A secret only your client knows, which the relay URL ends in:
// ?secret=SECRET. Required: without one the relay relays nothing (the
// sign-in and the account tokens cross it).
$SECRET = '';

$ALLOWED = [
    'mozilla.org', 'mozilla.com', 'firefox.com', // accounts, Guardian, server list
    'github.com', 'githubusercontent.com', 'jsdelivr.net', // geo files, flags
];

// Headers that describe this hop, not the request or the response.
$HOP = ['host', 'connection', 'keep-alive', 'content-length', 'transfer-encoding', 'accept-encoding',
    'x-forwarded-for', 'x-forwarded-proto', 'x-forwarded-host', 'x-real-ip', 'upgrade', 'te', 'trailer'];

function fail($status, $why)
{
    http_response_code($status);
    header('X-Relay-Error: ' . $why);
    header('Content-Type: text/plain');
    echo $why;
    exit;
}

function ends_with($text, $suffix)
{
    return substr($text, -strlen($suffix)) === $suffix;
}

// The page for whoever opens the relay's URL in a browser (no url
// parameter): whether it works, and what to do (as worker.js shows it).
function page($state)
{
    $states = [
        'works' => [200, '#10b981', '✓ Working', 'Your relay is ready', "Put this page's address in Firefox VPN:",
            ['Settings', 'Connection', 'If Mozilla is blocked', 'Cloudflare Worker']],
        'wrong' => [403, '#ef4444', '✗ Wrong secret', 'This address has no secret, or the wrong one',
            'It must end in <code>?secret=</code> followed by the $SECRET set in the file.', []],
        'unset' => [503, '#f59e0b', '⚠ Not set up', 'Set a secret first',
            'Set <code>$SECRET</code> in the file to a long random text, upload it again, and open this address with <code>?secret=…</code> at the end.', []],
    ];
    [$status, $color, $badge, $title, $text, $steps] = $states[$state];
    $path = $steps ? '<div class="path"><span>' . implode('</span><i>›</i><span>', $steps) . '</span></div>' : '';
    http_response_code($status);
    header('Content-Type: text/html; charset=utf-8');
    echo <<<HTML
<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Firefox VPN relay</title>
<style>
:root{--bg:#eef0fb;--card:#fff;--text:#1d2040;--muted:#5d6385;--accent:#5b5bd6;--c:$color}
@media (prefers-color-scheme:dark){:root{--bg:#0b0e1f;--card:#151a35;--text:#eef0ff;--muted:#9aa3c7;--accent:#8b8ff8}}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;color:var(--text);
font:16px/1.65 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
background:radial-gradient(900px 500px at 15% -10%,color-mix(in srgb,var(--accent) 28%,transparent),transparent),
radial-gradient(700px 500px at 110% 110%,color-mix(in srgb,var(--c) 22%,transparent),transparent),var(--bg)}
.card{width:min(560px,100%);background:var(--card);border-radius:22px;padding:34px 32px;
box-shadow:0 24px 70px rgba(20,27,61,.18);border-top:5px solid var(--c)}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;color:var(--muted);font-size:14px;letter-spacing:.02em}
.dot{width:10px;height:10px;border-radius:50%;background:var(--accent)}
.badge{display:inline-block;margin-top:22px;padding:6px 14px;border-radius:999px;font-weight:700;font-size:14px;
color:var(--c);background:color-mix(in srgb,var(--c) 15%,transparent)}
h1{font-size:23px;line-height:1.3;margin:14px 0 8px}
p{margin:0;color:var(--muted)}
code{background:color-mix(in srgb,var(--accent) 12%,transparent);color:var(--accent);padding:1px 6px;border-radius:6px}
.path{display:flex;flex-wrap:wrap;align-items:center;gap:6px;margin-top:16px}
.path span{padding:5px 12px;border-radius:10px;font-weight:600;font-size:14px;
background:color-mix(in srgb,var(--accent) 13%,transparent);color:var(--accent)}
.path i{color:var(--muted);font-style:normal}
</style>
<div class="card"><div class="brand"><span class="dot"></span>Firefox VPN relay</div>
<span class="badge">$badge</span><h1>$title</h1><p>$text</p>$path</div></html>
HTML;
    exit;
}

$browser = !isset($_GET['url']);
if ($SECRET === '') {
    $browser ? page('unset') : fail(503, 'no secret is set in the relay');
}
if (!hash_equals($SECRET, (string)($_GET['secret'] ?? ''))) {
    $browser ? page('wrong') : fail(403, 'wrong secret');
}
if ($browser) {
    page('works');
}
$target = (string)($_GET['url'] ?? '');
$parts = parse_url($target);
if (!$parts || ($parts['scheme'] ?? '') !== 'https' || empty($parts['host'])) {
    fail(400, 'url must be an https URL');
}
$host = strtolower($parts['host']);
$allowed = false;
foreach ($ALLOWED as $domain) {
    if ($host === $domain || ends_with($host, '.' . $domain)) {
        $allowed = true;
    }
}
if (!$allowed) {
    fail(403, 'host not allowed: ' . $host);
}

$headers = [];
foreach (getallheaders() as $name => $value) {
    $lower = strtolower($name);
    if (in_array($lower, $HOP, true) || strpos($lower, 'cf-') === 0) {
        continue;
    }
    $headers[] = $name . ': ' . $value;
}

$method = $_SERVER['REQUEST_METHOD'];
$ch = curl_init($target);
curl_setopt_array($ch, [
    CURLOPT_CUSTOMREQUEST => $method,
    CURLOPT_HTTPHEADER => $headers,
    // Redirects go back to the client, which follows them through the relay.
    CURLOPT_FOLLOWLOCATION => false,
    CURLOPT_CONNECTTIMEOUT => 20,
    CURLOPT_TIMEOUT => 600,
    // The response's status and headers, as they arrive (a 100 Continue
    // comes first sometimes).
    CURLOPT_HEADERFUNCTION => function ($ch, $line) use ($HOP) {
        $trimmed = trim($line);
        if (preg_match('#^HTTP/\S+\s+(\d{3})#', $trimmed, $m)) {
            http_response_code((int)$m[1]);
        } elseif ($trimmed !== '' && strpos($trimmed, ':') !== false) {
            $name = strtolower(trim(strstr($trimmed, ':', true)));
            if (!in_array($name, $HOP, true)) {
                header($trimmed, false);
            }
        }
        return strlen($line);
    },
    // The body is passed on as it arrives, so large files need no memory.
    CURLOPT_WRITEFUNCTION => function ($ch, $data) {
        echo $data;
        flush();
        return strlen($data);
    },
]);
if ($method !== 'GET' && $method !== 'HEAD') {
    curl_setopt($ch, CURLOPT_POSTFIELDS, file_get_contents('php://input'));
}
if ($method === 'HEAD') {
    curl_setopt($ch, CURLOPT_NOBODY, true);
}
if (curl_exec($ch) === false && !headers_sent()) {
    fail(502, 'the target did not answer: ' . curl_error($ch));
}
curl_close($ch);
