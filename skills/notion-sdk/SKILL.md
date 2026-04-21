---
name: notion-sdk
description: Notion API via the official @notionhq/client SDK. Use for search, pages, blocks, and databases (data sources). More performant than curl for frequent calls.
homepage: https://developers.notion.com
metadata:
  {
    "openclaw":
      {
        "emoji": "📝",
        "requires": { "bins": ["node"], "env": ["NOTION_API_KEY"] },
        "primaryEnv": "NOTION_API_KEY",
      },
  }
---

# notion-sdk

Use the official Notion JavaScript SDK (`@notionhq/client`) for search, pages, blocks, and data sources. Prefer this skill over the curl-based **notion** skill when OpenClaw calls Notion often (connection reuse, no subprocess per request).

## Setup

1. **Create an integration** at https://notion.so/my-integrations and copy the API key (`ntn_` or `secret_`).
2. **Set the API key** as `NOTION_API_KEY` or `NOTION_TOKEN` (env or OpenClaw skill config).
3. **Install the SDK** in this skill directory once (required for the CLI script):

```bash
cd {baseDir}
npm install --omit=dev
```

4. **Share** target pages/databases with your integration in Notion ("..." → "Connect to" → integration name).

On **AWS EC2 / Ubuntu**: copy the `notion-sdk` skill directory into your OpenClaw skills tree (e.g. where `openclaw skills status` looks), set `NOTION_API_KEY` in the environment or config, then run `cd <skill-path>/notion-sdk && npm install --omit=dev` once.

## Verify

```bash
NOTION_API_KEY="ntn_..." node {baseDir}/scripts/notion-cli.js me
```

Expect JSON with the bot user; otherwise check key and sharing.

## Commands

All commands output JSON to stdout. Replace `{baseDir}` with this skill’s directory (e.g. the path shown by `openclaw skills status`).

**Current user (verify token):**

```bash
node {baseDir}/scripts/notion-cli.js me
```

**Search pages and data sources:**

```bash
node {baseDir}/scripts/notion-cli.js search "query text"
node {baseDir}/scripts/notion-cli.js search
```

**Get a page:**

```bash
node {baseDir}/scripts/notion-cli.js get-page <page_id>
```

**Get block children (page content):**

```bash
node {baseDir}/scripts/notion-cli.js get-blocks <block_id>
```

**Query a data source (database):**

```bash
node {baseDir}/scripts/notion-cli.js query <data_source_id>
node {baseDir}/scripts/notion-cli.js query <data_source_id> --filter '{"property":"Status","select":{"equals":"Done"}}' --page-size 50
```

**Create a page:**

```bash
node {baseDir}/scripts/notion-cli.js create-page database_id <database_id> --title "New page"
node {baseDir}/scripts/notion-cli.js create-page page_id <page_id> --title "Child page"
node {baseDir}/scripts/notion-cli.js create-page database_id <id> --properties '{"Name":{"title":[{"text":{"content":"Item"}}]},"Status":{"select":{"name":"Todo"}}}'
```

**Update page properties (PATCH page):**

```bash
node {baseDir}/scripts/notion-cli.js update-page <page_id> --properties '{"Status":{"select":{"name":"Done"}}}'
node {baseDir}/scripts/notion-cli.js update-page <page_id> --properties '{"Name":{"title":[{"text":{"content":"New title"}}]}}'
```

**Append blocks to a page:**

```bash
node {baseDir}/scripts/notion-cli.js append-blocks <block_id> --children '[{"object":"block","type":"paragraph","paragraph":{"rich_text":[{"text":{"content":"Hello"}}]}}]'
```

## IDs

- **Page ID / block ID:** UUID from the Notion URL (e.g. `notion.so/Page-Title-abc123def456` → `abc123def456`). Use with or without dashes.
- **Data source (database):** From search results (`object: "data_source"`) or database URL. Use `data_source_id` for `query`; use `database_id` for `create-page` parent.

## Notes

- The script loads `@notionhq/client` from `{baseDir}/node_modules`. Run `npm install --omit=dev` in `{baseDir}` before first use.
- Rate limit: ~3 requests/second; the SDK retries on 429/5xx with backoff.
- For property shapes (title, select, date, etc.) see the curl-based **notion** skill or [Notion API reference](https://developers.notion.com/reference).
