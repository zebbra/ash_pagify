defmodule AshPagify.Factory do
  @moduledoc false

  use ExMachina

  alias AshPagify.Meta

  def meta_on_first_page_factory do
    %Meta{
      current_limit: 10,
      current_offset: 0,
      current_page: 1,
      has_next_page?: true,
      has_previous_page?: false,
      next_offset: 10,
      ash_pagify: %AshPagify{offset: 0, limit: 10},
      previous_offset: 0,
      total_count: 42,
      total_pages: 5
    }
  end

  def meta_on_second_page_factory do
    %Meta{
      current_limit: 10,
      current_offset: 10,
      current_page: 2,
      has_next_page?: true,
      has_previous_page?: true,
      next_offset: 20,
      ash_pagify: %AshPagify{offset: 10, limit: 10},
      previous_offset: 0,
      total_count: 42,
      total_pages: 5
    }
  end

  def meta_on_last_page_factory do
    %Meta{
      current_limit: 10,
      current_offset: 40,
      current_page: 5,
      has_next_page?: false,
      has_previous_page?: true,
      next_offset: nil,
      ash_pagify: %AshPagify{offset: 40, limit: 10},
      previous_offset: 30,
      total_count: 42,
      total_pages: 5
    }
  end

  def meta_one_page_factory do
    %Meta{
      current_limit: 10,
      current_offset: 0,
      current_page: 1,
      has_next_page?: false,
      has_previous_page?: false,
      next_offset: nil,
      ash_pagify: %AshPagify{offset: 0, limit: 10},
      previous_offset: 0,
      total_count: 6,
      total_pages: 1
    }
  end

  def meta_no_results_factory do
    %Meta{
      current_limit: 10,
      current_offset: 0,
      current_page: 1,
      has_next_page?: false,
      has_previous_page?: false,
      next_offset: nil,
      ash_pagify: %AshPagify{offset: 0, limit: 10},
      previous_offset: 0,
      total_count: 0,
      total_pages: 0
    }
  end

  def form_filter_parameter_factory do
    %{
      "components" => %{
        "0" => %{
          "arguments" => nil,
          "field" => "name",
          "negated" => false,
          "operator" => "eq",
          "path" => "",
          "value" => "Post 1"
        }
      },
      "negated" => "false",
      "operator" => "and"
    }
  end

  def relational_filter_form_parameter_factory do
    %{
      "components" => %{
        "0" => %{
          "arguments" => nil,
          "field" => "body",
          "negated" => false,
          "operator" => "eq",
          "path" => "comments",
          "value" => "Test"
        }
      },
      "negated" => "false",
      "operator" => "and"
    }
  end

  def calculated_filter_form_parameter_factory do
    %{
      "components" => %{
        "0" => %{
          "arguments" => nil,
          "field" => "comments_count",
          "negated" => false,
          "operator" => "gt",
          "path" => "",
          "value" => "20"
        }
      },
      "negated" => "false",
      "operator" => "and"
    }
  end

  def invalid_filter_form_parameter_factory do
    %{
      "components" => %{
        "0" => %{
          "arguments" => nil,
          "field" => "invalid_field",
          "negated" => false,
          "operator" => "eq",
          "path" => "",
          "value" => ""
        }
      },
      "negated" => "false",
      "operator" => "or"
    }
  end

  def complex_invalid_filter_form_parameter_factory do
    %{
      "components" => %{
        "0" => %{
          "arguments" => nil,
          "field" => "invalid_field",
          "negated" => false,
          "operator" => "eq",
          "path" => "",
          "value" => ""
        },
        "1" => %{
          "arguments" => nil,
          "field" => "name",
          "negated" => false,
          "operator" => "eq",
          "path" => "",
          "value" => "Post 1"
        }
      },
      "negated" => "false",
      "operator" => "or"
    }
  end

  def simple_empty_predicate_factory do
    %{
      field: "title",
      operator: "eq",
      value: ""
    }
  end

  def simple_predicate_factory do
    %{
      field: "title",
      operator: "eq",
      value: "Post 1"
    }
  end

  def simple_empty_filter_form_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :name,
          "negated?" => false,
          "operator" => :contains,
          "path" => "",
          "value" => ""
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end

  def simple_filter_form_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :name,
          "negated?" => false,
          "operator" => :contains,
          "path" => "",
          "value" => "John"
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end

  def simple_is_nil_filter_form_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :name,
          "negated?" => false,
          "operator" => :is_nil,
          "path" => "",
          "value" => ""
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end

  def nested_empty_filter_form_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :age,
          "negated?" => false,
          "operator" => :greater_than_or_equal,
          "path" => "",
          "value" => ""
        },
        "1" => %{
          "field" => :age,
          "negated?" => false,
          "operator" => :less_than_or_equal,
          "path" => "",
          "value" => ""
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end

  def nested_filter_form_with_one_value_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :age,
          "negated?" => false,
          "operator" => :greater_than_or_equal,
          "path" => "",
          "value" => "18"
        },
        "1" => %{
          "field" => :age,
          "negated?" => false,
          "operator" => :less_than_or_equal,
          "path" => "",
          "value" => ""
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end

  def nested_filter_form_with_one_is_nil_empty_value_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :age,
          "negated?" => false,
          "operator" => :is_nil,
          "path" => "",
          "value" => ""
        },
        "1" => %{
          "field" => :age,
          "negated?" => false,
          "operator" => :less_than_or_equal,
          "path" => "",
          "value" => ""
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end

  def mixed_empty_filter_form_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :name,
          "negated?" => false,
          "operator" => :contains,
          "path" => "",
          "value" => ""
        },
        "1" => %{
          "components" => %{
            "0" => %{
              "field" => :age,
              "negated?" => false,
              "operator" => :greater_than_or_equal,
              "path" => "",
              "value" => ""
            },
            "1" => %{
              "field" => :age,
              "negated?" => false,
              "operator" => :in,
              "path" => "",
              "value" => [""]
            }
          },
          "negated" => false,
          "operator" => "and"
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end

  def mixed_filter_form_with_empty_nested_form_but_non_empty_simple_value_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :name,
          "negated?" => false,
          "operator" => :contains,
          "path" => "",
          "value" => "John"
        },
        "1" => %{
          "components" => %{
            "0" => %{
              "field" => :age,
              "negated?" => false,
              "operator" => :greater_than_or_equal,
              "path" => "",
              "value" => ""
            },
            "1" => %{
              "field" => :age,
              "negated?" => false,
              "operator" => :less_than_or_equal,
              "path" => "",
              "value" => ""
            }
          },
          "negated" => false,
          "operator" => "and"
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end

  def mixed_filter_form_with_one_filled_nested_form_and_empty_simple_value_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :name,
          "negated?" => false,
          "operator" => :contains,
          "path" => "",
          "value" => ""
        },
        "1" => %{
          "components" => %{
            "0" => %{
              "field" => :age,
              "negated?" => false,
              "operator" => :greater_than_or_equal,
              "path" => "",
              "value" => "18"
            },
            "1" => %{
              "field" => :age,
              "negated?" => false,
              "operator" => :less_than_or_equal,
              "path" => "",
              "value" => ""
            }
          },
          "negated" => false,
          "operator" => "and"
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end

  def mixed_filter_form_with_one_is_nil_nested_form_and_empty_simple_value_factory do
    %{
      "components" => %{
        "0" => %{
          "field" => :name,
          "negated?" => false,
          "operator" => :contains,
          "path" => "",
          "value" => ""
        },
        "1" => %{
          "components" => %{
            "0" => %{
              "field" => :age,
              "negated?" => false,
              "operator" => :is_nil,
              "path" => "",
              "value" => ""
            },
            "1" => %{
              "field" => :age,
              "negated?" => false,
              "operator" => :less_than_or_equal,
              "path" => "",
              "value" => ""
            }
          },
          "negated" => false,
          "operator" => "and"
        }
      },
      "negated" => false,
      "operator" => "and"
    }
  end
end
