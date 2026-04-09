# Context7 MCP Server

Up-to-date, version-specific code documentation and examples for libraries directly in your prompt.

## Overview

Context7 fetches current documentation and code examples for libraries so your AI assistant doesn't hallucinate APIs that don't exist or generate code for deprecated versions.

## Requirements

- Node.js >= v18.0.0

## Configuration

This plugin automatically configures the Context7 MCP server:

```json
{
  "command": "npx",
  "args": ["-y", "@upstash/context7-mcp"]
}
```

### Optional: API Key

For higher rate limits, get a free API key at [context7.com/dashboard](https://context7.com/dashboard) and set the `CONTEXT7_API_KEY` environment variable.

## Resources

- [Website](https://context7.com)
- [GitHub](https://github.com/upstash/context7)
- [MCP Documentation](https://modelcontextprotocol.io)
