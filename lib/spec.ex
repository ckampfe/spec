# TODO
#
# API design:
# conform -> {:ok, conformed} | {:error, explanation}

defmodule Spec do
  defmacro all?(specs) when is_list(specs) do
    quote do
      {:all, unquote(specs)}
    end
  end

  defmacro any?(specs) when is_list(specs) do
    quote do
      {:any, unquote(specs)}
    end
  end

  defmacro keys(args) when is_list(args) do
    quote do
      {:keys, unquote(args)}
    end
  end

  def conform(m, f, value) when is_atom(m) and is_atom(f) do
    do_conform(m, f, value, [])
  end

  def conform(spec, value) when is_function(spec, 1) do
    do_conform(spec, value, [])
  end

  def conform({:all, _specs} = expr, value) do
    do_conform(expr, value, [])
  end

  def conform({:any, _specs_and_keys} = expr, value) do
    do_conform(expr, value, [])
  end

  def conform(%MapSet{} = spec, value) do
    do_conform(spec, value, [])
  end

  def conform({:keys, _specs} = expr, value) when is_map(value) do
    do_conform(expr, value, [])
  end

  defp do_conform(spec, value, path) when is_function(spec, 1) do
    if spec.(value) do
      {:ok, value}
    else
      {:error, %{spec: spec, value: value, path: path}}
    end
  end

  defp do_conform({:keys, specs} = spec, value, path) when is_map(value) do
    req_specs = specs[:required]
    opt_specs = specs[:optional]
    keys = MapSet.new(Map.keys(value))

    req_keyset = specs[:required] |> Keyword.keys() |> MapSet.new()

    opt_keyset =
      specs[:optional] |> Keyword.keys() |> MapSet.new()

    common_keys =
      MapSet.intersection(req_keyset, opt_keyset)

    if Enum.empty?(req_keyset) && Enum.empty?(opt_keyset) do
      throw(
        {:error,
         %{
           spec: spec,
           value: value,
           path: path,
           error: "required and optional keysets cannot both be empty"
         }}
      )
    end

    if !MapSet.equal?(common_keys, MapSet.new()) do
      throw(
        {:error,
         %{
           spec: spec,
           value: value,
           path: path,
           error: "required keys cannot alows be optional keys"
         }}
      )
    end

    if !MapSet.subset?(req_keyset, keys) do
      diff = MapSet.difference(req_keyset, keys)

      throw(
        {:error,
         %{spec: spec, value: value, path: path, error: "missing #{inspect(Enum.to_list(diff))}"}}
      )
    end

    if MapSet.equal?(
         MapSet.intersection(req_keyset, keys),
         req_keyset
       ) do
      {req_conform, errors} =
        Enum.reduce_while(req_specs, {value, []}, fn {key, spec}, {acc, errors} ->
          value_for_key = Map.fetch!(acc, key)

          case do_conform(spec, value_for_key, path) do
            {:ok, conformed} ->
              {:cont, {Map.put(acc, key, conformed), errors}}

            {:error, e} ->
              e =
                Map.update!(e, :path, fn path ->
                  [key | path]
                end)

              {:cont, {acc, [e | errors]}}
          end
        end)

      {out, errors} =
        Enum.reduce_while(opt_specs, {req_conform, errors}, fn {key, spec}, {acc, errors} ->
          case Map.fetch(acc, key) do
            :error ->
              {:cont, {acc, errors}}

            {:ok, value_for_key} ->
              case do_conform(spec, value_for_key, path) do
                {:ok, conformed} ->
                  {:cont, {Map.put(acc, key, conformed), errors}}

                {:error, e} ->
                  e =
                    Map.update!(e, :path, fn path ->
                      [key | path]
                    end)

                  {:cont, {acc, [e | errors]}}
              end
          end
        end)

      if !Enum.empty?(errors) do
        {:error, errors}
      else
        {:ok, out}
      end
    else
      Spec.Invalid
    end
  catch
    :throw, e ->
      e
  end

  defp do_conform(%MapSet{} = spec, value, path) do
    if MapSet.member?(spec, value) do
      {:ok, value}
    else
      {:error, %{value: value, spec: spec, path: path}}
    end
  end

  defp do_conform({:all, specs}, value, path) do
    out =
      Enum.reduce_while(specs, value, fn spec, acc ->
        case do_conform(spec, acc, path) do
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

  defp do_conform({:any, specs_and_keys}, value, path) do
    out =
      Enum.reduce_while(specs_and_keys, [], fn {key, spec}, errors ->
        case do_conform(spec, value, path) do
          {:ok, conformed} ->
            {:halt, {:ok, {key, conformed}}}

          {:error, e} ->
            e =
              Map.update!(e, :path, fn path ->
                [key | path]
              end)

            {:cont, [e | errors]}
        end
      end)

    case out do
      {:ok, _} = ok -> ok
      errors -> {:error, errors}
    end
  end

  defp do_conform(m, f, value, path) when is_atom(m) and is_atom(f) do
    if apply(m, f, [value]) do
      {:ok, value}
    else
      {:error, %{spec: {m, f}, value: value, path: path}}
    end
  end

  def valid?(%MapSet{} = spec, value) do
    match?({:ok, _}, conform(spec, value))
  end

  def valid?({:keys, _specs} = keys_expr, value) do
    match?({:ok, _}, conform(keys_expr, value))
  end

  def valid?({:all, _specs} = and_expr, value) do
    match?({:ok, _}, conform(and_expr, value))
  end

  def valid?({:any, _specs} = or_expr, value) do
    match?({:ok, _}, conform(or_expr, value))
  end

  def valid?(spec, value) when is_function(spec, 1) do
    match?({:ok, _}, conform(spec, value))
  end

  def valid?(m, f, value) when is_atom(m) and is_atom(f) do
    conform(m, f, value)
  end

  # Kernel.def def(name, do: body) do
  #   quote do
  #     def unquote(name)(arg) do
  #     end
  #   end
  # end

  defmodule Invalid do
  end
end
