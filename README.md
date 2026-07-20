# Mase the Creative — website redesign

A Node-generated public website with an authenticated Supabase client workspace at `/portal/`. The production output is written to `dist/`.

## Pages

- Home
- Work and filterable portfolio
- Four reusable case studies
- Clients
- Services
- Content Direction monthly guidance membership
- About
- Contact
- Custom 404
- Ask Mase business chatbot
- Mase Workspace client portal

## Run locally

Requires Node.js 18 or newer.

```bash
npm run build
npm run preview
```

Then open `http://localhost:4173`.

Install dependencies first with `pnpm install` (preferred) or `npm install`. Portal setup, security and deployment instructions are in [`PORTAL_SETUP.md`](./PORTAL_SETUP.md).

If `npm` is unavailable but `node` is installed:

```bash
node build.mjs
PORT=4173 node server.mjs dist
```

Without an API key, Ask Mase automatically runs in safe demo mode. The complete five-question qualification flow, service guidance, contact routes and enquiry summary remain available.

## Connect Ask Mase to OpenAI

Set `OPENAI_API_KEY` as a private environment variable on the server or hosting platform. Never place it in `public/`, browser JavaScript or a committed file.

```bash
export OPENAI_API_KEY="your-key-here"
npm run preview
```

The server uses the OpenAI Responses API through `/api/chat`. It includes input limits, basic in-memory rate limiting, request timeouts and same-origin delivery. `OPENAI_CHAT_MODEL` can override the default model without editing source code.

## Deploy

Run the production build and deploy `server.mjs`, `chatbot-config.mjs` and `dist/` to a Node.js host. Configure private server variables there. The portal requires the Node server for protected invitation and client-creation endpoints.

### Render

The included `render.yaml` makes the repository deployable as a Render Blueprint. Connect the repository from Render, provide the requested OpenAI and Supabase variables, and let Render run the configured build and start commands. Test the generated `onrender.com` address before adding the production domain.

## Content architecture

Global details, services and case studies are maintained near the top of `build.mjs`. Shared navigation, metadata, schema, footer and page templates are generated from that single source.

## Before launch

- Connect a form endpoint. The verified current email is `mason@edgemediacreative.co.uk`; update it in `chatbot-config.mjs` and `public/chatbot.js` when the address changes.
- Replace the neutral `window.maseTrack` hook in `public/main.js` if analytics is required. Add consent handling only when a cookie-setting provider is introduced.
- Add verified client names/logos, testimonials and measured results when supplied.
- Add original showreel/video files and poster images when supplied.
- Confirm the preferred legal/privacy wording and business address requirements.

No clients, testimonials, awards or results were invented. All included images came from the existing public Mase the Creative website.

## Ask Mase knowledge and behaviour

The authoritative assistant instructions live in `chatbot-config.mjs`. They include the verified service area, starting price, contact routes, qualification questions, tone and refusal boundaries. The browser fallback in `public/chatbot.js` mirrors the same facts for safe testing without an API connection.
