# TODO
#
# - [x] conform -> {:ok, conformed} | {:error, explanation}
# - [x] store stringified version of spec so users can see what spec failed clearly
# - [ ] pass full, original object to all subspecs so they can correlate, if they want
# - [x] struct to store all spec context
# - [ ] write docs
# - [ ] set up CI
# - [ ] README

defmodule Spec do
  @enforce_keys [:impl, :repr]
  defstruct [:impl, :repr]

  defmodule Keys do
    defstruct [:args]
  end

  defmodule All do
    defstruct [:args]
  end

  defmodule Any do
    defstruct [:args]
  end

  defmodule Context do
    defstruct [:path]
  end

  def conform(term, value, context \\ %Spec.Context{path: []}) do
    case AsSpec.test(term, value, context) do
      :ok ->
        {:ok, value}

      {:ok, value} ->
        {:ok, value}

      :error ->
        repr = AsSpec.to_string(term)
        {:error, %{value: value, spec: repr, path: context.path}}

      {:error, e} ->
        {:error, e}
    end
  end

  def valid?(term, value) do
    match?({:ok, _}, conform(term, value))
  end

  def all?(specs) when is_list(specs) do
    %Spec.All{args: specs}
  end

  def any?(specs) when is_list(specs) do
    %Spec.Any{args: specs}
  end

  def keys(args) when is_list(args) do
    %Spec.Keys{args: args}
  end
end

defprotocol AsSpec do
  require Spec

  def test(spec, value, context)
  def to_string(spec)
end

defimpl AsSpec, for: Tuple do
  require Spec

  def test({m, f}, value, context) do
    case apply(m, f, [value]) do
      v when is_struct(v) ->
        AsSpec.test(v, value, context)

      truthy_value when truthy_value ->
        {:ok, value}

      _falsy_value ->
        :error
    end
  end

  def to_string(spec) do
    Macro.to_string(spec)
  end
end

defimpl AsSpec, for: Spec.Keys do
  require Spec

  def test(%Spec.Keys{args: specs} = full, value, context) do
    req_specs = specs[:required]
    opt_specs = specs[:optional]
    keys = MapSet.new(Map.keys(value))

    req_keyset = specs[:required] |> Keyword.keys() |> MapSet.new()

    opt_keyset =
      Keyword.get(specs, :optional, []) |> Keyword.keys() |> MapSet.new()

    common_keys =
      MapSet.intersection(req_keyset, opt_keyset)

    if Enum.empty?(req_keyset) && Enum.empty?(opt_keyset) do
      throw(
        {:error,
         %{
           spec: AsSpec.to_string(full),
           value: value,
           path: context.path,
           error: "required and optional keysets cannot both be empty"
         }}
      )
    end

    if !MapSet.equal?(common_keys, MapSet.new()) do
      throw(
        {:error,
         %{
           spec: AsSpec.to_string(full),
           value: value,
           path: context.path,
           error: "required keys cannot alows be optional keys"
         }}
      )
    end

    if !MapSet.subset?(req_keyset, keys) do
      diff = MapSet.difference(req_keyset, keys)

      throw(
        {:error,
         %{
           spec: full,
           value: value,
           path: context.path,
           error: "missing #{inspect(Enum.to_list(diff))}"
         }}
      )
    end

    {req_conform, errors} =
      Enum.reduce_while(req_specs, {value, []}, fn {key, spec}, {acc, errors} ->
        value_for_key = Map.fetch!(acc, key)

        case Spec.conform(spec, value_for_key, %{context | path: context.path ++ [key]}) do
          {:ok, conformed} ->
            {:cont, {Map.put(acc, key, conformed), errors}}

          {:error, e} when is_list(e) ->
            {:cont, {acc, e ++ errors}}

          {:error, e} ->
            {:cont, {acc, [e | errors]}}
        end
      end)

    {out, errors} =
      Enum.reduce_while(opt_specs, {req_conform, errors}, fn {key, spec}, {acc, errors} ->
        case Map.fetch(acc, key) do
          :error ->
            {:cont, {acc, errors}}

          {:ok, value_for_key} ->
            case Spec.conform(spec, value_for_key, %{context | path: context.path ++ [key]}) do
              {:ok, conformed} ->
                {:cont, {Map.put(acc, key, conformed), errors}}

              {:error, e} when is_list(e) ->
                {:cont, {acc, e ++ errors}}

              {:error, e} ->
                {:cont, {acc, [e | errors]}}
            end
        end
      end)

    if !Enum.empty?(errors) do
      {:error, errors}
    else
      {:ok, out}
    end
  catch
    :throw, e ->
      e
  end

  def to_string(_spec) do
    "keys"
  end
end

defimpl AsSpec, for: Spec.All do
  def test(%Spec.All{args: specs}, value, context) do
    out =
      Enum.reduce_while(specs, value, fn spec, acc ->
        case Spec.conform(spec, acc, context) do
          {:ok, conformed} ->
            {:cont, conformed}

          {:error, e} ->
            {:halt, {:error, e}}
        end
      end)

    case out do
      {:error, _} = e -> e
      ok -> {:ok, ok}
    end
  end

  def to_string(_spec) do
    "all"
  end
end

defimpl AsSpec, for: Spec.Any do
  def test(%Spec.Any{args: specs}, value, context) do
    out =
      Enum.reduce_while(specs, [], fn {key, spec}, errors ->
        case Spec.conform(spec, value, context) do
          {:ok, conformed} ->
            {:halt, {:ok, {key, conformed}}}

          {:error, e} ->
            e =
              Map.update!(e, :path, fn path ->
                path ++ [key]
              end)

            {:cont, [e | errors]}
        end
      end)

    case out do
      {:ok, _} = ok -> ok
      errors -> {:error, errors}
    end
  end

  def to_string(_spec) do
    "any"
  end
end

defimpl AsSpec, for: MapSet do
  require Spec

  def test(impl, value, _context) do
    if MapSet.member?(impl, value) do
      :ok
    else
      :error
    end
  end

  def to_string(spec) do
    Macro.to_string(spec)
  end
end

defimpl AsSpec, for: Function do
  require Spec

  def test(impl, value, _context) do
    if impl.(value) do
      :ok
    else
      :error
    end
  end

  def to_string(spec) do
    Macro.to_string(spec)
  end
end

defimpl AsSpec, for: Range do
  require Spec

  def test(impl, value, _context) do
    if value in impl do
      :ok
    else
      :error
    end
  end

  def to_string(spec) do
    Macro.to_string(spec)
  end
end

defimpl AsSpec, for: Any do
  def test(spec, _value, _context) do
    raise "No AsSpec implementation exists for #{spec}"
  end

  def to_string(spec) do
    Macro.to_string(spec)
  end
end
