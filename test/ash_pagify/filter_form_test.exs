defmodule AshPagify.FilterFormTest do
  @moduledoc false
  use ExUnit.Case

  import AshPagify.Factory
  import Phoenix.HTML.Form, only: [input_value: 2]

  alias AshPagify.Factory.Post
  alias AshPagify.FilterForm
  alias AshPhoenix.FilterForm.Predicate
  alias Plug.Conn.Query

  require Ash.Query

  doctest FilterForm, import: true

  defp form_for(thing, _) do
    Phoenix.HTML.FormData.to_form(thing, [])
  end

  defp inputs_for(form, key) do
    form[key].value
  end

  describe "new" do
    test "allows to initialize with initial form and deep merge with url encoded params" do
      initial_form =
        Post
        |> FilterForm.new()
        |> FilterForm.add_predicate(:title, :eq, nil)
        |> FilterForm.add_group(return_id?: true, key: "age_range_group")
        |> then(fn {form, id} ->
          form
          |> FilterForm.add_predicate(:age, :greater_than_or_equal, nil, to: id)
          |> FilterForm.add_predicate(:age, :less_than_or_equal, nil, to: id)
        end)

      # Sanity check
      initial_form_params =
        FilterForm.params_for_query(initial_form, nillify_blanks?: false, keep_keys?: true)

      assert initial_form_params == %{
               "components" => %{
                 "0" => %{
                   "field" => :title,
                   "negated?" => false,
                   "operator" => :eq,
                   "path" => "",
                   "value" => nil
                 },
                 "1" => %{
                   "components" => %{
                     "0" => %{
                       "field" => :age,
                       "negated?" => false,
                       "operator" => :greater_than_or_equal,
                       "path" => "",
                       "value" => nil
                     },
                     "1" => %{
                       "field" => :age,
                       "negated?" => false,
                       "operator" => :less_than_or_equal,
                       "path" => "",
                       "value" => nil
                     }
                   },
                   "key" => "age_range_group",
                   "negated" => false,
                   "operator" => "and"
                 }
               },
               "negated" => false,
               "operator" => "and"
             }

      params = %{
        "components" => %{
          "0" => %{
            "field" => "title",
            "operator" => "eq",
            "value" => "new post"
          },
          "1" => %{
            "components" => %{
              "0" => %{
                "field" => "age",
                "operator" => "greater_than_or_equal",
                "value" => "18"
              }
            },
            "operator" => "and"
          }
        },
        "operator" => "and"
      }

      form = FilterForm.new(Post, params: params, initial_form: initial_form)

      assert Enum.at(form.components, 0).value == "new post"
      assert Enum.at(form.components, 1).key == "age_range_group"
      assert Enum.at(Enum.at(form.components, 1).components, 0).value == "18"
      assert Enum.at(Enum.at(form.components, 1).components, 1).value == nil
    end
  end

  describe "groups" do
    test "a group can be added" do
      form = FilterForm.new(Post)

      {form, group_id} = FilterForm.add_group(form, operator: :or, return_id?: true)
      form = FilterForm.add_predicate(form, :title, :eq, "new post", to: group_id)

      assert %FilterForm{
               components: [
                 %FilterForm{
                   components: [
                     %Predicate{
                       field: :title,
                       operator: :eq,
                       value: "new post"
                     }
                   ]
                 }
               ]
             } = form
    end

    test "a group can be removed" do
      form = FilterForm.new(Post)

      {form, group_id} = FilterForm.add_group(form, operator: :or, return_id?: true)
      form = FilterForm.add_predicate(form, :title, :eq, "new post", to: group_id)

      form = FilterForm.remove_group(form, group_id)

      assert %FilterForm{
               components: []
             } = form
    end

    test "a predicate can be removed from a group" do
      form = FilterForm.new(Post)

      {form, group_id} = FilterForm.add_group(form, operator: :or, return_id?: true)

      {form, predicate_id} =
        FilterForm.add_predicate(form, :title, :eq, "new post", to: group_id, return_id?: true)

      form = FilterForm.remove_predicate(form, predicate_id)

      assert %FilterForm{
               components: [
                 %FilterForm{
                   components: []
                 }
               ]
             } = form
    end

    test "groups and predicates can be removed with remove_component" do
      form = FilterForm.new(Post)

      {form, group_id} = FilterForm.add_group(form, operator: :or, return_id?: true)

      {form, predicate_id} =
        FilterForm.add_predicate(form, :title, :eq, "new post", to: group_id, return_id?: true)

      form = FilterForm.remove_component(form, predicate_id)

      assert %FilterForm{
               components: [
                 %FilterForm{
                   components: []
                 }
               ]
             } = form

      form = FilterForm.remove_component(form, group_id)

      assert %FilterForm{
               components: []
             } = form
    end

    test "with `remove_empty_groups?: true` empty groups are removed on component removal" do
      form = FilterForm.new(Post, remove_empty_groups?: true)

      {form, group_id} = FilterForm.add_group(form, operator: :or, return_id?: true)

      {form, predicate_id} =
        FilterForm.add_predicate(form, :title, :eq, "new post", to: group_id, return_id?: true)

      form = FilterForm.remove_predicate(form, predicate_id)

      assert %FilterForm{components: []} = form
    end

    test "the form ids and names for deeply nested components are correct" do
      form =
        Post
        |> FilterForm.new()
        |> FilterForm.add_group(return_id?: true)
        |> then(fn {form, id} -> FilterForm.add_group(form, to: id, return_id?: true) end)
        |> then(fn {form, id} -> FilterForm.add_group(form, to: id, return_id?: true) end)
        |> then(fn {form, id} ->
          FilterForm.add_predicate(form, :title, :eq, "new_post", to: id)
        end)
        |> form_for("action")

      assert [group_form] = inputs_for(form, :components)

      assert group_form.id == group_form.source.id
      assert group_form.name == form.name <> "[components][0]"

      assert [sub_group_form] = inputs_for(group_form, :components)

      assert sub_group_form.id == sub_group_form.source.id
      assert sub_group_form.name == form.name <> "[components][0][components][0]"

      assert [predicate_form] = inputs_for(sub_group_form, :components)

      assert predicate_form.id == predicate_form.source.id
      assert predicate_form.name == form.name <> "[components][0][components][0][components][0]"
    end

    test "the form ids and names for deeply nested components are correct when initializing form from params" do
      params =
        Post
        |> FilterForm.new()
        |> FilterForm.add_group(return_id?: true)
        |> then(fn {form, id} -> FilterForm.add_group(form, to: id, return_id?: true) end)
        |> then(fn {form, id} -> FilterForm.add_group(form, to: id, return_id?: true) end)
        |> then(fn {form, id} ->
          FilterForm.add_predicate(form, :title, :eq, "new_post", to: id)
        end)
        |> FilterForm.params_for_query()

      form =
        Post
        |> FilterForm.new(params: params)
        |> form_for("action")

      assert [group_form] = inputs_for(form, :components)

      assert group_form.id == group_form.source.id
      assert group_form.name == form.name <> "[components][0]"

      assert [sub_group_form] = inputs_for(group_form, :components)

      assert sub_group_form.id == sub_group_form.source.id
      assert sub_group_form.name == form.name <> "[components][0][components][0]"

      assert [predicate_form] = inputs_for(sub_group_form, :components)

      assert predicate_form.id == predicate_form.source.id
      assert predicate_form.name == form.name <> "[components][0][components][0][components][0]"
    end

    test "key field can be added to nested groups" do
      form =
        Post
        |> FilterForm.new()
        |> FilterForm.add_group(return_id?: true, key: "name_group")
        |> then(fn {form, id} ->
          FilterForm.add_group(form, to: id, key: "age_group")
        end)

      assert Enum.at(form.components, 0).key == "name_group"
      assert Enum.at(Enum.at(form.components, 0).components, 0).key == "age_group"

      params = FilterForm.params_for_query(form, nillify_blanks?: false, keep_keys?: true)

      assert params == %{
               "components" => %{
                 "0" => %{
                   "components" => %{
                     "0" => %{"key" => "age_group", "negated" => false, "operator" => "and"}
                   },
                   "key" => "name_group",
                   "negated" => false,
                   "operator" => "and"
                 }
               },
               "negated" => false,
               "operator" => "and"
             }

      form =
        Post
        |> FilterForm.new(params: params)
        |> form_for("action")

      assert Enum.at(form.source.components, 0).key == "name_group"
      assert Enum.at(Enum.at(form.source.components, 0).components, 0).key == "age_group"

      assert [group_form] = inputs_for(form, :components)
      assert group_form.source.key == "name_group"

      assert [sub_group_form] = inputs_for(group_form, :components)
      assert sub_group_form.source.key == "age_group"
    end
  end

  describe "to_filter/1" do
    test "An empty form returns the filter `true`" do
      form = FilterForm.new(Post)

      assert FilterForm.to_filter_map(form) == {:ok, true}

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, form),
               true
             )
    end

    test "A form with a single predicate returns the corresponding filter" do
      form =
        FilterForm.new(Post,
          params: %{
            field: :title,
            value: "new post"
          }
        )

      assert FilterForm.to_filter_map(form) ==
               {:ok, %{"and" => [%{"title" => %{"eq" => "new post"}}]}}

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, form),
               title == "new post"
             )
    end

    test "the is_nil predicate correctly chooses the operator" do
      form =
        FilterForm.new(Post,
          params: %{
            field: :title,
            operator: :is_nil,
            value: "true"
          }
        )

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, form),
               is_nil(title)
             )

      form =
        FilterForm.new(Post,
          params: %{
            field: :title,
            operator: :is_nil,
            value: "false"
          }
        )

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, form),
               not is_nil(title)
             )
    end

    test "predicates that map to functions work as well" do
      form =
        FilterForm.new(Post,
          params: %{
            field: :title,
            operator: :contains,
            value: "new"
          }
        )

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, form),
               contains(title, "new")
             )
    end

    test "predicates can reference paths" do
      form =
        FilterForm.new(Post,
          params: %{
            field: :text,
            operator: :contains,
            path: "comments",
            value: "new"
          }
        )

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, form),
               contains(comments.text, "new")
             )
    end

    test "predicates can reference paths for to_filter_map" do
      form =
        FilterForm.new(Post,
          params: %{
            field: :text,
            operator: :eq,
            path: "comments",
            value: "new"
          }
        )

      assert {:ok, %{"and" => [%{"comments" => %{"text" => %{"eq" => "new"}}}]} = filter} =
               FilterForm.to_filter_map(form)

      assert Ash.Query.equivalent_to?(
               Ash.Query.filter(Post, ^Ash.Filter.parse!(Post, filter)),
               comments.text == "new"
             )
    end

    test "predicates with fields that refer to a relationship will be appended to the path" do
      form =
        FilterForm.new(Post,
          params: %{
            field: :comments,
            operator: :contains,
            path: "",
            value: "new"
          }
        )

      assert hd(form.components).path == [:comments]
      assert hd(form.components).field == :id
    end

    test "predicates can be added with paths" do
      form = FilterForm.new(Post)

      form =
        FilterForm.add_predicate(
          form,
          :text,
          :contains,
          "new",
          path: "comments"
        )

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, form),
               contains(comments.text, "new")
             )
    end

    test "predicates can be updated" do
      form = FilterForm.new(Post)

      {form, predicate_id} =
        FilterForm.add_predicate(
          form,
          :text,
          :contains,
          "new",
          path: "comments",
          return_id?: true
        )

      form =
        FilterForm.update_predicate(form, predicate_id, fn predicate ->
          %{predicate | path: []}
        end)

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, form),
               contains(text, "new")
             )
    end

    test "all predicates within a nested form can be updated" do
      form =
        Post
        |> FilterForm.new()
        |> FilterForm.add_group(return_id?: true, key: "age_range")
        |> then(fn {form, age_range_id} ->
          form
          |> FilterForm.add_predicate(:age, :equals, 20, to: age_range_id)
          |> FilterForm.add_predicate(:age, :not_equals, 30, to: age_range_id)
          |> FilterForm.add_group(
            return_id?: true,
            key: "nested_age_range",
            to: age_range_id
          )
          |> then(fn {form, nested_age_range_id} ->
            FilterForm.add_predicate(form, :age, :less_than, 40, to: nested_age_range_id)
          end)
        end)

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, form),
               age == 20 and age != 30 and age < 40
             )

      updated_form =
        FilterForm.update_group(form, "age_range", fn predicate ->
          case predicate.operator do
            :equals -> %{predicate | value: 10}
            :not_equals -> %{predicate | value: 20}
            _ -> %{predicate | value: 30}
          end
        end)

      assert Ash.Query.equivalent_to?(
               FilterForm.filter!(Post, updated_form),
               age == 10 and age != 20 and age < 30
             )
    end
  end

  describe "form_data implementation" do
    test "form_for works with a new filter form" do
      form = FilterForm.new(Post)

      form_for(form, "action")
    end

    test "form_for works with a single group" do
      form =
        FilterForm.new(Post,
          params: %{
            field: :title,
            value: "new post"
          }
        )

      form_for(form, "action")
    end

    test "the `:operator` and `:negated` inputs are available" do
      form =
        Post
        |> FilterForm.new(
          params: %{
            field: :title,
            value: "new post"
          }
        )
        |> form_for("action")

      assert input_value(form, :negated) == false
      assert input_value(form, :operator) == :and
    end

    test "the filter name can be overridden" do
      filter_form =
        FilterForm.new(Post,
          params: %{field: :field, operator: :contains, value: ""},
          as: "resource_filter"
        )

      assert filter_form.name == "resource_filter"
    end

    test "the `:components` are available as nested forms" do
      form =
        Post
        |> FilterForm.new(
          params: %{
            field: :title,
            value: "new post"
          }
        )
        |> form_for("action")

      assert [predicate_form] = inputs_for(form, :components)

      assert form.name == "filter"
      assert form.name == form.source.name
      assert form.id == form.source.id
      assert predicate_form.name == form.name <> "[components][0]"
      assert(input_value(predicate_form, :field) == :title)

      assert input_value(predicate_form, :value) == "new post"
      assert input_value(predicate_form, :operator) == :eq
      assert input_value(predicate_form, :negated) == false
    end

    test "the form ids and names for nested components are correct" do
      form =
        Post
        |> FilterForm.new(
          params: %{
            field: :title,
            value: "new post"
          }
        )
        |> form_for("action")

      assert [predicate_form] = inputs_for(form, :components)

      assert predicate_form.id == predicate_form.source.id
      assert predicate_form.name == form.name <> "[components][0]"
    end

    test "using an unknown operator shows an error" do
      assert [predicate_form] =
               Post
               |> FilterForm.new(
                 params: %{
                   field: :title,
                   operator: "what_on_earth",
                   value: "new post"
                 }
               )
               |> form_for("action")
               |> inputs_for(:components)

      assert [{:operator, {"No such operator what_on_earth", []}}] = predicate_form.errors
    end
  end

  describe "validate/1" do
    test "will update the forms accordingly" do
      form =
        FilterForm.new(Post, params: %{field: :title, value: "new post"})

      predicate = Enum.at(form.components, 0)

      form =
        FilterForm.validate(form, %{
          "components" => %{
            "0" => %{
              id: Map.get(predicate, :id),
              field: :title,
              value: "new post 2"
            }
          }
        })

      new_predicate = Enum.at(form.components, 0)

      assert %{
               predicate
               | value: "new post 2",
                 params: Map.put(predicate.params, "value", "new post 2")
             } == new_predicate
    end

    test "changing the field clears the value" do
      form =
        FilterForm.new(Post, params: %{field: :title, value: "new post"})

      predicate = Enum.at(form.components, 0)

      form =
        FilterForm.validate(form, %{
          "components" => %{
            "0" => %{
              id: Map.get(predicate, :id),
              field: :other,
              value: "new post"
            }
          }
        })

      assert is_nil(Enum.at(form.components, 0).value)
    end

    test "changing the field don't clears the value if reset_on_change? is false" do
      form =
        FilterForm.new(Post, params: %{field: :title, value: "new post"})

      predicate = Enum.at(form.components, 0)

      form =
        FilterForm.validate(
          form,
          %{
            "components" => %{
              "0" => %{
                id: Map.get(predicate, :id),
                field: :other,
                value: "new post"
              }
            }
          },
          reset_on_change?: false
        )

      assert Enum.at(form.components, 0).value
    end

    test "the form names for deeply nested components are correct" do
      form =
        Post
        |> FilterForm.new()
        |> FilterForm.add_group(return_id?: true)
        |> then(fn {form, id} -> FilterForm.add_group(form, to: id, return_id?: true) end)
        |> then(fn {form, id} -> FilterForm.add_group(form, to: id, return_id?: true) end)
        |> then(fn {form, id} ->
          FilterForm.add_predicate(form, :title, :eq, "new_post", to: id)
        end)

      original_form = form_for(form, "action")

      assert [group_form] = inputs_for(original_form, :components)
      assert group_form.name == form.name <> "[components][0]"
      assert [sub_group_form] = inputs_for(group_form, :components)
      assert sub_group_form.name == form.name <> "[components][0][components][0]"
      assert [predicate_form] = inputs_for(sub_group_form, :components)
      assert predicate_form.name == form.name <> "[components][0][components][0][components][0]"

      form =
        form
        |> FilterForm.validate(%{
          "id" => original_form.id,
          "components" => %{
            "0" => %{
              "id" => group_form.id,
              "components" => %{
                "0" => %{
                  "id" => sub_group_form.id,
                  "components" => %{
                    "0" => %{
                      "id" => predicate_form.id,
                      "field" => "title",
                      "value" => "new post"
                    }
                  }
                }
              }
            }
          }
        })
        |> form_for("action")

      assert [group_form] = inputs_for(form, :components)
      assert group_form.name == form.name <> "[components][0]"
      assert [sub_group_form] = inputs_for(group_form, :components)
      assert sub_group_form.name == form.name <> "[components][0][components][0]"
      assert [predicate_form] = inputs_for(sub_group_form, :components)
      assert predicate_form.name == form.name <> "[components][0][components][0][components][0]"
    end
  end

  describe "params_for_query/1" do
    test "can be query encoded, and then rebuilt" do
      form =
        FilterForm.new(Post, params: %{field: :title, value: "new post"})

      assert [predicate_form] =
               form
               |> form_for("action")
               |> inputs_for(:components)

      assert input_value(predicate_form, :field) == :title
      assert input_value(predicate_form, :value) == "new post"
      assert input_value(predicate_form, :operator) == :eq
      assert input_value(predicate_form, :negated) == false

      encoded =
        form
        |> FilterForm.params_for_query()
        |> Query.encode()

      decoded = Query.decode(encoded)

      assert [predicate_form] =
               Post
               |> FilterForm.new(params: decoded)
               |> form_for("action")
               |> inputs_for(:components)

      assert input_value(predicate_form, :field) == :title
      assert input_value(predicate_form, :value) == "new post"
      assert input_value(predicate_form, :operator) == :eq
      assert input_value(predicate_form, :negated) == false
    end

    test "removes simple empty predicate" do
      params = build(:simple_empty_predicate)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form) == %{}
    end

    test "does not remove simple empty predicate in case nillify_blanks? is set to false" do
      params = build(:simple_empty_predicate)
      form = FilterForm.new(Post, params: params)

      assert FilterForm.params_for_query(form, nillify_blanks?: false) == %{
               "components" => %{
                 "0" => %{
                   "field" => :title,
                   "negated?" => false,
                   "operator" => :eq,
                   "path" => "",
                   "value" => ""
                 }
               },
               "negated" => false,
               "operator" => "and"
             }
    end

    test "removes simple empty filter form" do
      params = build(:simple_empty_filter_form)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form) == %{}
    end

    test "removes simple empty filter form with or as base operator" do
      params = build(:simple_empty_filter_form, %{"operator" => "or"})
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form) == %{}
    end

    test "does not remove simple empty filter form in case nillify_blanks? is set to false" do
      params = build(:simple_empty_filter_form)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form, nillify_blanks?: false) == params
    end

    test "does not remove simple is_nil empty filter form" do
      params = build(:simple_is_nil_filter_form)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form) == params
    end

    test "removes nested empty filter form" do
      params = build(:nested_empty_filter_form)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form) == %{}
    end

    test "does not remove nested empty filter form in case nillify_blanks? is set to false" do
      params = build(:nested_empty_filter_form)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form, nillify_blanks?: false) == params
    end

    test "removes other empty value from nested filter form if one value is not empty" do
      params = build(:nested_filter_form_with_one_value)
      form = FilterForm.new(Post, params: params)

      assert FilterForm.params_for_query(form) == %{
               "components" => %{
                 "0" => %{
                   "field" => :age,
                   "negated?" => false,
                   "operator" => :greater_than_or_equal,
                   "path" => "",
                   "value" => "18"
                 }
               },
               "negated" => false,
               "operator" => "and"
             }
    end

    test "does not remove other empty value from nested filter form if one value is not empty in case nillify_blanks? is set to false" do
      params = build(:nested_filter_form_with_one_value)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form, nillify_blanks?: false) == params
    end

    test "removes other empty value from nested filter form if one value is empty but it is an is_nil operator" do
      params = build(:nested_filter_form_with_one_is_nil_empty_value)
      form = FilterForm.new(Post, params: params)

      assert FilterForm.params_for_query(form) == %{
               "components" => %{
                 "0" => %{
                   "field" => :age,
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

    test "does not remove other empty value from nested filter form if one value is empty but it is an is_nil operator in case nillify_blanks? is set to false" do
      params = build(:nested_filter_form_with_one_is_nil_empty_value)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form, nillify_blanks?: false) == params
    end

    test "removes mixed filter form values if all are empty" do
      params = build(:mixed_empty_filter_form)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form) == %{}
    end

    test "does not remove mixed filter form values if all are empty in case nillify_blanks? is set to false" do
      params = build(:mixed_empty_filter_form)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form, nillify_blanks?: false) == params
    end

    test "keeps simple non-empty value in mixed values when nested values are empty" do
      params = build(:mixed_filter_form_with_empty_nested_form_but_non_empty_simple_value)
      form = FilterForm.new(Post, params: params)

      assert FilterForm.params_for_query(form) == %{
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

    test "does not remove mixed filter form values simple value is no empty in case nillify_blanks? is set to false" do
      params = build(:mixed_filter_form_with_empty_nested_form_but_non_empty_simple_value)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form, nillify_blanks?: false) == params
    end

    test "keeps one nested filter if value is not empty but other nested fitler value and simple value of mixed form is emtpy" do
      params = build(:mixed_filter_form_with_one_filled_nested_form_and_empty_simple_value)
      form = FilterForm.new(Post, params: params)

      assert FilterForm.params_for_query(form) == %{
               "components" => %{
                 "1" => %{
                   "components" => %{
                     "0" => %{
                       "field" => :age,
                       "negated?" => false,
                       "operator" => :greater_than_or_equal,
                       "path" => "",
                       "value" => "18"
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

    test "keeps all filters if only one nested is not empty in mixed case if nillify_blanks? is set to false" do
      params = build(:mixed_filter_form_with_one_filled_nested_form_and_empty_simple_value)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form, nillify_blanks?: false) == params
    end

    test "keeps one nested filter if value is empty but operator is_nil and other nested fitler value and simple value of mixed form is emtpy" do
      params = build(:mixed_filter_form_with_one_is_nil_nested_form_and_empty_simple_value)
      form = FilterForm.new(Post, params: params)

      assert FilterForm.params_for_query(form) == %{
               "components" => %{
                 "1" => %{
                   "components" => %{
                     "0" => %{
                       "field" => :age,
                       "negated?" => false,
                       "operator" => :is_nil,
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

    test "keeps all filters if only one nested is empty but operator is is_nil in mixed case if nillify_blanks? is set to false" do
      params = build(:mixed_filter_form_with_one_is_nil_nested_form_and_empty_simple_value)
      form = FilterForm.new(Post, params: params)
      assert FilterForm.params_for_query(form, nillify_blanks?: false) == params
    end

    test "keeps the nested group key if set accordingly in opts" do
      params =
        Post
        |> FilterForm.new()
        |> FilterForm.add_group(return_id?: true, key: "name_group")
        |> then(fn {form, id} ->
          FilterForm.add_group(form, to: id, key: "age_group")
        end)
        |> FilterForm.params_for_query(nillify_blanks?: false, keep_keys?: true)

      assert params == %{
               "components" => %{
                 "0" => %{
                   "components" => %{
                     "0" => %{"key" => "age_group", "negated" => false, "operator" => "and"}
                   },
                   "key" => "name_group",
                   "negated" => false,
                   "operator" => "and"
                 }
               },
               "negated" => false,
               "operator" => "and"
             }
    end
  end

  describe "custom serializer" do
    test "apply custom serializer to the form" do
      params = build(:simple_empty_predicate)
      form = FilterForm.new(Post, params: params, serializer: &custom_serializer/2)

      assert FilterForm.params_for_query(form) == %{
               "components" => %{
                 "0" => %{
                   "field" => :title,
                   "negated?" => false,
                   "operator" => :eq,
                   "path" => "",
                   "value" => "test"
                 }
               },
               "negated" => false,
               "operator" => "and"
             }
    end
  end

  defp custom_serializer(_value, %{"field" => "title", "operator" => "eq"}) do
    "test"
  end

  defp custom_serializer(value, _params) do
    value
  end
end
