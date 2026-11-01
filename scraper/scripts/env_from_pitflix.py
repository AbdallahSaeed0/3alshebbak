# Fills the scraper's .env from Pitflix's own settings: its Supabase project
# (URL + service role key, saved in Pitflix › Settings › Sync with Mobile) and
# its TMDB key. Prints only which keys it found, never their values.
#
#   python scripts/env_from_pitflix.py
#
# Run it from the scraper folder, in your own terminal.
import os, pathlib, shutil, sqlite3, tempfile

DEFAULT_SUPABASE_URL = 'https://enmcbbwunzhjxgwehzuf.supabase.co'  # Pitflix's built-in default

src = pathlib.Path(os.environ['LOCALAPPDATA']) / 'Pitflix' / 'pitflix.db'
env = pathlib.Path(__file__).resolve().parent.parent / '.env'

# Pitflix may be running and holding the database; read a copy instead.
with tempfile.TemporaryDirectory() as tmp:
    copy = pathlib.Path(tmp) / 'pitflix.db'
    shutil.copy(src, copy)
    for ext in ('-wal', '-shm'):
        if src.with_name(src.name + ext).exists():
            shutil.copy(src.with_name(src.name + ext), copy.with_name(copy.name + ext))
    con = sqlite3.connect(copy)
    table = next(r[0] for r in con.execute(
        "select name from sqlite_master where type='table' and lower(name) like '%setting%'"))
    cols = [r[1] for r in con.execute(f'pragma table_info("{table}")')]
    k = next(c for c in cols if c.lower() == 'key')
    v = next(c for c in cols if c.lower() == 'value')
    settings = dict(con.execute(f'select "{k}", "{v}" from "{table}"'))
    con.close()

values = {
    'SUPABASE_URL': (settings.get('SupabaseUrl') or DEFAULT_SUPABASE_URL).strip().rstrip('/'),
    'SUPABASE_SERVICE_ROLE_KEY': (settings.get('SupabaseServiceRoleKey') or '').strip(),
    'TMDB_API_KEY': (settings.get('TmdbApiKey') or '').strip(),
}
lines = env.read_text(encoding='utf-8').splitlines() if env.exists() else []
current = {l.split('=', 1)[0].strip(): l.split('=', 1)[1].strip() for l in lines if '=' in l and not l.startswith('#')}

# Only fill keys that are empty in .env: values set by hand are never overwritten.
for name, value in values.items():
    if current.get(name):
        print(f'{name}: already set, kept')
        values[name] = None
    else:
        print(f'{name}: {"found" if value else "MISSING"}')

out = []
for l in lines:
    name = l.split('=', 1)[0].strip()
    out.append(f'{name}={values[name]}' if values.get(name) else l)
out += [f'{n}={v}' for n, v in values.items() if v and n not in current]
env.write_text('\n'.join(out) + '\n', encoding='utf-8')
print(f'wrote {env}')
