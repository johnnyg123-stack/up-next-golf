# Up Next Golf

A player directory for junior golfers. Players **sign in with their own email**
and create their **own** profile — name, hometown, graduating year, college
commitment, height, weight — plus their **tournament schedule**. Anyone can
browse the directory; each player can only edit their own profile.

Built as a static site (HTML/CSS/JS) backed by [Supabase](https://supabase.com)
for authentication and the database, with Row-Level Security so a player can only
write their own data.

## Files
- `index.html` — the whole app (directory · sign in / sign up · profile editor)
- `config.js` — Supabase project URL + publishable key
- `supabase-setup.sql` — run once in Supabase to create the tables + security rules

## Local development
Open `index.html` in a browser. It reads your Supabase keys from `config.js`.

## Privacy
Profiles are **opt-in**: a player creates their own account and enters their own
details. No player data is added without that person signing in and doing it
themselves.
