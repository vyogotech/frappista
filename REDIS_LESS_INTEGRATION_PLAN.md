# Redis-less Integration Plan for Frappista S2I

**Status:** Planned — awaiting upstream PR approval (`vyogotech/frappe` → `frappe/frappe`)  
**Depends on:** [feat/redis-less-developer-onboarding](https://github.com/vyogotech/frappe/tree/feat/redis-less-developer-onboarding) in `vyogotech/frappe`  
**Author:** Varun Krishnamurthy <varun@vyogolabs.tech>

---

## Overview

Add an `ENABLE_REDIS` environment variable (default `false`) so containers start in Redis-less mode out of the box. Developers get a working Frappe/ERPNext with zero extra services. Set `ENABLE_REDIS=true` to restore full Redis behaviour for production.

The Redis-less fallback relies on `MemoryCacheWrapper` from the upstream Frappe change. This plan must not be implemented until that PR is merged into `frappe/frappe`.

---

## New Environment Variables

| Variable | Default | Description |
|---|---|---|
| `ENABLE_REDIS` | `false` | `true` = start and use Redis (production); `false` = in-memory cache (development) |
| `SETUP_WIZARD` | `false` | Run `bench setup-wizard` automatically after site creation |
| `SETUP_COUNTRY` | `India` | Country for setup wizard |
| `SETUP_TIMEZONE` | `Asia/Kolkata` | Timezone for setup wizard |
| `SETUP_CURRENCY` | `INR` | ISO currency code |
| `SETUP_COMPANY` | *(empty)* | Company name — optional, used for ERPNext |
| `SETUP_EMAIL` | `admin@example.com` | Administrator email |
| `SETUP_PASSWORD` | `admin` | Administrator password |

---

## Files to Change

### 1. `s2i/bin/assemble`

**Current behaviour:** always starts Redis, always writes Redis URLs to bench config.

**Changes required:**

#### a) Wrap Redis startup in `ENABLE_REDIS` guard

```bash
# BEFORE (lines ~220-221):
start_redis
wait_for_redis

# AFTER:
if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
    start_redis
    wait_for_redis
    log "Redis services started."
else
    log "ENABLE_REDIS=false — skipping Redis (using in-memory cache fallback)."
fi
```

#### b) Conditionally configure Redis URLs vs memory cache

```bash
# BEFORE (lines ~256-258):
bench set-config --global redis_cache "redis://localhost:6379"
bench set-config --global redis_queue "redis://localhost:6379"
bench set-config --global redis_socketio "redis://localhost:6379"

# AFTER:
if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
    bench set-config --global redis_cache "redis://localhost:6379"
    bench set-config --global redis_queue "redis://localhost:6379"
    bench set-config --global redis_socketio "redis://localhost:6379"
else
    bench set-config --global use_memory_cache 1
    # Remove Redis keys if they were set by a prior layer
    bench set-config --global redis_cache "" 2>/dev/null || true
    bench set-config --global redis_queue "" 2>/dev/null || true
    bench set-config --global redis_socketio "" 2>/dev/null || true
fi
```

#### c) Add optional setup wizard after site creation

After the `create_site` call completes (currently line ~369), add:

```bash
# Optional: run setup wizard non-interactively
if [[ "${SETUP_WIZARD:-false}" == "true" ]]; then
    log "Running setup wizard for $site_name..."
    setup_args=(
        --country  "${SETUP_COUNTRY:-India}"
        --timezone "${SETUP_TIMEZONE:-Asia/Kolkata}"
        --currency "${SETUP_CURRENCY:-INR}"
        --email    "${SETUP_EMAIL:-admin@example.com}"
        --password "${SETUP_PASSWORD:-admin}"
    )
    [[ -n "${SETUP_COMPANY:-}" ]] && setup_args+=(--company-name "$SETUP_COMPANY")
    bench --site "$site_name" setup-wizard "${setup_args[@]}" \
        && log "Setup wizard completed." \
        || log "WARNING: Setup wizard failed — run manually after container starts."
fi
```

---

### 2. `s2i/bin/run`

**Current behaviour:** always starts Redis, hard-fails if `redis-server` not found.

**Changes required:**

#### a) Make `redis-server` check conditional

```bash
# BEFORE (line ~75):
command -v redis-server >/dev/null 2>&1 || error "redis-server is not installed. Please install Redis."

# AFTER:
if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
    command -v redis-server >/dev/null 2>&1 || error "redis-server is not installed. Please install Redis."
fi
```

#### b) Wrap Redis start block in guard (lines ~91-108)

```bash
# AFTER:
if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
    log "Starting Redis server..."
    if redis-server --save "" --appendonly no --dir /tmp/redis --daemonize yes --pidfile /tmp/pids/redis.pid &> /var/log/redis.log; then
      # ... existing success/failure checks ...
    fi
else
    log "ENABLE_REDIS=false — skipping Redis (using in-memory cache fallback)."
fi
```

#### c) Patch Procfile when Redis disabled

After the existing `ENABLE_WATCH` Procfile block, add:

```bash
PROCFILE="/home/frappe/frappe-bench/Procfile"
if [[ "${ENABLE_REDIS:-false}" != "true" && -f "$PROCFILE" ]]; then
    log "Redis-less mode: patching Procfile (removing worker/socketio/schedule, adding --nothreading)."
    # Disable worker, socketio, schedule processes
    sed -i 's/^worker:/#worker:/'   "$PROCFILE"
    sed -i 's/^socketio:/#socketio:/' "$PROCFILE"
    sed -i 's/^schedule:/#schedule:/' "$PROCFILE"
    # Add --nothreading to gunicorn to prevent concurrent DB lock contention
    # (setup wizard holds a row lock for its full duration)
    if grep -q '^web:' "$PROCFILE" && ! grep -q '\-\-nothreading' "$PROCFILE"; then
        sed -i 's/^\(web:.*gunicorn\)/\1 --nothreading/' "$PROCFILE"
    fi
fi
```

#### d) Skip Redis post-start commands when disabled

```bash
# BEFORE (line ~191-192):
redis-cli CONFIG SET protected-mode no  || true
bench --site all clear-cache || true

# AFTER:
if [[ "${ENABLE_REDIS:-false}" == "true" ]]; then
    redis-cli CONFIG SET protected-mode no || true
fi
bench --site all clear-cache || true
```

#### e) Conditional Redis cleanup in `cleanup()`

```bash
# AFTER (in cleanup function):
if [[ "${ENABLE_REDIS:-false}" == "true" && -f /tmp/pids/redis.pid ]]; then
    redis-cli shutdown || kill -15 $(cat /tmp/pids/redis.pid)
    log "Redis server stopped."
fi
```

---

### 3. `config/common_site_config.json`

This file is baked into the image. Two variants needed — the `assemble` script will write the correct one.

**Redis-less (default, `ENABLE_REDIS=false`):**
```json
{
    "use_memory_cache": 1,
    "socketio_port": 9000
}
```

**Redis-enabled (`ENABLE_REDIS=true`):**
```json
{
    "redis_cache": "redis://localhost:6379",
    "redis_queue": "redis://localhost:6379",
    "redis_socketio": "redis://localhost:6379",
    "socketio_port": 9000
}
```

The `assemble` script already runs `bench set-config --global` which writes to this file, so the logic in change (1b) above is sufficient — no need to ship two separate files.

---

## Backward Compatibility

| Scenario | How it works |
|---|---|
| Existing deployments with Redis | Set `ENABLE_REDIS=true` — identical behaviour to today |
| New dev/onboarding containers | Default `ENABLE_REDIS=false` — no Redis needed |
| Production compose stacks | Set `ENABLE_REDIS=true` — Redis containers used as today |
| Setup wizard automation | Set `SETUP_WIZARD=true` + country/tz/currency vars — wizard runs at build time |

No existing compose file or Makefile target needs to change unless the team wants to make Redis-less the explicit default.

---

## Suggested Compose Override

For developer quickstart, add to `development/compose.yml` or a new `compose.redis-less.yml`:

```yaml
services:
  frappe:
    environment:
      ENABLE_REDIS: "false"
      SETUP_WIZARD: "true"
      SETUP_COUNTRY: "Australia"
      SETUP_TIMEZONE: "Australia/Sydney"
      SETUP_CURRENCY: "AUD"
```

---

## Prerequisites / Blockers

1. **Upstream Frappe PR must be merged first** — `MemoryCacheWrapper`, `use_memory_cache` fallback, `bench setup-wizard` command must be in `frappe/frappe` before this works in production images. The feature branch is at `vyogotech/frappe:feat/redis-less-developer-onboarding`.

2. **Image rebuild required** — Any image built before this change will have Redis URLs hard-coded in `common_site_config.json`. A fresh S2I build is needed.

---

## Implementation Order

1. Wait for `frappe/frappe` upstream PR approval and merge
2. Update `frappe` dependency/branch in `Containerfile` or `apps.json` to pick up the merged code
3. Apply changes to `s2i/bin/assemble` (steps 1a, 1b, 1c)
4. Apply changes to `s2i/bin/run` (steps 2a–2e)
5. Rebuild test image with `ENABLE_REDIS=false` (the new default)
6. Verify: container starts → `/desk` loads → no Redis process running
7. Verify: `ENABLE_REDIS=true` → existing Redis behaviour unchanged
8. Update `README.md` with new env vars
