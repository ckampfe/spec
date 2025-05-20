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
    assert Spec.conform(&Integer.is_even/1, 2) == 2
    assert Spec.conform(&Integer.is_even/1, 1) == Spec.Invalid
    assert Spec.conform(MapSet.new([1, 2, 3]), 1) == 1
    assert Spec.conform(MapSet.new([1, 2, 3]), 9) == Spec.Invalid
  end

  test "and" do
    specs = Spec.all?([&Integer.is_even/1, fn v -> v < 10 end])

    assert Spec.conform(specs, 4) == 4
    assert Spec.conform(specs, 12) == Spec.Invalid

    assert Spec.valid?(specs, 4)
    refute Spec.valid?(specs, 12)
  end

  test "or" do
    spec = Spec.any?(even: &Integer.is_even/1, less_than_10: fn v -> v < 10 end)

    assert Spec.conform(spec, 4) == {:even, 4}
    assert Spec.conform(spec, 9) == {:less_than_10, 9}
    assert Spec.conform(spec, 12) == {:even, 12}

    assert Spec.valid?(spec, 4)
    assert Spec.valid?(spec, 12)
    refute Spec.valid?(spec, 31)
  end

  test "keys" do
    spec =
      Spec.keys(
        required: [
          a: Spec.all?([&is_binary/1, fn v -> String.length(v) < 5 end]),
          b: &is_integer/1
        ],
        optional: [c: &is_atom/1]
      )

    # required keys only
    assert Spec.conform(spec, %{a: "hi", b: 8}) == %{a: "hi", b: 8}
    assert Spec.conform(spec, %{a: "longer than 5", b: 8}) == Spec.Invalid
    assert Spec.conform(spec, %{a: "hi"}) == Spec.Invalid
    assert Spec.conform(spec, %{a: 842_848_024, b: "not an int"}) == Spec.Invalid

    # with opt
    assert Spec.conform(spec, %{a: "hi", b: 8, c: :foo}) == %{a: "hi", b: 8, c: :foo}
    assert Spec.conform(spec, %{a: "hi", b: 8, c: "nope"}) == Spec.Invalid

    # valid?
    assert Spec.valid?(spec, %{a: "hi", b: 8})
    refute Spec.valid?(spec, %{a: "longer than 5", b: 8})
    refute Spec.valid?(spec, %{a: "hi"})
    refute Spec.valid?(spec, %{a: 842_848_024, b: "not an int"})
    assert Spec.valid?(spec, %{a: "hi", b: 8, c: :foo})
    refute Spec.valid?(spec, %{a: "hi", b: 8, c: "nope"})
  end
end
