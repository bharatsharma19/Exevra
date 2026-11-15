// End-to-end smoke test of the local Supabase backend and Edge Functions.
// Run after `supabase start`, `supabase db reset` and `supabase functions serve`:
//   eval "$(supabase status -o env | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
//   node supabase/e2e/smoke.mjs "$API_URL" "$ANON_KEY" "$SERVICE_ROLE_KEY"
// Never prints keys or tokens. Needs a real ANTHROPIC_API_KEY in supabase/functions/.env.
const [API, ANON, SERVICE] = process.argv.slice(2)
const log = (...a) => console.log(...a)
let failures = 0
const check = (ok, msg) => { log(`${ok ? 'PASS' : 'FAIL'}  ${msg}`); if (!ok) failures++ }

async function j(method, path, { token, key = ANON, body, headers = {} } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { apikey: key, 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const text = await res.text()
  let data; try { data = text ? JSON.parse(text) : null } catch { data = text }
  return { status: res.status, data, headers: res.headers }
}

const stamp = process.pid
const email = `e2e.${stamp}@example.test`
const password = 'E2e-Passw0rd!'

// 1. confirmed user via admin API
let r = await j('POST', '/auth/v1/admin/users', { key: SERVICE, token: SERVICE, body: { email, password, email_confirm: true, user_metadata: { display_name: 'E2E Tester' } } })
check(r.status === 200 || r.status === 201, `admin create user (${r.status})`)
r = await j('POST', '/auth/v1/token?grant_type=password', { body: { email, password } })
check(r.status === 200, `sign in (${r.status})`)
const token = r.data?.access_token
const uid = r.data?.user?.id

// 2. personal expense (minor units)
r = await j('POST', '/rest/v1/expenses', { token, headers: { prefer: 'return=representation' }, body: { user_id: uid, title: 'Groceries at the market', amount_minor: 125050, currency: 'INR', category: 'Food', spent_at: new Date().toISOString() } })
check(r.status === 201, `insert expense (${r.status}) ${r.status !== 201 ? JSON.stringify(r.data).slice(0, 300) : ''}`)

// 3. ai-chat without consent -> 403 consent_required
const chatBody = { messages: [{ role: 'user', content: 'How much did I spend on food this month? Answer in one short sentence.' }], tz: 'Asia/Kolkata', locale: 'en-IN', days: 30 }
r = await j('POST', '/functions/v1/ai-chat', { token, body: chatBody })
check(r.status === 403 && r.data?.error?.code === 'consent_required', `ai-chat without consent -> ${r.status} ${r.data?.error?.code}`)

// 4. consent then a real streamed answer
r = await j('PATCH', `/rest/v1/profiles?id=eq.${uid}`, { token, headers: { prefer: 'return=representation' }, body: { ai_consent: true } })
check(r.status === 200 && Array.isArray(r.data) && r.data[0]?.ai_consent === true, `set ai_consent (${r.status})`)
const t0 = Date.now()
const res = await fetch(`${API}/functions/v1/ai-chat`, { method: 'POST', headers: { apikey: ANON, authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(chatBody) })
check(res.status === 200 && (res.headers.get('content-type') || '').includes('text/event-stream'), `ai-chat stream opened (${res.status} ${res.headers.get('content-type')})`)
const raw = await res.text()
const events = raw.split(/\n\n/).map(b => { const e = /event: (\w+)/.exec(b)?.[1]; const d = /data: (.*)/.exec(b)?.[1]; return e ? { e, d: d ? JSON.parse(d) : null } : null }).filter(Boolean)
const meta = events.find(x => x.e === 'meta')
const text = events.filter(x => x.e === 'delta').map(x => x.d.text).join('')
const last = events[events.length - 1]
check(!!meta, `meta event first (provider=${meta?.d?.provider})`)
check(events.findIndex(x => x.e === 'meta') < events.findIndex(x => x.e === 'delta'), 'meta precedes first delta')
check(last?.e === 'done', `stream ends with done (last=${last?.e} ${JSON.stringify(last?.d)})`)
check(text.length > 0, `answer text received (${text.length} chars, ${Date.now() - t0} ms)`)
log(`      answer: ${text.replace(/\s+/g, ' ').slice(0, 300)}`)
check(/1,250(\.50)?|1250(\.50)?|₹/.test(text), 'answer cites the seeded amount (₹1,250.50)')
r = await j('GET', `/rest/v1/ai_usage_events?select=status,provider&order=created_at.desc&limit=1`, { token })
check(r.status === 200 && r.data?.[0]?.status === 'ok', `usage event recorded (${JSON.stringify(r.data?.[0])})`)

// 5. group + invite (Resend not configured locally -> sent:false + share_url)
r = await j('POST', '/rest/v1/rpc/create_group', { token, body: { p_name: 'E2E Flat', p_currency: 'INR' } })
const groupId = r.data?.id ?? r.data?.[0]?.id
check(r.status === 200 && !!groupId, `create_group (${r.status})`)
r = await j('POST', '/functions/v1/send-invite', { token, body: { group_id: groupId, email: `friend.${stamp}@example.test`, role: 'member' } })
check(r.status === 200 && r.data?.sent === false && typeof r.data?.share_url === 'string', `send-invite honest when email not configured (${r.status} sent=${r.data?.sent} reason=${r.data?.reason})`)
check(/\/invite\/[A-Za-z0-9_-]{20,}$/.test(r.data?.share_url || ''), `share_url format /invite/<token> (${(r.data?.share_url || '').replace(/[A-Za-z0-9_-]{20,}$/, '<token>')})`)

// 6. delete account
r = await j('POST', '/functions/v1/delete-account', { token, body: {} })
check(r.status === 200 && r.data?.deleted === true, `delete-account (${r.status} ${JSON.stringify(r.data)})`)
r = await j('POST', '/auth/v1/token?grant_type=password', { body: { email, password } })
check(r.status === 400, `sign in after deletion refused (${r.status})`)

log(failures ? `\n${failures} FAILURE(S)` : '\nALL PASS')
process.exit(failures ? 1 : 0)
