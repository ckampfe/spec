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

  def conform(m, f, _value) when is_atom(m) and is_atom(f) do
  end

  def conform(spec, value) when is_function(spec, 1) do
    if spec.(value) do
      value
    else
      Spec.Invalid
    end
  end

  def conform({:all, specs}, value) do
    Enum.reduce_while(specs, value, fn spec, acc ->
      conformed = conform(spec, acc)

      if conformed == Spec.Invalid do
        {:halt, conformed}
      else
        {:cont, conformed}
      end
    end)
  end

  def conform({:any, specs_and_keys}, value) do
    Enum.find_value(specs_and_keys, Spec.Invalid, fn {key, spec} ->
      conformed = conform(spec, value)

      if conformed != Spec.Invalid do
        {key, conformed}
      else
        false
      end
    end)
  end

  def conform(%MapSet{} = spec, value) do
    if MapSet.member?(spec, value) do
      value
    else
      Spec.Invalid
    end
  end

  def conform({:keys, specs}, value) when is_map(value) do
    req_specs = specs[:required]
    opt_specs = specs[:optional]
    req_keyset = MapSet.new(Keyword.keys(req_specs))
    keys = MapSet.new(Map.keys(value))

    if !Enum.empty?(req_keyset) &&
         MapSet.equal?(
           MapSet.intersection(req_keyset, keys),
           req_keyset
         ) do
      req_conform =
        Enum.reduce_while(req_specs, value, fn {key, spec}, acc ->
          value_for_key = Map.fetch!(acc, key)
          conformed = conform(spec, value_for_key)

          if conformed == Spec.Invalid do
            {:halt, conformed}
          else
            {:cont, Map.put(acc, key, conformed)}
          end
        end)

      if req_conform == Spec.Invalid do
        Spec.Invalid
      else
        Enum.reduce_while(opt_specs, req_conform, fn {key, spec}, acc ->
          case Map.fetch(acc, key) do
            :error ->
              {:cont, acc}

            {:ok, value_for_key} ->
              conformed = conform(spec, value_for_key)

              if conformed == Spec.Invalid do
                {:halt, conformed}
              else
                {:cont, Map.put(acc, key, conformed)}
              end
          end
        end)
      end
    else
      Spec.Invalid
    end
  end

  def conform({:keys, _specs}, value) when not is_map(value) do
    Spec.Invalid
  end

  def valid?(%MapSet{} = spec, value) do
    conform(spec, value) != Spec.Invalid
  end

  def valid?({:keys, _specs} = keys_expr, value) do
    conform(keys_expr, value) != Spec.Invalid
  end

  def valid?({:all, _specs} = and_expr, value) do
    conform(and_expr, value) != Spec.Invalid
  end

  def valid?({:any, _specs} = or_expr, value) do
    conform(or_expr, value) != Spec.Invalid
  end

  def valid?(spec, value) when is_function(spec, 1) do
    !!spec.(value)
  end

  def valid?(m, f, _value) when is_atom(m) and is_atom(f) do
    raise "todo"
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
