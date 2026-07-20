# Mase Workspace setup

Mase Workspace is the private client portal at `/portal/`. The browser uses Supabase's public anonymous key and all access is enforced by Postgres row-level security (RLS). The service-role key stays on the Node server and is used only for administrator actions that cannot safely run in the browser.

## Architecture

- `build.mjs` continues to generate the public website and bundles the TypeScript portal with esbuild.
- `portal/` contains the portal source. Generated assets are written to `dist/portal/`.
- `server.mjs` serves the public website and portal SPA. It validates the current Supabase access token and the `app_admins` table before creating clients or sending invitations.
- `supabase/migrations/20260720_000001_mase_workspace.sql` creates the database, storage bucket, security helpers, approval transaction and RLS policies.
- `supabase/seed.sql` contains optional development-only client organisations. It does not create authentication users.

## Supabase project setup

1. Create a Supabase project in the UK or another region appropriate for the business and its data-processing requirements.
2. Apply `supabase/migrations/20260720_000001_mase_workspace.sql` with the Supabase CLI or SQL editor.
3. In Authentication → URL Configuration, set the production site URL to `https://masethecreative.co.uk` and add these redirect URLs:
   - `https://masethecreative.co.uk/portal/`
   - `https://masethecreative.co.uk/portal/account/`
   - the equivalent local and Render preview URLs used for testing
4. Keep email/password authentication enabled. Configure a branded invitation and password-reset email if required.
5. Create the first Mason admin user in Supabase Authentication. The profile row is created automatically by the database trigger.
6. Promote that user once, in the SQL editor, replacing the example value with the user's real UUID:

```sql
insert into public.app_admins (user_id)
values ('00000000-0000-0000-0000-000000000000');
```

After that, the admin can create client workspaces and send invitations from the portal.

## Environment variables

Copy `.env.example` into your local environment or configure these values in Render:

- `SUPABASE_URL`: Project URL from Supabase Settings → API.
- `SUPABASE_ANON_KEY`: Public anonymous/publishable key. This is bundled into the portal; RLS makes that safe.
- `SUPABASE_SERVICE_ROLE_KEY`: Secret server-only key. Never add this to `public/`, `portal/`, source control or a `VITE_`/`PUBLIC_` variable.
- `SITE_URL`: `https://masethecreative.co.uk` in production; used for secure invitation redirects.
- `OPENAI_API_KEY` and `OPENAI_CHAT_MODEL`: existing Ask Mase settings.

Build-time environment variables are read by `build.mjs`; restart the build after changing the Supabase URL or anonymous key.

## Run locally

```bash
pnpm install
pnpm build
PORT=4173 pnpm start
```

Open `http://localhost:4173/portal/`. Without Supabase variables, the portal deliberately displays a setup-required screen rather than a fake login or insecure demo account.

## Optional development data

Run `supabase/seed.sql` only in a development project. It creates Fourwards, The Black Horse and ORE4x4 workspaces plus starter briefs. Invite test users through the portal after seeding. Do not run the seed file in production.

## Security model

- Every client-owned record carries an `organisation_id`; composite foreign keys prevent child records from pointing into another organisation.
- RLS is enabled on every portal table. Platform admins can work across clients; clients and collaborators can only read organisations to which they belong.
- Clients can create ideas, comments, approval decisions, requests and client-visible files. Status management, analytics, briefs, production records and private notes are restricted by role.
- Content approval is handled by the `review_content` database function so the decision and content status update happen together.
- `workspace` is a private Storage bucket. Object policies mirror file-record visibility, and downloads use 60-second signed URLs.
- Admin HTTP endpoints authenticate the bearer token with Supabase, check `app_admins`, validate input and apply an in-memory rate limit.
- Portal pages send `noindex`, a restrictive Content Security Policy, `frame-ancestors 'none'`, no-store HTML caching and browser permissions restrictions.

RLS is the security boundary. Hiding a button in the interface is only a usability choice; it is never relied upon for data isolation.

## Test before launch

Run the automated local checks:

```bash
pnpm check
pnpm build
```

Use separate test accounts for each matrix row:

| Test | Expected result |
| --- | --- |
| Client A reads Client A ideas/files | Allowed |
| Client A requests Client B records via REST | Empty/denied by RLS |
| Collaborator linked to Client A | Can manage Client A production, cannot see Client B |
| Client changes an idea status outside the early draft stages | Denied |
| Client adds a comment, request, file and approval | Allowed in their organisation |
| Client reads `private_admin_notes` | Empty/denied |
| Admin switches organisations | Sees the selected client's data |
| Non-admin calls `/api/portal/admin/invite` | `403` |
| Missing/expired bearer token calls an admin endpoint | `401` |
| Private Storage URL is opened without a signed token | Denied |
| Password-reset link returns to `/portal/account/` | New-password view opens |

Also inspect the public header, portal login, pipeline, idea drawer, filming mode, calendar, approvals, analytics, files and admin screens at 1440 px, 768 px and 390 px widths. Test keyboard navigation, visible focus, escape-to-close dialogs, labels and reduced-motion mode.

## Render deployment

1. Add `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` to the Render service as secret environment variables. Set `SITE_URL` to the final HTTPS domain.
2. Deploy the branch to a preview or the `onrender.com` URL first.
3. Add that preview URL to Supabase Authentication redirect URLs before testing invitations and reset links.
4. Run the role-isolation test matrix against the deployed service.
5. Only then point the production domain or promote the deployment.

Do not log access tokens or the service-role key. Rotate the service-role key immediately if it is ever exposed.

## Phase-one limitations

- Analytics are entered manually; no Instagram, Facebook, TikTok, LinkedIn or YouTube accounts are connected.
- The calendar schedules work inside Mase Workspace but does not publish content to a social platform.
- Notifications are stored in the data model but no transactional notification service is connected yet. Supabase handles authentication emails and invitations.
- Files are previewed by signed download rather than in-browser annotation.
- The admin invitation route does not attach an already-existing Supabase user to another organisation; that exceptional case is handled in Supabase until a safe search-and-confirm flow is added.
- The portal supports one active workspace at a time in the interface. Platform admins switch clients from the sidebar.

## Phase two

- Platform analytics integrations and scheduled data imports.
- Email/in-app notification delivery and digest preferences.
- Social publishing integrations with an explicit final-confirmation step.
- Asset previews, time-coded video feedback and version history.
- Recurring content templates, saved shot lists and automated reporting exports.
- Audit-log export, user deactivation and an admin flow for linking existing users to additional organisations.
