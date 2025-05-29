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
                 spec: 72..120,
                 value: 60
               },
               %{
                 path: [
                   :financing,
                   :term_months,
                   :short
                 ],
                 spec: 24..48,
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
