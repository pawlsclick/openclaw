#!/usr/bin/env node
"use strict";

/**
 * Notion SDK CLI for OpenClaw notion-sdk skill.
 * Uses @notionhq/client; requires NOTION_API_KEY or NOTION_TOKEN.
 * Output: JSON to stdout, errors to stderr, exit 1 on failure.
 */

const path = require("path");
const fs = require("fs");

// Resolve skill root (parent of scripts/) so we find this skill's node_modules
const scriptDir = path.resolve(__dirname);
const skillRoot = path.resolve(scriptDir, "..");
const nodeModules = path.join(skillRoot, "node_modules");
if (fs.existsSync(nodeModules)) {
  module.paths.unshift(nodeModules);
}

const { Client } = require("@notionhq/client");

const token = process.env.NOTION_API_KEY || process.env.NOTION_TOKEN;
if (!token) {
  console.error("notion-cli: set NOTION_API_KEY or NOTION_TOKEN");
  process.exit(1);
}

const notion = new Client({ auth: token });

function out(obj) {
  console.log(JSON.stringify(obj));
}

function err(msg) {
  console.error("notion-cli:", msg);
}

function usage() {
  err(
    "Usage: notion-cli.js <cmd> [args...]\n" +
      "  me\n" +
      "  search [query]\n" +
      "  get-page <page_id>\n" +
      "  get-blocks <block_id>\n" +
      "  query <data_source_id> [--filter JSON] [--sorts JSON] [--page-size N]\n" +
      "  create-page <parent_type> <parent_id> [--properties JSON] [--title TITLE]\n" +
      "  update-page <page_id> --properties JSON\n" +
      "  append-blocks <block_id> [--children JSON]"
  );
}

async function run() {
  const args = process.argv.slice(2);
  const cmd = args[0];
  if (!cmd || cmd === "-h" || cmd === "--help") {
    usage();
    process.exit(2);
  }

  try {
    switch (cmd) {
      case "me": {
        const user = await notion.users.me();
        out(user);
        break;
      }
      case "search": {
        const query = args[1] || "";
        const body = query ? { query } : {};
        const resp = await notion.search(body);
        out(resp);
        break;
      }
      case "get-page": {
        const pageId = args[1];
        if (!pageId) {
          err("get-page requires <page_id>");
          process.exit(2);
        }
        const page = await notion.pages.retrieve({ page_id: pageId });
        out(page);
        break;
      }
      case "get-blocks": {
        const blockId = args[1];
        if (!blockId) {
          err("get-blocks requires <block_id>");
          process.exit(2);
        }
        const resp = await notion.blocks.children.list({
          block_id: blockId,
          page_size: 100,
        });
        out(resp);
        break;
      }
      case "query": {
        const dataSourceId = args[1];
        if (!dataSourceId) {
          err("query requires <data_source_id>");
          process.exit(2);
        }
        let filterJson = null;
        let sortsJson = null;
        let pageSize = 100;
        for (let i = 2; i < args.length; i++) {
          if (args[i] === "--filter" && args[i + 1]) {
            filterJson = args[++i];
          } else if (args[i] === "--sorts" && args[i + 1]) {
            sortsJson = args[++i];
          } else if (args[i] === "--page-size" && args[i + 1]) {
            pageSize = parseInt(args[++i], 10) || 100;
          }
        }
        const body = {
          data_source_id: dataSourceId,
          page_size: pageSize,
        };
        if (filterJson) body.filter = JSON.parse(filterJson);
        if (sortsJson) body.sorts = JSON.parse(sortsJson);
        const resp = await notion.dataSources.query(body);
        out(resp);
        break;
      }
      case "create-page": {
        const parentType = args[1];
        const parentId = args[2];
        if (!parentType || !parentId) {
          err("create-page requires <parent_type> <parent_id> (e.g. database_id <uuid>)");
          process.exit(2);
        }
        let propertiesJson = null;
        let title = null;
        for (let i = 3; i < args.length; i++) {
          if (args[i] === "--properties" && args[i + 1]) {
            propertiesJson = args[++i];
          } else if (args[i] === "--title" && args[i + 1]) {
            title = args[++i];
          }
        }
        const parentKey =
          parentType === "page_id"
            ? "page_id"
            : parentType === "database_id"
              ? "database_id"
              : "database_id";
        const parent = { [parentKey]: parentId };
        const properties = propertiesJson
          ? JSON.parse(propertiesJson)
          : title
            ? { title: [{ text: { content: title } }] }
            : { title: [{ text: { content: "Untitled" } }] };
        const resp = await notion.pages.create({ parent, properties });
        out(resp);
        break;
      }
      case "update-page": {
        const pageId = args[1];
        if (!pageId) {
          err("update-page requires <page_id>");
          process.exit(2);
        }
        let propertiesJson = null;
        for (let i = 2; i < args.length; i++) {
          if (args[i] === "--properties" && args[i + 1]) {
            propertiesJson = args[++i];
            break;
          }
        }
        if (!propertiesJson) {
          err("update-page requires --properties JSON");
          process.exit(2);
        }
        const properties = JSON.parse(propertiesJson);
        const resp = await notion.pages.update({ page_id: pageId, properties });
        out(resp);
        break;
      }
      case "append-blocks": {
        const blockId = args[1];
        if (!blockId) {
          err("append-blocks requires <block_id>");
          process.exit(2);
        }
        let childrenJson = args[2];
        for (let i = 2; i < args.length; i++) {
          if (args[i] === "--children" && args[i + 1]) {
            childrenJson = args[++i];
            break;
          }
        }
        if (!childrenJson) {
          err("append-blocks requires --children JSON or positional JSON array");
          process.exit(2);
        }
        const children = JSON.parse(childrenJson);
        const resp = await notion.blocks.children.append({
          block_id: blockId,
          children: Array.isArray(children) ? children : [children],
        });
        out(resp);
        break;
      }
      default:
        err("Unknown command: " + cmd);
        usage();
        process.exit(2);
    }
  } catch (e) {
    err(e.message || String(e));
    if (e.body) {
      try {
        err(JSON.stringify(e.body));
      } catch (_) {}
    }
    process.exit(1);
  }
}

run();
