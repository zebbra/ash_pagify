![Elixir CI](https://github.com/zebbra/ash_pagify/workflows/AshPagify%20CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/ash_pagify.svg)](https://hex.pm/packages/ash_pagify)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/ash_pagify)

# AshPagify

Welcome! AshPagify adds full-text search, scoping, filtering, ordering, and pagination APIs for the [Ash Framework](https://hexdocs.pm/ash). Please refere to the documentation on [hexdocs](https://hexdocs.pm/ash_pagify) to get you started.

## Installation

```elixir
def deps do
  [
    {:ash_pagify, "~> 0.1.0"}
  ]
end
```

## Features

- **Full-text search**: AshPagify supports full-text search using the `tsvector` column in PostgreSQL.
- **Offset-based pagination**: AshPagify uses `OFFSET` and `LIMIT` to paginate your queries.
- **Scoping**: Apply predefined filters to your queries using a simple map syntax.
- **Filtering**: Apply user-input filters to your queries using a simple map syntax. Allows complex data filtering using multiple conditions, operators, and fields. Also incooperates with `AshPhoenix.FilterForm` to provide a simple way to build complex filter user interfaces.
- **Sorting**: Sort your queries by multiple fields and any directions.
- **UI helpers and URL builders**: AshPagify provides a `AshPagify.Meta` struct with information about the current page, total pages, and more. This information can be used to build pagination links in your UI. Further, `AshPagify` provides the `AshPagify.Components` module with headless table and pagination components to easily build sortable tables and pagination links in your Phoenix LiveView. The `AshPagify.FilterForm` module provides a simple way to build filter forms for your LiveView.

## Release Management

We use [git_opts](https://hexdocs.pm/git_ops/readme.html) to manage our releases. To create a new release, run:

```bash
mix git_ops.release
```

This will bump the version, create a new tag, and push the changes to the repository. The GitHub action will then build and publish the new version to Hex.
