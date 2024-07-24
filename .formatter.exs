# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [
    :ash,
    :ash_phoenix,
    :ash_uuid
  ],
  plugins: [
    Spark.Formatter,
    Styler
  ]
]
