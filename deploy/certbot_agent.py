"""Tellora certbot agent: free SSL for store owners' custom domains.

Runs in its own container (certbot/certbot image) next to nginx. Every minute it asks
the app which domains need a certificate (GET /internal/tls/queue, token protected):

  issue   -> certbot gets a certificate (HTTP check through /.well-known/acme-challenge/),
             writes an nginx server block for the domain and asks nginx to reload
  remove  -> deletes the nginx server block and the certificate
  active  -> renewed automatically when they are close to expiry (checked once a day)

nginx reloads itself when the file "<custom dir>/.reload" changes (see docker-compose.yml),
after testing its configuration first, so a bad file can never take the sites down.
Only domains approved by the app (DNS verified) are ever requested.
"""

import json
import os
import re
import subprocess
import sys
import time
import urllib.request

APP_URL = os.environ.get("APP_URL", "http://app:3000").rstrip("/")
TOKEN = os.environ.get("TLS_AGENT_TOKEN", "")
EMAIL = os.environ.get("LETSENCRYPT_EMAIL", "")
WEBROOT = os.environ.get("ACME_WEBROOT", "/var/www/certbot")
CUSTOM_DIR = os.environ.get("NGINX_CUSTOM_DIR", "/nginx-custom")
UPSTREAM = os.environ.get("NGINX_UPSTREAM", "tellora_app")
POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "60"))
RENEW_EVERY = 24 * 60 * 60

HOST_RE = re.compile(r"^(?=.{4,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")


def log(message):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), "[certbot-agent]", message, flush=True)


def api(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(APP_URL + path, data=data, method=method)
    request.add_header("Authorization", "Bearer " + TOKEN)
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=20) as response:
        body = response.read().decode() or "{}"
        return json.loads(body) if body.strip().startswith("{") else {}


def valid(entry):
    names = entry.get("names") or []
    hosts = [entry.get("host", ""), entry.get("primary", ""), entry.get("cert_name", "")] + names
    return bool(names) and all(HOST_RE.match(h or "") for h in hosts)


def request_reload():
    os.makedirs(CUSTOM_DIR, exist_ok=True)
    with open(os.path.join(CUSTOM_DIR, ".reload"), "w") as flag:
        flag.write(str(time.time()))


def server_block(entry):
    names = " ".join(entry["names"])
    primary = entry["primary"]
    cert = entry["cert_name"]
    return f"""# Managed by the Tellora certbot agent. Do not edit: it is rewritten automatically.
# Custom domain: {entry["host"]}
server {{
  listen 443 ssl;
  http2 on;
  server_name {names};

  ssl_certificate     /etc/letsencrypt/live/{cert}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/{cert}/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers off;

  add_header Strict-Transport-Security "max-age=31536000" always;

  if ($host != "{primary}") {{
    return 301 https://{primary}$request_uri;
  }}

  location / {{
    proxy_pass http://{UPSTREAM};
    proxy_http_version 1.1;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Ssl   on;
    proxy_set_header Upgrade           $http_upgrade;
    proxy_set_header Connection        $connection_upgrade;
    proxy_read_timeout 180s;
  }}
}}
"""


def conf_path(entry):
    return os.path.join(CUSTOM_DIR, entry["cert_name"] + ".conf")


def run_certbot(args):
    result = subprocess.run(["certbot"] + args, capture_output=True, text=True, timeout=300)
    output = (result.stdout + "\n" + result.stderr).strip()
    return result.returncode == 0, output


def issue(entry):
    log(f"issuing certificate for {', '.join(entry['names'])}")
    args = ["certonly", "--webroot", "-w", WEBROOT, "--cert-name", entry["cert_name"],
            "--non-interactive", "--agree-tos", "--keep-until-expiring", "--expand"]
    args += ["-m", EMAIL] if EMAIL else ["--register-unsafely-without-email"]
    for name in entry["names"]:
        args += ["-d", name]

    ok, output = run_certbot(args)
    if not ok:
        reason = next((line.strip() for line in output.splitlines() if "Detail:" in line or "Error" in line), output[-300:])
        log(f"certificate failed for {entry['host']}: {reason}")
        api("POST", "/internal/tls/failed", {"host": entry["host"], "error": reason[:480]})
        return

    os.makedirs(CUSTOM_DIR, exist_ok=True)
    tmp = conf_path(entry) + ".tmp"
    with open(tmp, "w") as handle:
        handle.write(server_block(entry))
    os.replace(tmp, conf_path(entry))
    request_reload()
    time.sleep(25)  # nginx checks for the reload flag every 20 seconds
    api("POST", "/internal/tls/issued", {"host": entry["host"]})
    log(f"{entry['host']} is live")


def remove(entry):
    log(f"removing {entry['host']}")
    try:
        os.remove(conf_path(entry))
    except FileNotFoundError:
        pass
    request_reload()
    run_certbot(["delete", "--cert-name", entry["cert_name"], "--non-interactive"])
    api("POST", "/internal/tls/removed", {"host": entry["host"]})


def renew(active):
    renewed = False
    for entry in active:
        if not valid(entry):
            continue
        ok, output = run_certbot(["renew", "--cert-name", entry["cert_name"], "--webroot", "-w", WEBROOT,
                                  "--non-interactive", "--quiet"])
        if not ok:
            log(f"renewal problem for {entry['host']}: {output[-200:]}")
        else:
            renewed = True
    if renewed:
        request_reload()


def main():
    if not TOKEN:
        log("TLS_AGENT_TOKEN is not set; nothing to do")
        while True:
            time.sleep(3600)

    log(f"started, asking {APP_URL} every {POLL_SECONDS}s")
    last_renew = 0
    while True:
        try:
            queue = api("GET", "/internal/tls/queue")
            for entry in queue.get("issue", []):
                if valid(entry):
                    issue(entry)
                else:
                    log(f"skipping invalid entry {entry!r}")
            for entry in queue.get("remove", []):
                if valid(entry):
                    remove(entry)
            if time.time() - last_renew > RENEW_EVERY:
                renew(queue.get("active", []))
                last_renew = time.time()
        except Exception as error:  # keep running whatever happens
            log(f"error: {error}")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    sys.exit(main())
