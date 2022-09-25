defmodule BankTest do
  use ExUnit.Case
  doctest Bank

  setup do
    start_supervised!({Bank.Network, %{}})

    []
  end

  test "create an account at branch-1, deposit at atm-1, check balance at branch-2" do
    {:ok, :account_opened} = Bank.Branch.open_account(1, 1000)

    # This will fail with `{:error, :account_does_not_exist}` until you implement account replication
    assert {:ok, :cash_deposited} = Bank.Atm.deposit_cash(1, 1000, 50)

    # This will fail with `{:error, :account_does_not_exist}` until you implement transaction replication
    assert {:ok, 50} = Bank.Branch.check_balance(2, 1000)
  end
end
