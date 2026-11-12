const grid = document.getElementById('mission-grid');
const L = (key, fallback = '') => grid?.dataset[key] || fallback;

// Authentication failure is terminal for this page; transient failures are
// visible and retry with a growing delay. A hidden tab spends no request budget.
//
// The bus drives the refresh: an event on /events/stream refetches the
// panels, debounced, so the page updates when something happened rather than
// every eight seconds whether or not it did. A slow safety poll covers a quiet
// bus, and both the fetch and the stream back off while they fail.
const refreshState = document.getElementById('refresh-state');
const SAFETY_POLL_MS = 60000;
const EVENT_DEBOUNCE_MS = 1500;
const BACKOFF_MIN_MS = 2000;
const BACKOFF_MAX_MS = 300000;
let inFlight = false;
let terminal = false;
let failures = 0;
let streamFailures = 0;
let pollTimer = null;
let eventTimer = null;
let source = null;

const backoffMs = (count) => Math.min(BACKOFF_MAX_MS, BACKOFF_MIN_MS * 2 ** Math.max(0, count - 1));

function schedulePoll() {
  clearTimeout(pollTimer);
  if (terminal) return;
  pollTimer = setTimeout(refresh, failures ? backoffMs(failures) : SAFETY_POLL_MS);
}

function connectStream() {
  if (terminal || source || typeof EventSource !== 'function') return;
  source = new EventSource('/events/stream');
  source.onopen = () => { streamFailures = 0; };
  source.onmessage = () => {
    clearTimeout(eventTimer);
    eventTimer = setTimeout(refresh, EVENT_DEBOUNCE_MS);
  };

  // EventSource retries on its own every few seconds; close it and reconnect
  // on a growing delay instead, so a down server is not hammered.
  source.onerror = () => {
    source.close();
    source = null;
    if (terminal) return;
    streamFailures += 1;
    setTimeout(connectStream, backoffMs(streamFailures));
  };
}

function closeDoor() {
  terminal = true;
  clearTimeout(pollTimer);
  clearTimeout(eventTimer);
  if (source) { source.close(); source = null; }
  const note = document.createElement('p');
  note.textContent = L('i18nAuth', 'authentication required');
  grid.replaceChildren(note);
  refreshState.textContent = L('i18nAuth', 'authentication required');
}

function renderPanel(id, draw) {
  try {
    draw();
  } catch (error) {
    const reason = error?.message ? error.message : 'render failed';
    // A broken pane is isolated; even a detached/missing node cannot stop
    // the remaining panels from rendering.
    try {
      document.getElementById(id).textContent = `${L('i18nUnavailable', 'unavailable')}: ${reason}`;
    } catch (_error) {
      // The pane itself is absent; sibling panels still render.
    }
  }
}

async function refresh() {
  if (terminal || inFlight) return;
  if (document.hidden) { schedulePoll(); return; }
  inFlight = true;
  let ok = false;
  try {
    const r = await fetch('/dashboard/live', {
      headers: { Accept: 'application/json' },
      cache: 'no-store'
    });
    if (r.status === 401 || r.status === 403) { closeDoor(); return; }

    const d = await r.json();
    if (!r.ok || d.error) {
      const reason = d.error || `HTTP ${r.status}`;
      document.getElementById('status').textContent =
        `${L('i18nUnavailable', 'status unavailable')}: ${reason}`;
      refreshState.textContent = L('i18nRefreshFailed', 'live data unavailable; retrying');
      return;
    }

    const none = L('i18nBreakersNone', 'none');
    renderPanel('status', () => {
      const m = d.mission || {};
      document.getElementById('status').textContent = [
        `${L('labelModel', 'model')}: ${d.model}`,
        `mission: ${m.id || 'none'}`,
        `mission state: ${m.state || 'idle'} / ${m.stage || '—'}`,
        `effort: ${m.effort || '—'}`,
        `${L('labelCtx', 'ctx')}: ${d.tokens} ${L('labelTokens', 'tokens')}`,
        `${L('labelCost', 'cost')}: ${Number(d.cost || 0).toFixed(4)}`,
        `${L('labelAgentPool', 'agent pool')}: ${d.agent_pool} active`,
        `${L('labelBreakers', 'breakers')}: ${(d.open_breakers || []).join(', ') || none}`
      ].join('\n');
    });

    renderPanel('rtk', () => {
      const rtk = d.rtk || {};
      document.getElementById('rtk').textContent = [
        `${L('labelCommands', 'commands')}: ${rtk.commands || 0}`,
        `${L('labelSaved', 'saved')}: ${rtk.saved_pct || 0}%`,
        `${L('labelBytes', 'bytes')}: ${rtk.bytes_out || 0} / ${rtk.bytes_in || 0}`
      ].join('\n');
    });
    renderPanel('plan', () => {
      document.getElementById('plan').textContent = d.active_plan || L('i18nNone', '(none)');
    });
    renderPanel('rsi', () => {
      document.getElementById('rsi').textContent = (d.rsi_inbox || []).map(i => `${i.path}\n${i.excerpt}`).join('\n\n') || L('i18nEmpty', '(empty)');
    });
    renderPanel('skills', () => {
      document.getElementById('skills').textContent = (d.skills || []).join('\n') || L('i18nNone', '(none)');
    });

    renderPanel('pressure', () => {
      const p = d.context_pressure || {};
      document.getElementById('pressure').textContent = [
        `${L('labelBand', 'band')}: ${p.band || 'ok'}`,
        `${L('labelTokens', 'tokens')}: ${p.tokens || 0} / ${p.limit || 0}`,
        `${L('labelPct', 'pct')}: ${p.pct || 0}%`,
        `${L('labelHeadroom', 'headroom')}: ${p.headroom || 0}`
      ].join('\n');
    });

    renderPanel('providers', () => {
      const ph = d.provider_health || {};
      document.getElementById('providers').textContent = [
        `${L('labelStatus', 'status')}: ${ph.status || 'unknown'}`,
        `${L('labelOpenBreakers', 'open breakers')}: ${(ph.open_breakers || []).join(', ') || none}`,
        `${L('labelAgentPool', 'agent pool')}: ${ph.agent_pool || 0}`
      ].join('\n');
    });

    renderPanel('repair', () => {
      document.getElementById('repair').textContent = (d.repair_queue || []).map((item) => {
        const recent = (item.recent || []).join('\n  ');
        return `${item.path} (${item.count || 0} bytes)\n  ${recent}`;
      }).join('\n\n') || L('i18nEmpty', '(empty)');
    });

    renderPanel('fleet', () => {
      const fleet = d.fleet || {};
      document.getElementById('fleet').textContent = [
        ...(fleet.apps || []).map((app) =>
          `${app.name} (${app.domain}:${app.port}): ${app.up ? 'up' : 'down'}`),
        `${L('labelFleetLoad', 'load (1 min)')}: ${fleet.load ?? 'unknown'}` +
          (fleet.guard ? `  warn ${fleet.guard.load_warn} / crit ${fleet.guard.load_crit}` : ''),
        fleet.guard
          ? `${L('labelFleetOrder', 'sheds first')}: ${fleet.guard.shed_order.join(', then ')}` +
            `  (${L('labelFleetStrikes', 'after')}: ${fleet.guard.shed_strikes})`
          : `${L('labelFleetOrder', 'guard order')}: ${L('i18nUnavailable', 'unavailable')}`
      ].join('\n') || L('i18nEmpty', '(empty)');
    });

    renderPanel('quota', () => {
      const quota = d.model_quota || {};
      const cache = d.cache_efficiency || {};
      const used = Object.entries(quota.models || {})
        .map(([model, count]) => `${model}: ${count}`)
        .join(', ');
      const provider = quota.provider || null;
      const providerLine = provider
        ? `${L('labelQuotaProvider', 'provider quota')}: ${provider.used ?? '—'} / ${provider.limit ?? '—'}; ` +
          `${L('labelQuotaRemaining', 'remaining')}: ${provider.remaining ?? '—'}; ` +
          `${L(provider.fresh ? 'labelQuotaFresh' : 'labelQuotaStale', provider.fresh ? 'fresh' : 'stale')} ` +
          `(${L('labelQuotaAge', 'last read')}: ${provider.age_seconds ?? '—'}s)`
        : `${L('labelQuotaProvider', 'provider quota')}: ${L('i18nUnavailable', 'not available')}`;
      const forecastRows = Object.values(quota.forecasts || {}).map((forecast) =>
        `${forecast.model}: ${forecast.remaining} / ${forecast.limit} ` +
        `(${forecast.remaining_source}; ${L('labelQuotaForecast', 'per-model forecast')})`
      );
      document.getElementById('quota').textContent = [
        `${L('labelQuotaDay', 'day')}: ${quota.day || '—'}`,
        `${L('labelQuotaLimit', 'configured free limit')}: ${quota.limit ?? '—'}`,
        `${L('labelQuotaUsed', 'used by model')}: ${used || L('i18nNone', '(none)')}`,
        `${L('labelQuotaExhausted', 'exhausted')}: ${(quota.exhausted || []).join(', ') || none}`,
        providerLine,
        ...forecastRows,
        `${L('labelCachePct', 'prompt cache')}: ${cache.measured ? `${cache.efficiency_pct}%` : L('labelCacheUnavailable', 'not measured yet')}`,
        `${L('labelCacheTokens', 'cached tokens')}: ${cache.measured ? `${cache.cached_tokens} / ${cache.input_tokens}` : L('labelCacheUnavailable', 'not measured yet')}`
      ].join('\n');
    });

    renderPanel('bus', () => {
      document.getElementById('bus').textContent = (d.bus_events || []).slice(-12).map(e => JSON.stringify(e)).join('\n') || L('i18nQuiet', '(quiet)');
    });
    refreshState.textContent = `${L('i18nUpdated', 'updated')}: ${new Date().toLocaleTimeString()}`;
    ok = true;
  } catch (error) {
    const reason = error?.message ? error.message : 'network error';
    document.getElementById('status').textContent =
      `${L('i18nUnavailable', 'status unavailable')}: ${reason}`;
    refreshState.textContent = L('i18nRefreshFailed', 'live data unavailable; retrying');
  } finally {
    inFlight = false;
    if (!terminal) {
      failures = ok ? 0 : failures + 1;
      schedulePoll();
    }
  }
}
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
connectStream();
refresh();
