defmodule Bank.AtmTest do
  alias Bank.Atm

  use ExUnit.Case
  doctest Atm

  describe "given seven ATMs" do
    setup _ctx do
      atms =
        1..7
        |> Enum.map(fn x -> {x, start_supervised!({Atm, x}, id: x)} end)
        |> Map.new()

      [atms: atms]
    end
  end

  describe "given a new disconnected ATM" do
    setup _ctx do
      start_supervised!({Bank.Network, %{}})
      [{pid, nil}] = Registry.lookup(BankRegistry, {:atm, 1})

      [pid: pid]
    end

    test "the initial state is set", ctx do
      assert 1 == peek(ctx.pid) |> Map.get(:id)
    end

    test "the cash-on-hand will be $1,000" do
      assert {:ok, 1000} == Atm.check_cash_on_hand(1)
    end

    test "calls to check_balance will error with :account_does_not_exist" do
      assert {:error, :account_does_not_exist} == Atm.check_balance(1, 1000)
    end

    test "calls to deposit_cash will error with :account_does_not_exist" do
      assert {:error, :account_does_not_exist} == Atm.deposit_cash(1, 1000, 100)
    end

    test "calls to withdraw_cash will error with :account_does_not_exist" do
      assert {:error, :account_does_not_exist} == Atm.withdraw_cash(1, 1000, 100)
    end
  end

  defp peek(pid) do
    :sys.get_state(pid)
  end
end
