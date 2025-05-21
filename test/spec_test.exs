defmodule SpecTest do
  require Integer
  require Spec
  use ExUnit.Case
  doctest Spec

  test "valid?/2" do
    assert Spec.valid?(&Integer.is_even/1, 2)
    refute Spec.valid?(&Integer.is_even/1, 1)
    assert Spec.valid?(MapSet.new([1, 2, 3]), 1)
    refute Spec.valid?(MapSet.new([1, 2, 3]), 9)
  end

  test "conform/2" do
    assert Spec.conform(&Integer.is_even/1, 2) == {:ok, 2}
    assert match?({:error, %{value: 1}}, Spec.conform(&Integer.is_even/1, 1))
    assert Spec.conform(MapSet.new([1, 2, 3]), 1) == {:ok, 1}
    assert match?({:error, _}, Spec.conform(MapSet.new([1, 2, 3]), 9))
  end

  test "and" do
    specs = Spec.all?([&Integer.is_even/1, fn v -> v < 10 end])

    assert Spec.conform(specs, 4) == {:ok, 4}
    assert match?({:error, _}, Spec.conform(specs, 12))

    assert Spec.valid?(specs, 4)
    refute Spec.valid?(specs, 12)
  end

  test "or" do
    spec = Spec.any?(even: &Integer.is_even/1, less_than_10: fn v -> v < 10 end)

    assert Spec.conform(spec, 4) == {:ok, {:even, 4}}
    assert Spec.conform(spec, 9) == {:ok, {:less_than_10, 9}}
    assert Spec.conform(spec, 12) == {:ok, {:even, 12}}

    assert Spec.valid?(spec, 4)
    assert Spec.valid?(spec, 12)
    refute Spec.valid?(spec, 31)
  end

  test "keys required only" do
    spec =
      Spec.keys(
        required: [
          a: Spec.all?([&is_binary/1, fn v -> String.length(v) < 5 end]),
          b: &is_integer/1
        ],
        optional: []
      )

    assert Spec.conform(spec, %{a: "hi", b: 8}) == {:ok, %{a: "hi", b: 8}}

    assert {:error, [%{value: "longer than 5", path: [:a], spec: _}]} =
             Spec.conform(spec, %{a: "longer than 5", b: 8})

    assert Spec.conform(spec, %{a: "hi", b: 8}) == {:ok, %{a: "hi", b: 8}}

    assert {:error,
            %{
              error: "missing [:b]",
              value: %{a: "hi"},
              path: [],
              spec: ^spec
            }} = Spec.conform(spec, %{a: "hi"})

    assert {:error,
            [
              %{value: "not an int", path: [:b], spec: _},
              %{value: 842_848_024, path: [:a], spec: _}
            ]} = Spec.conform(spec, %{a: 842_848_024, b: "not an int"})

    assert Spec.conform(spec, %{a: "hi", b: 8, c: "something"}) ==
             {:ok, %{a: "hi", b: 8, c: "something"}}
  end

  test "test optional only" do
    spec =
      Spec.keys(
        required: [],
        optional: [
          a: Spec.all?([&is_binary/1, fn v -> String.length(v) < 5 end]),
          b: &is_integer/1,
          c: &is_atom/1
        ]
      )

    assert Spec.conform(spec, %{a: "hi", b: 8}) == {:ok, %{a: "hi", b: 8}}

    assert {:error,
            [
              %{
                value: "longer than 5",
                path: [:a],
                spec: _
              }
            ]} =
             Spec.conform(spec, %{a: "longer than 5", b: 8})

    assert Spec.conform(spec, %{a: "hi", b: 8}) == {:ok, %{a: "hi", b: 8}}

    assert Spec.conform(spec, %{a: "hi"}) == {:ok, %{a: "hi"}}

    assert {:error,
            [
              %{value: "not an int", path: [:b], spec: _},
              %{value: 842_848_024, path: [:a], spec: _}
            ]} = Spec.conform(spec, %{a: 842_848_024, b: "not an int"})
  end

  test "keys both" do
    spec =
      Spec.keys(
        required: [
          a: Spec.all?([&is_binary/1, fn v -> String.length(v) < 5 end]),
          b: &is_integer/1
        ],
        optional: [c: &is_atom/1]
      )

    # required keys only
    assert Spec.conform(spec, %{a: "hi", b: 8}) == {:ok, %{a: "hi", b: 8}}

    assert {:error, [%{value: "longer than 5", path: [:a], spec: _}]} =
             Spec.conform(spec, %{a: "longer than 5", b: 8})

    assert {
             :error,
             [
               %{
                 path: [:b],
                 value: "not an int",
                 spec: _
               },
               %{
                 path: [:a],
                 value: 842_848_024,
                 spec: _
               }
             ]
           } =
             Spec.conform(spec, %{a: 842_848_024, b: "not an int"})

    # with opt
    assert Spec.conform(spec, %{a: "hi", b: 8, c: :foo}) == {:ok, %{a: "hi", b: 8, c: :foo}}
    assert match?({:error, _}, Spec.conform(spec, %{a: "hi", b: 8, c: "nope"}))

    # valid?
    assert Spec.valid?(spec, %{a: "hi", b: 8})
    refute Spec.valid?(spec, %{a: "longer than 5", b: 8})
    refute Spec.valid?(spec, %{a: "hi"})
    refute Spec.valid?(spec, %{a: 842_848_024, b: "not an int"})
    assert Spec.valid?(spec, %{a: "hi", b: 8, c: :foo})
    refute Spec.valid?(spec, %{a: "hi", b: 8, c: "nope"})
  end
end
