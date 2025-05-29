# Spec

Validate data against specifications

[![Elixir CI](https://github.com/ckampfe/spec/actions/workflows/elixir.yml/badge.svg)](https://github.com/ckampfe/spec/actions/workflows/elixir.yml)

---

## What/why

You want to validate input data before it makes its way into the
rest of your system.

You are sending data to a remote client and want to
make sure you always send valid data.

You want to make sure that data obeys a spec.

## Features

- Anything can be a spec: anything that implements the `AsSpec` protocol and returns truthy/falsy values can be a spec. Default implementations provided for `fn/1`, `{Module, :function}`, `MapSet` (if a value is a member of a set), `Range` (if a value is in a range). See the tests for more.
- Compose specs arbitrarily with `all?` (all specs must pass in order to pass the parent spec) and `any?` (any passing spec passes the parent spec)
- Validate maps for required and optional keys
- Robust failure reporting

## Examples

### Validate data

`valid?` returns `true` or `false`.

```elixir
# simple
spec = fn v -> Integer.is_even(v) end
Spec.valid?(spec, 2) == true
Spec.valid?(spec, 3) == false

# all
spec = Spec.all?([
  fn v -> Integer.is_even(v) end,
  fn v -> v < 10 end
])
Spec.valid?(spec, 2) == true
Spec.valid?(spec, 12) == false

# note the keyword list
spec = Spec.any?(
  even: fn v -> Integer.is_even(v) end,
  less_than_10: fn v -> v < 10 end
)
Spec.valid?(spec, 2) == true # is_even
Spec.valid?(spec, 9) == true # < 10
Spec.valid?(spec, 13) == false # neither

# maps
Spec.keys(
  # required keys must be present, and must pass the specs
  required: [
    a: Spec.all?([&is_binary/1, fn v -> String.length(v) < 5 end]),
    b: &is_integer/1
  ],
  # optional keys can be missing, but if they are present,
  # they must pass the specs
  optional: [c: &is_atom/1]
)

Spec.valid?(spec, %{a: "hi"}) == false # :b missing
Spec.valid?(spec, %{a: "hi", b: 8}) == true
Spec.valid?(spec, %{a: "hello there", b: 8}) == false # String.length("hello there") > 5
Spec.valid?(spec, %{a: "hi", b: 8, c: :hi}) == true
Spec.valid?(spec, %{a: "hi", b: 8, c: %{}}) == false # :c not an atom
```

### Conform data

`conform` returns `{:ok, data}` or `{:error, explanation}`.
Explanation contains the failing value, the failing spec, and the path to reach the failing value/spec.

```elixir
Spec.conform(fn v -> Integer.is_even(v) end, 2) == {:ok, 2}

# map with error reporting
 spec =
      Spec.keys(
        required: [
          a: Spec.all?([&is_binary/1, fn v -> String.length(v) < 5 end]),
          b: &is_integer/1
        ],
        optional: []
      )

assert {
  :error,
  [
    %{value: "not an int", path: [:b], spec: "&:erlang.is_integer/1"},
    %{value: 842_848_024, path: [:a], spec: "&:erlang.is_binary/1"}
  ]
} = Spec.conform(spec, %{a: 842_848_024, b: "not an int"})
```

## Complex, "real" example

```elixir
defmodule CarSpecs do
  require Spec

  def financing(_v) do
    Spec.keys(
      required: [
        interest_rate: {CarSpecs, :financing_interest_rate},
        term_months: {CarSpecs, :financing_term_months}
      ],
      optional: [
        contingent: {CarSpecs, :financing_contingent}
      ]
    )
  end

  def financing_interest_rate(_v) do
    Spec.all?([&is_float/1, fn v -> v > 0.0 end])
  end

  def financing_term_months(_v) do
    Spec.any?(short: 24..48, longer: 72..120)
  end

  def financing_contingent(_v) do
    Spec.keys(
      required: [
        credit_score: fn score -> score > 700 end
      ],
      optional: []
    )
  end

  def msrp(_v) do
    Spec.all?([&is_integer/1, fn v -> v > 0 end])
  end

  def make(v) do
    Enum.member?(MapSet.new([:lancia, :ferrari]), v)
  end

  def model(v) do
    is_binary(v)
  end

  def miles(v) do
    v >= 0
  end

  def year(_v) do
    Spec.all?([&is_binary/1, fn v -> String.length(v) == 4 end])
  end
end

defmodule SpecDataTest do
  require Spec
  use ExUnit.Case
  doctest Spec

  test "failing" do
    data = %{
      financing: %{
        interest_rate: "sof",
        term_months: 60
      },
      msrp: 27_001,
      make: :lancia,
      model: "delta",
      miles: 2402,
      year: 2025
    }

    spec =
      Spec.keys(
        required: [
          financing: {CarSpecs, :financing},
          msrp: {CarSpecs, :msrp},
          make: {CarSpecs, :make},
          model: {CarSpecs, :model},
          miles: {CarSpecs, :miles},
          year: {CarSpecs, :year}
        ],
        optional: []
      )

    assert {
             :error,
             [
               %{value: 2025, path: [:year], spec: _},
               %{
                 path: [
                   :financing,
                   :term_months,
                   :longer
                 ],
                 spec: "72..120",
                 value: 60
               },
               %{
                 path: [
                   :financing,
                   :term_months,
                   :short
                 ],
                 spec: "24..48",
                 value: 60
               },
               %{value: "sof", path: [:financing, :interest_rate], spec: _}
             ]
           } = Spec.conform(spec, data)
  end

  test "ok" do
    data = %{
      financing: %{
        interest_rate: 3.9,
        term_months: 48,
        contingent: %{
          credit_score: 720
        }
      },
      msrp: 27_001,
      make: :lancia,
      model: "delta",
      miles: 8,
      year: "2025"
    }

    spec =
      Spec.keys(
        required: [
          financing: {CarSpecs, :financing},
          msrp: {CarSpecs, :msrp},
          make: {CarSpecs, :make},
          model: {CarSpecs, :model},
          miles: {CarSpecs, :miles},
          year: {CarSpecs, :year}
        ],
        optional: []
      )

    assert {:ok, _} = Spec.conform(spec, data)
  end
end
```
