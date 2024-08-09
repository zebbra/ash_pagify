defmodule AshPagify.FilterForm do
  @moduledoc """
  A module to help you create complex forms that generate Ash filters.

  > #### Disclaimer {: .info}
  >
  > This is a copy of the `AshPhoenix.FilterForm` module from the `ash_phoenix` package.
  > We made some changes such as `nillify_blanks?` option in `params_for_query/2` function.
  > Further we fixed the issue with the duplicated [components][index] suffix in case
  > you restore the form from the params. Additonal you can now provide an `initial_form`
  > to `AshPagify.FilterForm.new/2` to enforce a specific structure for the form and then merge
  > in the params.

  ```elixir
  # Create a FilterForm
  filter_form = AshPagify.FilterForm.new(MyApp.Payroll.Employee)
  ```

  FilterForm's comprise two concepts, predicates and groups. Predicates are the simple boolean
  expressions you can use to build a query (`name == "Joe"`), and groups can be used to group
  predicates and more groups together. Groups can apply `and` or `or` operators to its nested
  components.

  ```elixir
  # Add a predicate to the root of the form (which is itself a group)
  filter_form = AshPagify.FilterForm.add_predicate(filter_form, :some_field, :eq, "Some Value")

  # Add a group and another predicate to that group
  {filter_form, group_id} = AshPagify.FilterForm.add_group(filter_form, operator: :or, return_id?: true)
  filter_form = AshPagify.FilterForm.add_predicate(filter_form, :another, :eq, "Other", to: group_id)
  ```

  `validate/1` is used to merge the submitted form params into the filter form, and one of the
  provided filter functions to apply the filter as a query, or generate an expression map,
  depending on your requirements:

  ```elixir
  filter_form = AshPagify.FilterForm.validate(socket.assigns.filter_form, params)

  # Generate a query and pass it to the Domain
  query = AshPagify.FilterForm.filter!(MyApp.Payroll.Employee, filter_form)
  filtered_employees = MyApp.Payroll.read!(query)

  # Or use one of the other filter functions
  AshPagify.FilterForm.to_filter_expression(filter_form)
  AshPagify.FilterForm.to_filter_map(filter_form)
  ```

  ## LiveView Example

  You can build a form and handle adding and removing nested groups and predicates with the following:

  ```elixir
  alias MyApp.Payroll.Employee

  @impl true
  def render(assigns) do
    ~H\"\"\"
    <.simple_form
      :let={filter_form}
      for={@filter_form}
      phx-change="filter_validate"
      phx-submit="filter_submit"
    >
      <.filter_form_component component={filter_form} />
      <:actions>
        <.button>Submit</.button>
      </:actions>
    </.simple_form>
    <.table id="employees" rows={@employees}>
      <:col :let={employee} label="Payroll ID"><%= employee.employee_id %></:col>
      <:col :let={employee} label="Name"><%= employee.name %></:col>
      <:col :let={employee} label="Position"><%= employee.position %></:col>
    </.table>
    \"\"\"
  end

  attr :component, :map, required: true, doc: "Could be a FilterForm (group) or a Predicate"

  defp filter_form_component(%{component: %{source: %AshPagify.FilterForm{}}} = assigns) do
    ~H\"\"\"
    <div class="border-gray-50 border-8 p-4 rounded-xl mt-4">
      <div class="flex flex-row justify-between">
        <div class="flex flex-row gap-2 items-center">Filter</div>
        <div class="flex flex-row gap-2 items-center">
          <.input type="select" field={@component[:operator]} options={["and", "or"]} />
          <.button phx-click="add_filter_group" phx-value-component-id={@component.source.id} type="button">
            Add Group
          </.button>
          <.button
            phx-click="add_filter_predicate"
            phx-value-component-id={@component.source.id}
            type="button"
          >
            Add Predicate
          </.button>
          <.button
            phx-click="remove_filter_component"
            phx-value-component-id={@component.source.id}
            type="button"
          >
            Remove Group
          </.button>
        </div>
      </div>
      <.inputs_for :let={component} field={@component[:components]}>
        <.filter_form_component component={component} />
      </.inputs_for>
    </div>
    \"\"\"
  end

  defp filter_form_component(
         %{component: %{source: %AshPhoenix.FilterForm.Predicate{}}} = assigns
       ) do
    ~H\"\"\"
    <div class="flex flex-row gap-2 mt-4">
      <.input
        type="select"
        options={AshPagify.FilterForm.fields(Employee)}
        field={@component[:field]}
      />
      <.input
        type="select"
        options={AshPagify.FilterForm.predicates(Employee)}
        field={@component[:operator]}
      />
      <.input field={@component[:value]} />
      <.button
        phx-click="remove_filter_component"
        phx-value-component-id={@component.source.id}
        type="button"
      >
        Remove
      </.button>
    </div>
    \"\"\"
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:filter_form, AshPagify.FilterForm.new(Employee))
      |> assign(:employees, Employee.read_all!())

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_validate", %{"filter" => params}, socket) do
    {:noreply,
     assign(socket,
       filter_form: AshPagify.FilterForm.validate(socket.assigns.filter_form, params)
     )}
  end

  @impl true
  def handle_event("filter_submit", %{"filter" => params}, socket) do
    filter_form = AshPagify.FilterForm.validate(socket.assigns.filter_form, params)

    case AshPagify.FilterForm.filter(Employee, filter_form) do
      {:ok, query} ->
        {:noreply,
         socket
         |> assign(:employees, Employee.read_all!(query: query))
         |> assign(:filter_form, filter_form)}

      {:error, filter_form} ->
        {:noreply, assign(socket, filter_form: filter_form)}
    end
  end

  @impl true
  def handle_event("remove_filter_component", %{"component-id" => component_id}, socket) do
    {:noreply,
     assign(socket,
       filter_form:
         AshPagify.FilterForm.remove_component(socket.assigns.filter_form, component_id)
     )}
  end

  @impl true
  def handle_event("add_filter_group", %{"component-id" => component_id}, socket) do
    {:noreply,
     assign(socket,
       filter_form: AshPagify.FilterForm.add_group(socket.assigns.filter_form, to: component_id)
     )}
  end

  @impl true
  def handle_event("add_filter_predicate", %{"component-id" => component_id}, socket) do
    {:noreply,
     assign(socket,
       filter_form:
         AshPagify.FilterForm.add_predicate(socket.assigns.filter_form, :name, :contains, nil,
           to: component_id
         )
     )}
  end
  ```
  """

  alias Ash.Query
  alias Ash.Resource
  alias AshPagify.Meta
  alias AshPagify.Misc
  alias AshPhoenix.FilterForm.Arguments
  alias AshPhoenix.FilterForm.Predicate

  require Ash.Expr

  defstruct [
    :id,
    :resource,
    :transform_errors,
    :key,
    name: "filter",
    valid?: false,
    negated?: false,
    params: %{},
    components: [],
    operator: :and,
    remove_empty_groups?: false,
    serializer: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          resource: Resource.t(),
          transform_errors: term(),
          key: term(),
          name: String.t(),
          valid?: boolean(),
          negated?: boolean(),
          params: map(),
          components: [term() | t()],
          operator: :and | :or,
          remove_empty_groups?: boolean(),
          serializer: (term() -> term()) | nil
        }

  @new_opts [
    params: [
      type: :any,
      doc: "Initial parameters to create the form with",
      default: %{}
    ],
    as: [
      type: :string,
      default: "filter",
      doc: "Set the parameter name for the form."
    ],
    key: [
      type: :any,
      default: nil,
      doc: "Set the parameter key for the form."
    ],
    transform_errors: [
      type: :any,
      doc: """
      Allows for manual manipulation and transformation of errors.

      If possible, try to implement `AshPhoenix.FormData.Error` for the error (if it as a custom one, for example).
      If that isn't possible, you can provide this function which will get the predicate and the error, and should
      return a list of ash phoenix formatted errors, e.g `[{field :: atom, message :: String.t(), substituations :: Keyword.t()}]`
      """
    ],
    remove_empty_groups?: [
      type: :boolean,
      doc: """
      If true (the default), then any time a group would be made empty by removing a group or predicate, it is removed instead.

      An empty form can still be added, this only affects a group if its last component is removed.
      """,
      default: false
    ],
    root?: [
      type: :boolean,
      doc: """
      If true (the default), the form's name will not be suffixed with [components][index] when adding / validating components.

      This flag is used internally and should not be set manually.
      """,
      default: true
    ],
    initial_form: [
      type: :any,
      doc: """
      The initial form to use when creating a new form.

      This is usefully if you want to enforce a specific structure for the form and then merge in the params.
      """
    ],
    serializer: [
      type: :any,
      default: nil,
      doc: """
      A function that will be called on the predicate param during new predicate initialization.

      This is useful for custom serialization of the form input values.
      """
    ]
  ]

  @doc """
  Create a new filter form.

  Options:
  #{Spark.Options.docs(@new_opts)}
  """
  def new(resource, opts \\ []) do
    opts = Spark.Options.validate!(opts, @new_opts)
    params = opts[:params]

    params =
      case opts[:initial_form] do
        %__MODULE__{} = form ->
          initial_params = params_for_query(form, nillify_blanks?: false, keep_keys?: true)
          Misc.map_merge(initial_params, params || %{})

        _ ->
          params
      end

    params = sanitize_params(params)

    params =
      if predicate?(params) do
        %{
          "operator" => "and",
          "id" => Ash.UUID.generate(),
          "components" => %{"0" => params}
        }
      else
        params
      end

    form = %__MODULE__{
      id: params["id"],
      name: opts[:as] || "filter",
      key: opts[:key],
      resource: resource,
      params: params,
      remove_empty_groups?: opts[:remove_empty_groups?],
      operator: to_existing_atom(params["operator"] || :and),
      serializer: opts[:serializer]
    }

    set_validity(%{
      form
      | components:
          parse_components(form, params["components"],
            remove_empty_groups?: opts[:remove_empty_groups?],
            root?: opts[:root?]
          )
    })
  end

  @doc """
  Updates the filter with the provided input and validates it.

  At present, no validation actually occurs, but this will eventually be added.

  Passing `reset_on_change?: false` into `opts` will prevent predicates to reset
  the `value` and `operator` fields to `nil` if the predicate `field` changes.
  """
  def validate(form, params \\ %{}, opts \\ [root?: true]) do
    params = sanitize_params(params)

    params =
      if predicate?(params) do
        %{
          "operator" => "and",
          "id" => Ash.UUID.generate(),
          "components" => %{"0" => params}
        }
      else
        params
      end

    set_validity(%{
      form
      | params: params,
        components: validate_components(form, params["components"], opts),
        operator: to_existing_atom(params["operator"] || :and),
        negated?: params["negated"] || false
    })
  end

  @doc """
  Returns a filter map that can be provided to `Ash.Filter.parse`

  This allows for things like saving a stored filter. Does not currently support parameterizing calculations or functions.
  """
  def to_filter_map(form) do
    if form.valid? do
      case do_to_filter_map(form, form.resource) do
        {:ok, expr} ->
          {:ok, expr}

        {:error, %__MODULE__{} = form} ->
          {:error, form}
      end
    else
      {:error, form}
    end
  end

  defp do_to_filter_map(%__MODULE__{components: []}, _), do: {:ok, true}

  defp do_to_filter_map(%__MODULE__{components: components, operator: operator, negated?: negated?} = form, resource) do
    {filters, components, errors?} =
      Enum.reduce(components, {[], [], false}, fn component, {filters, components, errors?} ->
        case do_to_filter_map(component, resource) do
          {:ok, component_filter} ->
            {filters ++ [component_filter], components ++ [component], errors?}

          {:error, component} ->
            {filters, components ++ [component], true}
        end
      end)

    if errors? do
      {:error, %{form | components: components}}
    else
      expr = %{to_string(operator) => filters}

      if negated? do
        {:ok, %{"not" => expr}}
      else
        {:ok, expr}
      end
    end
  end

  defp do_to_filter_map(
         %Predicate{field: field, value: value, operator: operator, negated?: negated?, path: path},
         _resource
       ) do
    expr =
      put_at_path(%{}, Enum.map(path, &to_string/1), %{
        to_string(field) => %{to_string(operator) => value}
      })

    if negated? do
      {:ok, %{"not" => expr}}
    else
      {:ok, expr}
    end
  end

  defp put_at_path(_, [], value), do: value

  defp put_at_path(map, [key], value) do
    Map.put(map || %{}, key, value)
  end

  defp put_at_path(map, [key | rest], value) do
    map
    |> Kernel.||(%{})
    |> Map.put_new(key, %{})
    |> Map.update!(key, &put_at_path(&1, rest, value))
  end

  @doc """
  Returns a filter expression that can be provided to Ash.Query.filter/2

  To add this to a query, remember to use `^`, for example:
  ```elixir
  filter = AshPagify.FilterForm.to_filter_expression(form)

  Ash.Query.filter(MyApp.Post, ^filter)
  ```

  Alternatively, you can use the shorthand: `filter/2` to apply the expression directly to a query.
  """
  def to_filter_expression(form) do
    if form.valid? do
      case do_to_filter_expression(form, form.resource) do
        {:ok, expr} ->
          {:ok, expr}

        {:error, %__MODULE__{} = form} ->
          {:error, form}

        {:error, error} ->
          {:error, %{form | errors: List.wrap(error)}}
      end
    else
      {:error, form}
    end
  end

  @doc """
  Same as `to_filter_expression/1` but raises on errors.
  """
  def to_filter_expression!(form) do
    case to_filter_expression(form) do
      {:ok, filter} ->
        filter

      {:error, %__MODULE__{} = form} ->
        error =
          form
          |> errors()
          |> Enum.map(fn
            {key, message, vars} ->
              "#{key}: #{AshPhoenix.replace_vars(message, vars)}"

            other ->
              other
          end)
          |> Ash.Error.to_error_class()

        raise error

      {:error, error} ->
        raise Ash.Error.to_error_class(error)
    end
  end

  @deprecated "Use to_filter_expression!/1 instead"
  def to_filter!(form), do: to_filter_expression!(form)

  @doc """
  Returns a flat list of all errors on all predicates in the filter.
  """
  def errors(form, opts \\ [])

  def errors(%__MODULE__{components: components, transform_errors: transform_errors}, opts) do
    Enum.flat_map(
      components,
      &errors(&1, Keyword.put_new(opts, :handle_errors, transform_errors))
    )
  end

  def errors(%Predicate{} = predicate, opts), do: Predicate.errors(predicate, opts[:transform_errors])

  defp do_to_filter_expression(%__MODULE__{components: []}, _), do: {:ok, true}

  defp do_to_filter_expression(
         %__MODULE__{components: components, operator: operator, negated?: negated?} = form,
         resource
       ) do
    {filters, components, errors?} =
      Enum.reduce(components, {[], [], false}, fn component, {filters, components, errors?} ->
        case do_to_filter_expression(component, resource) do
          {:ok, component_filter} ->
            {filters ++ [component_filter], components ++ [component], errors?}

          {:error, component} ->
            {filters, components ++ [component], true}
        end
      end)

    if errors? do
      {:error, %{form | components: components}}
    else
      expr = filters_expression(filters, operator)

      if negated? do
        {:ok, Query.Not.new(expr)}
      else
        {:ok, expr}
      end
    end
  end

  defp do_to_filter_expression(%Predicate{} = predicate, resource) do
    %Predicate{
      field: field,
      value: value,
      arguments: arguments,
      operator: operator,
      negated?: negated?,
      path: path
    } = predicate

    ref = resource_ref(resource, path, field, arguments)

    case ref do
      {:ok, ref} ->
        expr = ref_expression(operator, ref, value, resource)

        case expr do
          {:ok, expr} ->
            maybe_negate_expression(expr, negated?)

          {:error, error} ->
            {:error, %{predicate | errors: predicate.errors ++ [error]}}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp filters_expression(filters, operator) do
    Enum.reduce(filters, nil, fn component_as_filter, acc ->
      if acc do
        Query.BooleanExpression.new(operator, acc, component_as_filter)
      else
        component_as_filter
      end
    end)
  end

  defp resource_ref(resource, path, field, arguments) do
    case Resource.Info.public_calculation(Resource.Info.related(resource, path), field) do
      nil ->
        {:ok, Ash.Expr.expr(^Ash.Expr.ref(List.wrap(path), field))}

      calc ->
        case Query.validate_calculation_arguments(
               calc,
               arguments.input || %{}
             ) do
          {:ok, input} ->
            {:ok,
             %Query.Call{
               name: calc.name,
               args: [Map.to_list(input)],
               relationship_path: path
             }}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp ref_expression(operator, ref, value, resource) do
    if Ash.Filter.get_operator(operator) do
      {:ok, %Query.Call{name: operator, args: [ref, value], operator?: true}}
    else
      if Ash.Filter.get_function(operator, resource, true) do
        {:ok, %Query.Call{name: operator, args: [ref, value]}}
      else
        {:error, {:operator, "No such function or operator #{operator}", []}}
      end
    end
  end

  defp maybe_negate_expression(expr, negated?) do
    if negated? do
      {:ok, Query.Not.new(expr)}
    else
      {:ok, expr}
    end
  end

  @doc """
  Converts the form into a filter, and filters the provided query or resource with that filter.
  """
  def filter(query, form) do
    case to_filter_expression(form) do
      {:ok, filter} ->
        {:ok, Query.do_filter(query, filter)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Same as `filter/2` but raises on errors.
  """
  def filter!(query, form) do
    Query.do_filter(query, to_filter_expression!(form))
  end

  defp sanitize_params(params) do
    if predicate?(params) do
      sanitize_predicate(params)
    else
      sanitize_components(params)
    end
  end

  defp sanitize_predicate(params) do
    field = coalesce_field(params)
    path = coalesce_path(params)

    %{
      "id" => params[:id] || params["id"] || Ash.UUID.generate(),
      "operator" => to_string(params[:operator] || params["operator"] || "eq"),
      "negated" => params[:negated] || params["negated"] || false,
      "arguments" => params["arguments"],
      "field" => field,
      "value" => params[:value] || params["value"],
      "path" => path
    }
  end

  defp sanitize_components(params) do
    components = coalesce_components(params)

    %{
      "id" => params[:id] || params["id"] || Ash.UUID.generate(),
      "operator" => to_string(params[:operator] || params["operator"] || "and"),
      "negated" => params[:negated] || params["negated"] || false,
      "components" => components || %{},
      "key" => params[:key] || params["key"]
    }
  end

  defp coalesce_field(params) do
    case params[:field] || params["field"] do
      nil -> nil
      field -> to_string(field)
    end
  end

  defp coalesce_path(params) do
    case params[:path] || params["path"] do
      nil -> nil
      path when is_list(path) -> Enum.join(path, ".")
      path when is_binary(path) -> path
    end
  end

  defp coalesce_components(params) do
    components = params[:components] || params["components"] || []

    if is_list(components) do
      components
      |> Enum.with_index()
      |> Map.new(fn {value, index} ->
        {to_string(index), value}
      end)
    else
      components_map(components)
    end
  end

  defp components_map(components) do
    if is_map(components) do
      Map.new(components, fn {key, value} ->
        {key, sanitize_params(value)}
      end)
    end
  end

  defp parse_components(parent, component_params, form_opts) do
    component_params
    |> Kernel.||(%{})
    |> Enum.sort_by(fn {key, _value} ->
      String.to_integer(key)
    end)
    |> Enum.map(&parse_component(parent, &1, form_opts))
  end

  defp parse_component(parent, {key, params}, form_opts) do
    if predicate?(params) do
      # Eventually, components may have references w/ paths
      # also, we should validate references here
      new_predicate(params, parent)
    else
      params = Map.put_new(params, "id", Ash.UUID.generate())

      new(
        parent.resource,
        Keyword.merge(form_opts,
          params: params,
          as: form_name(parent.name, key, form_opts[:root?]),
          key: params["key"],
          root?: false
        )
      )
    end
  end

  defp form_name(name, key, root?) do
    if root? do
      name
    else
      name <> "[components][#{key}]"
    end
  end

  defp new_predicate(params, form) do
    {path, field} = parse_path_and_field(params, form)

    arguments =
      with related when not is_nil(related) <- Resource.Info.related(form.resource, path),
           calc when not is_nil(calc) <- Resource.Info.calculation(related, field) do
        calc.arguments
      else
        _ ->
          []
      end

    serializer =
      if form.serializer do
        form.serializer
      else
        &default_serializer/2
      end

    operator = to_existing_atom(params["operator"] || :eq)

    predicate = %Predicate{
      id: params["id"],
      field: field,
      value: serializer.(params["value"], params),
      path: path,
      transform_errors: form.transform_errors,
      arguments: Arguments.new(params["arguments"] || %{}, arguments),
      params: params,
      negated?: negated?(params),
      operator: operator
    }

    %{predicate | errors: predicate_errors(predicate, form.resource)}
  end

  defp default_serializer(value, _params), do: value

  defp parse_path_and_field(params, form) do
    path = parse_path(params)
    field = to_existing_atom(params["field"])

    extended_path = path ++ [field]

    case Resource.Info.related(form.resource, extended_path) do
      nil ->
        {path, field}

      related ->
        %{name: new_field} = List.first(Resource.Info.public_attributes(related))
        {extended_path, new_field}
    end
  end

  defp parse_path(params) do
    path = params[:path] || params["path"]

    case path do
      "" ->
        []

      nil ->
        []

      path when is_list(path) ->
        Enum.map(path, &to_existing_atom/1)

      path ->
        path
        |> String.split(".")
        |> Enum.map(&to_existing_atom/1)
    end
  end

  defp negated?(params) do
    params["negated"] in [true, "true"]
  end

  defp validate_components(form, component_params, opts) do
    form_without_components = %{form | components: []}

    component_params
    |> Enum.sort_by(fn {key, _} ->
      String.to_integer(key)
    end)
    |> Enum.map(&validate_component(form_without_components, &1, form.components, opts))
  end

  defp validate_component(form, {key, params}, current_components, opts) do
    reset_on_change? = Keyword.get(opts, :reset_on_change?, true)

    id = params[:id] || params["id"]

    match_component =
      id && Enum.find(current_components, fn %{id: component_id} -> component_id == id end)

    if match_component do
      case match_component do
        %__MODULE__{} ->
          validate(match_component, params, root?: false)

        %Predicate{field: field} ->
          validate_predicate(params, form, field, reset_on_change?)
      end
    else
      if predicate?(params) do
        new_predicate(params, form)
      else
        params = Map.put_new(params, "id", Ash.UUID.generate())

        new(form.resource,
          params: params,
          as: form_name(form.name, key, opts[:root?]),
          remove_empty_groups?: form.remove_empty_groups?,
          root?: false
        )
      end
    end
  end

  defp validate_predicate(params, form, field, reset_on_change?) do
    new_predicate = new_predicate(params, form)

    if reset_on_change? && new_predicate.field != field && not is_nil(new_predicate.value) do
      %{
        new_predicate
        | value: nil,
          operator: nil,
          params: Map.merge(new_predicate.params, %{"value" => nil, "operator" => nil})
      }
    else
      new_predicate
    end
  end

  defp predicate?(params) do
    Enum.any?([:field, :value, "field", "value"], &Map.has_key?(params, &1))
  end

  defp to_existing_atom(value) when is_atom(value), do: value

  defp to_existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    _ -> value
  end

  @doc """
  Returns the minimal set of params (at the moment just strips ids) for use in a query string.

  If nillify_blanks? is true (default to true), then any blank values will be set to nil and
  not included in the params. Furthermore, if a nested group results to an empty group (after
  nillification of it's components), it will be removed as well.
  """
  def params_for_query(form, opts \\ [nillify_blanks?: true, keep_keys?: false])

  def params_for_query(%Predicate{} = predicate, opts) do
    params =
      Map.new(~w(field value operator negated? path)a, fn field ->
        if field == :path do
          {to_string(field), Enum.join(predicate.path, ".")}
        else
          {to_string(field), Map.get(predicate, field)}
        end
      end)

    if opts[:nillify_blanks?] && empty_value?(params["value"], params["operator"]) do
      nil
    else
      maybe_parse_arguments(predicate, params)
    end
  end

  def params_for_query(%__MODULE__{} = form, opts) do
    params = %{
      "negated" => form.negated?,
      "operator" => to_string(form.operator)
    }

    params =
      if opts[:keep_keys?] && form.key do
        Map.put(params, "key", form.key)
      else
        params
      end

    if is_nil(form.components) || Enum.empty?(form.components) do
      if opts[:nillify_blanks?] do
        %{}
      else
        params
      end
    else
      params
      |> Map.put(
        "components",
        form.components
        |> Enum.with_index()
        |> eval_components(opts)
      )
      |> then(fn params -> coalesce_empty_groups(params) end)
    end
  end

  def params_for_query(%Arguments{} = arguments, _opts) do
    Map.new(arguments.arguments, fn argument ->
      {to_string(argument.name),
       Map.get(
         arguments.input,
         argument.name,
         Map.get(
           arguments.params,
           argument.name,
           Map.get(arguments.params, to_string(argument.name))
         )
       )}
    end)
  end

  defp maybe_parse_arguments(predicate, params) do
    case predicate.arguments do
      %Arguments{} = arguments ->
        argument_params = params_for_query(arguments)

        if Enum.empty?(argument_params) do
          params
        else
          Map.put(params, "arguments", argument_params)
        end

      _ ->
        params
    end
  end

  defp coalesce_empty_groups(params) do
    case params["components"] do
      components when components == %{"empty" => %{}} ->
        %{}

      %{"empty" => %{}} ->
        Map.update!(params, "components", fn components ->
          Map.delete(components, "empty")
        end)

      _ ->
        params
    end
  end

  defp eval_components(components, opts) do
    Map.new(components, fn {value, index} ->
      params = params_for_query(value, opts)

      case params do
        nil -> {"empty", %{}}
        params when params == %{} -> {"empty", %{}}
        params -> {to_string(index), params}
      end
    end)
  end

  defp empty_value?(value, operator)
  defp empty_value?(_, :is_nil), do: false
  defp empty_value?(value, :in) when value in [[], [""]], do: true
  defp empty_value?(value, _) when value in [nil, ""], do: true
  defp empty_value?(_, _), do: false

  @doc "Returns the list of available predicates for the given resource, which may be functions or operators."
  def predicates(resource) do
    resource
    |> Ash.DataLayer.functions()
    |> Enum.concat(Ash.Filter.builtin_functions())
    |> Enum.filter(fn function ->
      try do
        struct(function).__predicate__? && Enum.any?(function.args, &match?([_, _], &1))
      rescue
        _ -> false
      end
    end)
    |> Enum.concat(Ash.Filter.builtin_predicate_operators())
    |> Enum.map(fn function_or_operator ->
      function_or_operator.name()
    end)
  end

  @doc "Returns the list of available fields, which may be attributes, calculations, or aggregates."
  def fields(resource) do
    resource
    |> Resource.Info.public_aggregates()
    |> Enum.concat(Resource.Info.public_calculations(resource))
    |> Enum.concat(Resource.Info.public_attributes(resource))
    |> Enum.map(& &1.name)
  end

  @add_predicate_opts [
    to: [
      type: :string,
      doc: "The group id to add the predicate to. If not set, will be added to the top level group."
    ],
    return_id?: [
      type: :boolean,
      default: false,
      doc: "If set to `true`, the function returns `{form, predicate_id}`"
    ],
    path: [
      type: {:or, [:string, {:list, {:or, [:string, :atom]}}]},
      doc: "The relationship path to apply the predicate to"
    ]
  ]

  @doc """
  Add a predicate to the filter.

  Options:

  #{Spark.Options.docs(@add_predicate_opts)}
  """
  def add_predicate(form, field, operator_or_function, value, opts \\ []) do
    opts = Spark.Options.validate!(opts, @add_predicate_opts)

    predicate_id = Ash.UUID.generate()

    predicate_params = %{
      "id" => predicate_id,
      "field" => field,
      "value" => value,
      "operator" => operator_or_function
    }

    predicate_params =
      if opts[:path] do
        Map.put(predicate_params, "path", opts[:path])
      else
        predicate_params
      end

    predicate =
      new_predicate(
        predicate_params,
        form
      )

    new_form =
      if opts[:to] && opts[:to] != form.id do
        set_validity(%{
          form
          | components: Enum.map(form.components, &do_add_predicate(&1, opts[:to], predicate))
        })
      else
        set_validity(%{form | components: form.components ++ [predicate]})
      end

    if opts[:return_id?] do
      {new_form, predicate_id}
    else
      new_form
    end
  end

  defp do_add_predicate(%__MODULE__{id: id} = form, id, predicate) do
    %{form | components: form.components ++ [predicate]}
  end

  defp do_add_predicate(%__MODULE__{} = form, id, predicate) do
    %{form | components: Enum.map(form.components, &do_add_predicate(&1, id, predicate))}
  end

  defp do_add_predicate(other, _, _), do: other

  defp set_validity(%__MODULE__{components: components} = form) do
    components = Enum.map(components, &set_validity/1)

    if Enum.all?(components, & &1.valid?) do
      %{form | components: components, valid?: true}
    else
      %{form | components: components, valid?: false}
    end
  end

  defp set_validity(%Predicate{errors: []} = predicate), do: %{predicate | valid?: true}
  defp set_validity(%Predicate{errors: _} = predicate), do: %{predicate | valid?: false}

  @doc "Remove the predicate with the given id"
  def remove_predicate(form, id) do
    set_validity(%{
      form
      | components:
          Enum.flat_map(form.components, fn
            %__MODULE__{} = nested_form ->
              new_nested_form = remove_predicate(nested_form, id)

              remove_if_empty(new_nested_form, form.remove_empty_groups?)

            %Predicate{id: ^id} ->
              []

            predicate ->
              [predicate]
          end)
    })
  end

  @doc "Update the predicate with the given id"
  def update_predicate(form, id, func) do
    set_validity(%{
      form
      | components:
          Enum.map(form.components, fn
            %__MODULE__{} = nested_form -> update_predicate(nested_form, id, func)
            %Predicate{id: ^id} = pred -> func.(pred)
            predicate -> predicate
          end)
    })
  end

  @doc """
  Update the predicates of the nested_form with the given key.

  Works also for predicates in nested forms inside the nested form.
  """
  def update_group(form, key, func, root \\ true)

  def update_group(%__MODULE__{key: form_key} = form, key, func, false) when form_key == key or key == :__nested_group do
    %{
      form
      | components:
          Enum.map(form.components, fn
            %__MODULE__{} = nested_form ->
              update_group(nested_form, :__nested_group, func, false)

            %Predicate{} = pred ->
              func.(pred)
          end)
    }
  end

  def update_group(%__MODULE__{} = form, key, func, true) do
    set_validity(%{
      form
      | components:
          Enum.map(form.components, fn component ->
            update_group(component, key, func, false)
          end)
    })
  end

  def update_group(%Predicate{} = predicate, _key, _func, _root), do: predicate
  def update_group(%__MODULE__{} = form, _key, _func, _root), do: form

  defp predicate_errors(predicate, resource) do
    case Resource.Info.related(resource, predicate.path) do
      nil ->
        [
          {:operator, "Invalid path #{Enum.join(predicate.path, ".")}", []}
        ]

      resource ->
        errors = public_field_errors(resource, predicate)

        if Ash.Filter.get_function(predicate.operator, resource, true) do
          errors
        else
          maybe_add_operator_errors(predicate, errors)
        end
    end
  end

  defp public_field_errors(resource, predicate) do
    case Resource.Info.public_field(resource, predicate.field) do
      nil ->
        [
          {:field, "No such field #{predicate.field}", []}
        ]

      _ ->
        []
    end
  end

  defp maybe_add_operator_errors(predicate, errors) do
    if Ash.Filter.get_operator(predicate.operator) do
      errors
    else
      [
        {:operator, "No such operator #{predicate.operator}", []} | errors
      ]
    end
  end

  @add_group_opts [
    to: [
      type: :string,
      doc: "The nested group id to add the group to."
    ],
    operator: [
      type: {:one_of, [:and, :or]},
      default: :and,
      doc: "The operator that the group should have internally."
    ],
    key: [
      type: :any,
      default: nil,
      doc: "The key to use for the group."
    ],
    return_id?: [
      type: :boolean,
      default: false,
      doc: "If set to `true`, the function returns `{form, predicate_id}`"
    ]
  ]

  @doc """
  Add a group to the filter. A group can contain predicates and other groups,
  allowing you to build quite complex nested filters.

  Options:

  #{Spark.Options.docs(@add_group_opts)}
  """
  def add_group(form, opts \\ []) do
    opts = Spark.Options.validate!(opts, @add_group_opts)
    group_id = Ash.UUID.generate()

    group = %__MODULE__{
      resource: form.resource,
      operator: opts[:operator],
      id: group_id,
      key: opts[:key]
    }

    new_form =
      if opts[:to] && opts[:to] != form.id do
        set_validity(%{
          form
          | components:
              Enum.map(
                Enum.with_index(form.components),
                &do_add_group(&1, opts[:to], group)
              )
        })
      else
        set_validity(%{form | components: form.components ++ [group]})
      end

    if opts[:return_id?] do
      {new_form, group_id}
    else
      new_form
    end
  end

  defp do_add_group({%AshPagify.FilterForm{id: id, name: parent_name} = form, i}, id, group) do
    name = parent_name <> "[components][#{i}]"
    %{form | components: form.components ++ [%{group | name: name}]}
  end

  defp do_add_group({%AshPagify.FilterForm{} = form, _i}, id, group) do
    %{
      form
      | components: Enum.map(Enum.with_index(form.components), &do_add_group(&1, id, group))
    }
  end

  defp do_add_group({other, _i}, _, _), do: other

  @doc "Remove the group with the given id"
  def remove_group(form, group_id) do
    set_validity(%{
      form
      | components:
          Enum.flat_map(form.components, fn
            %__MODULE__{id: ^group_id} ->
              []

            %__MODULE__{} = nested_form ->
              new_nested_form = remove_group(nested_form, group_id)

              remove_if_empty(new_nested_form, form.remove_empty_groups?)

            predicate ->
              [predicate]
          end)
    })
  end

  @doc "Removes the group *or* predicate with the given id"
  def remove_component(form, group_or_predicate_id) do
    form
    |> remove_group(group_or_predicate_id)
    |> remove_predicate(group_or_predicate_id)
  end

  defp remove_if_empty(form, false), do: [form]

  defp remove_if_empty(form, true) do
    if Enum.empty?(form.components) do
      []
    else
      [form]
    end
  end

  @doc """
  Count the number of records that match the filter form parameters.

  If you pass a query, it will be used to count the records. Otherwise, the resource
  from the meta struct will be used.

  If you pass `reset: true`, the filter form will be reset to an empty map.
  """
  @spec count(Meta.t(), map(), boolean(), Query.t() | nil) :: non_neg_integer()
  def count(meta, filter_form_params, reset \\ false, query \\ nil)

  def count(%Meta{} = meta, filter_form_params, reset, %Query{} = query) do
    meta = set_filter_form(meta, filter_form_params, reset)
    AshPagify.count(query, meta.ash_pagify)
  end

  def count(%Meta{} = meta, filter_form_params, reset, _) do
    meta = set_filter_form(meta, filter_form_params, reset)
    AshPagify.count(meta.resource, meta.ash_pagify)
  end

  defp set_filter_form(meta, filter_form_params, reset) do
    params = if reset, do: %{}, else: filter_form_params

    AshPagify.set_filter_form(meta, params)
  end

  @doc """
  Helper function to extract all active filter form fields from a AshPagify.Meta struct.
  """
  @spec active_filter_form_fields(Meta.t()) :: list()
  def active_filter_form_fields(meta)

  def active_filter_form_fields(%Meta{ash_pagify: %AshPagify{filter_form: nil}}), do: []

  def active_filter_form_fields(%Meta{ash_pagify: %AshPagify{filter_form: filter_form}}) do
    extract_filter_form_fields(filter_form)
  end

  @doc """
  Helper function to extract all filter form fields from a AshPhoenix.FilterForm parameter.
  """
  @spec extract_filter_form_fields(map() | nil) :: list()
  def extract_filter_form_fields(nil), do: []

  def extract_filter_form_fields(data) do
    data
    |> Map.get("components")
    |> do_extract_filter_form_fields([])
    |> Enum.uniq()
  end

  defp do_extract_filter_form_fields(nil, acc), do: acc

  defp do_extract_filter_form_fields(components, acc) do
    Enum.reduce(components, acc, fn {_key, value}, acc ->
      acc =
        case value do
          %{"operator" => "is_nil", "field" => field} -> [field | acc]
          %{"value" => nil} -> acc
          %{"value" => ""} -> acc
          %{"value" => []} -> acc
          %{"field" => field} -> [field | acc]
          _ -> acc
        end

      case Map.get(value, "components") do
        nil -> acc
        nested_form_parameter -> do_extract_filter_form_fields(nested_form_parameter, acc)
      end
    end)
  end

  defimpl Phoenix.HTML.FormData do
    @impl true
    def to_form(form, opts) do
      hidden = [id: form.id]

      %Phoenix.HTML.Form{
        source: form,
        impl: __MODULE__,
        id: opts[:id] || form.id,
        name: opts[:as] || form.name,
        errors: opts[:errors] || [],
        data: form,
        params: form.params,
        hidden: hidden,
        options: Keyword.put_new(opts, :method, "GET")
      }
    end

    @impl true
    def to_form(form, phoenix_form, :components, _opts) do
      form.components
      |> Enum.with_index()
      |> Enum.map(fn {component, index} ->
        name = Map.get(component, :name, phoenix_form.name)

        case component do
          %AshPagify.FilterForm{} ->
            to_form(component,
              as: name <> "[components][#{index}]",
              id: component.id,
              errors: AshPagify.FilterForm.errors(component)
            )

          %Predicate{} ->
            Phoenix.HTML.FormData.AshPhoenix.FilterForm.Predicate.to_form(component,
              as: name <> "[components][#{index}]",
              id: component.id,
              errors: AshPagify.FilterForm.errors(component)
            )
        end
      end)
    end

    def to_form(_, _, other, _) do
      raise "Invalid inputs_for name #{other}. Only :components is supported"
    end

    @impl true
    def input_value(%{id: id}, _, :id), do: id
    def input_value(%{negated?: negated?}, _, :negated), do: negated?
    def input_value(%{operator: operator}, _, :operator), do: operator

    def input_value(form, phoenix_form, :components) do
      to_form(form, phoenix_form, :components, [])
    end

    def input_value(_, _, _field) do
      nil
    end

    @impl true
    def input_validations(_, _, _), do: []
  end
end
