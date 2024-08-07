defmodule AshPagify.ValidationTest do
  @moduledoc false
  use ExUnit.Case, async: true

  import AshPagify.Factory

  alias Ash.Error.Query.InvalidFilterValue
  alias Ash.Error.Query.InvalidLimit
  alias Ash.Error.Query.InvalidOffset
  alias Ash.Error.Query.NoSuchField
  alias AshPagify.Error.Query.InvalidFilterFormParameter
  alias AshPagify.Error.Query.InvalidOrderByParameter
  alias AshPagify.Error.Query.InvalidScopesParameter
  alias AshPagify.Error.Query.InvalidSearchParameter
  alias AshPagify.Error.Query.NoSuchScope
  alias AshPagify.Factory.Comment
  alias AshPagify.Factory.Post
  alias AshPagify.Factory.User
  alias AshPagify.Misc
  alias AshPagify.Validation

  doctest AshPagify.Validation, import: true

  test "passes with empty params and resource" do
    assert {:ok, %AshPagify{limit: 15, offset: 0, scopes: %{status: :all}}} ==
             Validation.validate_params(Post, %{})
  end

  test "passes with empty params and query" do
    assert {:ok, %AshPagify{limit: 15, offset: 0, scopes: %{status: :all}}} ==
             Validation.validate_params(Ash.Query.new(Post), %{})
  end

  test "does not set limit if default_limit is set to false" do
    assert {:ok, %AshPagify{limit: nil, offset: 0}} =
             Validation.validate_params(Post, %{}, default_limit: false)
  end

  test "detects all errors and validates params" do
    {:error, errors, validated_params} =
      Validation.validate_params(
        Post,
        %{
          search: -1,
          scopes: -1,
          filter_form: -1,
          limit: -1,
          offset: -1,
          filters: 1,
          order_by: 1
        },
        replace_invalid_params?: true
      )

    assert [
             offset: [%InvalidOffset{offset: -1}],
             limit: [%InvalidLimit{limit: -1}],
             order_by: [%InvalidOrderByParameter{order_by: 1}],
             filters: [%InvalidFilterValue{value: 1}],
             filter_form: [%InvalidFilterFormParameter{filter_form: -1}],
             scopes: [%InvalidScopesParameter{scopes: -1}],
             search: [%InvalidSearchParameter{search: -1}]
           ] = errors

    assert %{
             limit: 15,
             offset: 0,
             filters: nil,
             order_by: nil,
             filter_form: nil,
             scopes: %{status: :all},
             search: nil
           } == validated_params
  end

  test "detects all errors and keeps original params" do
    params = %{
      search: -1,
      scopes: -1,
      filter_form: -1,
      limit: -1,
      offset: -1,
      filters: 1,
      order_by: 1
    }

    {:error, errors, original_params} =
      Validation.validate_params(Post, params)

    assert [
             offset: [%InvalidOffset{offset: -1}],
             limit: [%InvalidLimit{limit: -1}],
             order_by: [%InvalidOrderByParameter{order_by: 1}],
             filters: [%InvalidFilterValue{value: 1}],
             filter_form: [%InvalidFilterFormParameter{filter_form: -1}],
             scopes: [%InvalidScopesParameter{scopes: -1}],
             search: [%InvalidSearchParameter{search: -1}]
           ] = errors

    assert %{
             limit: -1,
             offset: -1,
             filters: 1,
             order_by: 1,
             filter_form: -1,
             scopes: -1,
             search: -1
           } == original_params
  end

  test "passes with string based map params" do
    assert {:ok,
            %AshPagify{
              limit: 15,
              offset: 0,
              order_by: [name: :asc],
              scopes: %{role: :admin, status: :all},
              filters: Ash.Query.filter_input(Post, %{author: "John"}).filter,
              filter_form: %{
                "components" => %{
                  "0" => %{
                    "field" => "name",
                    "negated?" => false,
                    "operator" => "eq",
                    "path" => "",
                    "value" => "Post 1"
                  }
                },
                "negated" => "false",
                "operator" => "or"
              },
              search: "Post 1"
            }} ==
             Validation.validate_params(
               Post,
               %{
                 "limit" => "15",
                 "offset" => "0",
                 "filters" => %{author: "John"},
                 "order_by" => "name",
                 "scopes" => %{"role" => "admin"},
                 "filter_form" => %{
                   "components" => %{
                     "0" => %{
                       "field" => "name",
                       "negated?" => false,
                       "operator" => "eq",
                       "path" => "",
                       "value" => "Post 1"
                     }
                   },
                   "negated" => "false",
                   "operator" => "or"
                 },
                 "search" => "Post 1"
               },
               full_text_search: :query
             )
  end

  describe "validate_search/2 for full_text_search" do
    test "passes with nil search" do
      assert %{search: nil} == Validation.validate_search(%{search: nil}, for: Post)
    end

    test "passes with empty string search" do
      assert %{search: ""} == Validation.validate_search(%{search: ""}, for: Post)
    end

    test "passes with no search" do
      assert %{} == Validation.validate_search(%{}, for: Post)
    end

    test "replaces invalid search type and adds error" do
      assert %{
               search: nil,
               errors: [
                 search: [%InvalidSearchParameter{search: 1}]
               ]
             } =
               Validation.validate_search(%{search: 1}, for: Post, replace_invalid_params?: true)
    end

    test "does not replace invalid search type and adds error" do
      assert %{
               search: 1,
               errors: [
                 search: [%InvalidSearchParameter{search: 1}]
               ]
             } =
               Validation.validate_search(%{search: 1}, for: Post)
    end

    test "allows full-text search if calculations are provided" do
      assert %{search: "Post 1"} ==
               Validation.validate_search(%{search: "Post 1"}, for: Post)
    end

    test "does not allow full-text search if calculations are not provided" do
      assert %{
               search: "User 1",
               errors: [
                 search: [%AshPagify.Error.Query.SearchNotImplemented{resource: User}]
               ]
             } =
               Validation.validate_search(%{search: "User 1"}, for: User)
    end
  end

  describe "validate_scopes/2" do
    test "passes with nil scopes" do
      assert %{scopes: nil} == Validation.validate_scopes(%{scopes: nil}, %{})
    end

    test "passes with no scopes" do
      assert %{} == Validation.validate_scopes(%{}, %{})
    end

    test "passes with empty map scopes" do
      assert %{scopes: nil} == Validation.validate_scopes(%{scopes: %{}}, %{})
    end

    test "passes with non-empty map scopes" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{scopes: %{role: :admin}} ==
               Validation.validate_scopes(%{scopes: %{role: :admin}}, scopes)
    end

    test "replaces invalid scope name and adds errors" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{
               scopes: nil,
               errors: [
                 scopes: [%NoSuchScope{group: :role, name: :invalid}]
               ]
             } =
               Validation.validate_scopes(
                 %{scopes: %{role: :invalid}},
                 scopes,
                 nil,
                 replace_invalid_params?: true
               )
    end

    test "does not replace invalid scope name and adds errors" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{
               scopes: %{role: :invalid},
               errors: [
                 scopes: [%NoSuchScope{group: :role, name: :invalid}]
               ]
             } =
               Validation.validate_scopes(%{scopes: %{role: :invalid}}, scopes)
    end

    test "replaces invalid scope group and adds errors" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{
               scopes: nil,
               errors: [
                 scopes: [%NoSuchScope{group: :invalid, name: :admin}]
               ]
             } =
               Validation.validate_scopes(%{scopes: %{invalid: :admin}}, scopes, nil, replace_invalid_params?: true)
    end

    test "does not replace invalid scope group and adds errors" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{
               scopes: %{invalid: :admin},
               errors: [
                 scopes: [%NoSuchScope{group: :invalid, name: :admin}]
               ]
             } =
               Validation.validate_scopes(%{scopes: %{invalid: :admin}}, scopes)
    end

    test "replaces invalid scopes parameter" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{
               scopes: nil,
               errors: [
                 scopes: [%InvalidScopesParameter{scopes: 1}]
               ]
             } =
               Validation.validate_scopes(%{scopes: 1}, scopes, nil, replace_invalid_params?: true)
    end

    test "does not replace invalid scopes parameter" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{
               scopes: 1,
               errors: [
                 scopes: [%InvalidScopesParameter{scopes: 1}]
               ]
             } =
               Validation.validate_scopes(%{scopes: 1}, scopes)
    end

    test "replaces invalid scope group and keeps valid scopes" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{
               scopes: %{role: :admin},
               errors: [
                 scopes: [%NoSuchScope{group: :invalid, name: :admin}]
               ]
             } =
               Validation.validate_scopes(
                 %{scopes: %{role: :admin, invalid: :admin}},
                 scopes,
                 nil,
                 replace_invalid_params?: true
               )
    end

    test "replaces invalid scope group and keeps valid scopes and loads default scopes" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{
               scopes: %{role: :user},
               errors: [
                 scopes: [%NoSuchScope{group: :invalid, name: :admin}]
               ]
             } =
               Validation.validate_scopes(
                 %{scopes: %{invalid: :admin}},
                 scopes,
                 %{role: :user},
                 replace_invalid_params?: true
               )
    end

    test "loads default scopes" do
      scopes = Misc.get_option(:scopes, for: Post)

      assert %{scopes: %{role: :user}} ==
               Validation.validate_scopes(%{}, scopes, %{role: :user})
    end
  end

  describe "validate_filter_form/2" do
    test "passes with nil filter_form" do
      params = Validation.validate_filter_form(%{filter_form: nil}, for: Post)
      assert %{filter_form: nil} == params
      refute Map.has_key?(params, :errors)
    end

    test "passes with no filter_form" do
      assert %{} == Validation.validate_filter_form(%{}, for: Post)
    end

    test "passes with empty map filter_form" do
      params = Validation.validate_filter_form(%{filter_form: %{}}, for: Post)
      assert %{filter_form: %{}} == params
      refute Map.has_key?(params, :errors)
    end

    test "passes with non-empty map filter_form" do
      filter_form_params = build(:form_filter_parameter)

      params = Validation.validate_filter_form(%{filter_form: filter_form_params}, for: Post)
      assert %{filter_form: ^filter_form_params} = params
      refute Map.has_key?(params, :errors)
    end

    test "passes with relational filter_form" do
      filter_form_params = build(:relational_filter_form_parameter)

      params = Validation.validate_filter_form(%{filter_form: filter_form_params}, for: Post)
      assert %{filter_form: ^filter_form_params} = params
      refute Map.has_key?(params, :errors)
    end

    test "passes with calculated filter_form" do
      filter_form_params = build(:calculated_filter_form_parameter)

      params = Validation.validate_filter_form(%{filter_form: filter_form_params}, for: Post)
      assert %{filter_form: ^filter_form_params} = params
      refute Map.has_key?(params, :errors)
    end

    test "replaces simple invalid filter_form fields and adds errors" do
      filter_form_params = build(:invalid_filter_form_parameter)

      assert %{
               :filter_form => %{},
               :errors => [filter_form: [field: {"No such field invalid_field", []}]]
             } =
               Validation.validate_filter_form(%{filter_form: filter_form_params},
                 for: Post,
                 replace_invalid_params?: true
               )
    end

    test "does not replace simple invalid filter_form fields and adds errors" do
      filter_form_params = build(:invalid_filter_form_parameter)

      assert %{
               :filter_form => ^filter_form_params,
               :errors => [filter_form: [field: {"No such field invalid_field", []}]]
             } =
               Validation.validate_filter_form(%{filter_form: filter_form_params}, for: Post)
    end

    test "replaces complex invalid filter_form and adds errors and keeps valid fields" do
      filter_form_params = build(:complex_invalid_filter_form_parameter)

      assert %{
               :filter_form => %{
                 "components" => %{
                   "0" => %{
                     "field" => :name,
                     "negated?" => false,
                     "operator" => :eq,
                     "path" => "",
                     "value" => "Post 1"
                   }
                 },
                 "negated" => "false",
                 "operator" => "or"
               },
               :errors => [filter_form: [field: {"No such field invalid_field", []}]]
             } =
               Validation.validate_filter_form(
                 %{filter_form: filter_form_params},
                 for: Post,
                 replace_invalid_params?: true
               )
    end
  end

  describe "validate_filters/2" do
    test "passes with nil filters" do
      assert %{filters: nil} == Validation.validate_filters(%{filters: nil}, for: Post)
    end

    test "passes with no filters" do
      assert %{} == Validation.validate_filters(%{}, for: Post)
    end

    test "passes with empty list filters" do
      assert %{filters: %Ash.Filter{}} = Validation.validate_filters(%{filters: []}, for: Post)
    end

    test "passes non-empty list filters" do
      assert %{filters: %Ash.Filter{}} =
               Validation.validate_filters(%{filters: [%{name: "Post 1"}]}, for: Post)
    end

    test "passes with empty map filters" do
      assert %{filters: %Ash.Filter{}} = Validation.validate_filters(%{filters: %{}}, for: Post)
    end

    test "passes with non-empty map filters" do
      assert %{filters: %Ash.Filter{}} =
               Validation.validate_filters(%{filters: %{name: "Post 1"}}, for: Post)
    end

    test "passes with relational filters" do
      assert %{filters: %Ash.Filter{}} =
               Validation.validate_filters(%{filters: %{comments: %{body: "Test"}}}, for: Post)
    end

    test "passes with calculated filters" do
      assert %{filters: %Ash.Filter{}} =
               Validation.validate_filters(%{filters: %{comments_count: %{gt: 1}}}, for: Post)
    end

    test "replaces simple invalid filters and adds errors" do
      assert %{:filters => nil, :errors => [filters: [%InvalidFilterValue{}]]} =
               Validation.validate_filters(%{filters: 1},
                 for: Post,
                 replace_invalid_params?: true
               )
    end

    test "does not replace simple invalid filters and adds errors" do
      assert %{:filters => 1, :errors => [filters: [%InvalidFilterValue{}]]} =
               Validation.validate_filters(%{filters: 1}, for: Post)
    end

    test "replaces complex invalid filters and adds errors" do
      assert %{
               :filters => nil,
               :errors => [
                 filters: [
                   %NoSuchField{},
                   %NoSuchField{}
                 ]
               ]
             } =
               Validation.validate_filters(
                 %{filters: %{and: [%{invalid_attribute_1: 1, invalid_attribute_2: 2}]}},
                 for: Post,
                 replace_invalid_params?: true
               )
    end

    test "replaces complex invalid filters and adds errors and keeps valid filters" do
      assert %{
               :filters => %Ash.Filter{},
               :errors => [
                 filters: [
                   %NoSuchField{},
                   %NoSuchField{}
                 ]
               ]
             } =
               Validation.validate_filters(
                 %{filters: %{name: "Post 1", invalid_attribute_1: 1, invalid_attribute_2: 2}},
                 for: Post,
                 replace_invalid_params?: true
               )
    end
  end

  describe "validate_order_by/2" do
    test "passes with nil order_by" do
      assert %{order_by: nil} == Validation.validate_order_by(%{order_by: nil}, for: Post)
    end

    test "passes with no order_by" do
      assert %{} == Validation.validate_order_by(%{}, for: Post)
    end

    test "passes with empty list order_by" do
      assert %{order_by: []} == Validation.validate_order_by(%{order_by: []}, for: Post)
    end

    test "passes with non-empty list order_by" do
      assert %{order_by: [name: :asc]} ==
               Validation.validate_order_by(%{order_by: ["name"]}, for: Post)
    end

    test "passes with single string" do
      assert %{order_by: [name: :asc]} ==
               Validation.validate_order_by(%{order_by: "name"}, for: Post)
    end

    test "passes with single string and direction" do
      assert %{order_by: [name: :desc]} =
               Validation.validate_order_by(%{order_by: "-name"}, for: Post)
    end

    test "passes with multiple strings" do
      assert %{order_by: [name: :asc, id: :desc]} ==
               Validation.validate_order_by(%{order_by: ["name", "-id"]}, for: Post)
    end

    test "passes with multiple strings and directions" do
      assert %{order_by: [name: :asc_nils_first, id: :desc_nils_last]} ==
               Validation.validate_order_by(%{order_by: "++name,--id"}, for: Post)
    end

    test "does not replace map order_by and adds errors" do
      assert %{
               order_by: %{name: :asc},
               errors: [
                 order_by: [
                   %InvalidOrderByParameter{}
                 ]
               ]
             } =
               Validation.validate_order_by(%{order_by: %{name: :asc}}, for: Post)
    end

    test "replaces map order_by and adds errors" do
      assert %{
               order_by: nil,
               errors: [
                 order_by: [%InvalidOrderByParameter{}]
               ]
             } =
               Validation.validate_order_by(%{order_by: %{name: :asc}},
                 for: Post,
                 replace_invalid_params?: true
               )
    end

    test "passes with calculated order_by" do
      assert %{order_by: [comments_count: :asc]} ==
               Validation.validate_order_by(%{order_by: "comments_count"}, for: Post)
    end

    test "replaces invalid order_by and adds errors" do
      assert %{
               order_by: [name: :desc_nils_last],
               errors: [
                 order_by: [
                   %NoSuchField{field: "non_existent", resource: Post}
                 ]
               ]
             } =
               Validation.validate_order_by(%{order_by: "--name,non_existent"},
                 for: Post,
                 replace_invalid_params?: true
               )
    end
  end

  describe "validate_pagination/2" do
    test "limit must be a positive integer" do
      params = %{limit: 0}

      assert %{
               limit: 0,
               errors: [limit: [%InvalidLimit{limit: 0}]]
             } = Validation.validate_pagination(params, for: Post)
    end

    test "limit must not be an empty string" do
      params = %{limit: ""}

      assert %{
               limit: "",
               errors: [limit: [%InvalidLimit{limit: ""}]]
             } = Validation.validate_pagination(params, for: Post)
    end

    test "limit must not contain non-number characters" do
      params = %{limit: "a"}

      assert %{
               limit: "a",
               errors: [limit: [%InvalidLimit{limit: "a"}]]
             } = Validation.validate_pagination(params, for: Post)
    end

    test "resets invalid limit to resource default_limit with replace_invalid_params?" do
      params = %{limit: 0}

      assert %{
               limit: 15,
               errors: [limit: [%InvalidLimit{limit: 0}]]
             } = Validation.validate_pagination(params, for: Post, replace_invalid_params?: true)
    end

    test "resets invalid limit to opts :default_limit with replace_invalid_params?" do
      params = %{limit: 0}

      assert %{
               limit: 10,
               errors: [limit: [%InvalidLimit{limit: 0}]]
             } =
               Validation.validate_pagination(params,
                 for: Comment,
                 replace_invalid_params?: true,
                 default_limit: 10
               )
    end

    test "resets invalid limit to AshPagify.default_limit() with replace_invalid_params?" do
      params = %{limit: 0}

      assert %{
               limit: 25,
               errors: [limit: [%InvalidLimit{limit: 0}]]
             } =
               Validation.validate_pagination(params, for: Comment, replace_invalid_params?: true)
    end

    test "offset must be a non-negative integer" do
      params = %{offset: -1}

      assert %{
               offset: -1,
               errors: [offset: [%InvalidOffset{offset: -1}]]
             } = Validation.validate_pagination(params, for: Post)
    end

    test "offset must not be an empty string" do
      params = %{offset: ""}

      assert %{
               offset: "",
               errors: [offset: [%InvalidOffset{offset: ""}]]
             } = Validation.validate_pagination(params, for: Post)
    end

    test "offset must not contain non-number characters" do
      params = %{offset: "a"}

      assert %{
               offset: "a",
               errors: [offset: [%InvalidOffset{offset: "a"}]]
             } = Validation.validate_pagination(params, for: Post)
    end

    test "replaces invalid offset with replace_invalid_params?" do
      params = %{offset: -1}

      assert %{
               offset: 0,
               errors: [offset: [%InvalidOffset{offset: -1}]]
             } = Validation.validate_pagination(params, for: Post, replace_invalid_params?: true)
    end

    test "validates max limit" do
      params = %{limit: 101}

      assert %{
               limit: 101,
               errors: [limit: [%InvalidLimit{limit: 101}]]
             } = Validation.validate_pagination(params, for: Post)
    end

    test "replaces invalid max limit with replace_invalid_params?" do
      params = %{limit: 101}

      assert %{
               limit: 15,
               errors: [limit: [%InvalidLimit{limit: 101}]]
             } = Validation.validate_pagination(params, for: Post, replace_invalid_params?: true)
    end

    test "replaces invalid max limit with opts :default_limit with replace_invalid_params?" do
      params = %{limit: 101}

      assert %{
               limit: 10,
               errors: [limit: [%InvalidLimit{limit: 101}]]
             } =
               Validation.validate_pagination(params,
                 for: Comment,
                 replace_invalid_params?: true,
                 default_limit: 10
               )
    end

    test "replaces invalid max limit with AshPagify.default_limit() with replace_invalid_params?" do
      params = %{limit: 101}

      assert %{
               limit: 25,
               errors: [limit: [%InvalidLimit{limit: 101}]]
             } =
               Validation.validate_pagination(params, for: Comment, replace_invalid_params?: true)
    end

    test "allows to overwrite max_limit with opts :max_limit" do
      params = %{limit: 101}

      assert %{limit: 101, offset: 0} ==
               Validation.validate_pagination(params,
                 for: Post,
                 replace_invalid_params?: true,
                 max_limit: 101
               )
    end

    test "does not set default limit if false" do
      params = %{}

      assert %{limit: 15} = Validation.validate_pagination(params, for: Post)

      assert %{limit: nil, offset: 0} ==
               Validation.validate_pagination(params,
                 for: Post,
                 replace_invalid_params?: true,
                 default_limit: false
               )
    end

    test "sets offset to 0 if limit is set without offset" do
      params = %{limit: 10}

      assert %{limit: 10, offset: 0} == Validation.validate_pagination(params, for: Post)
    end
  end
end
