# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [
    :ash,
    :ash_phoenix,
    :ash_uuid,
    :phoenix
  ],
  plugins: [
    Phoenix.LiveView.HTMLFormatter,
    Spark.Formatter,
    Styler
  ]
]
