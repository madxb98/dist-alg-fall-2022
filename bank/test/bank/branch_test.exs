defmodule Bank.BranchTest do
  alias Bank.Branch

  use ExUnit.Case
  doctest Branch

  describe "given a new disconnected Branch" do
    setup _ctx do
      pid = start_supervised!({Branch, 1})

      [pid: pid]
    end

    test "the initial state is set", ctx do
      assert 1 == peek(ctx.pid) |> Map.get(:id)
    end

    test "the cash-on-hand will be $1,000" do
      assert {:ok, 1000} == Branch.check_cash_on_hand(1)
    end

    test "calls to check_balance will error with :account_does_not_exist" do
      assert {:error, :account_does_not_exist} == Branch.check_balance(1, 1000)
    end

    test "calls to deposit_cash will error with :account_does_not_exist" do
      assert {:error, :account_does_not_exist} == Branch.deposit_cash(1, 1000, 100)
    end

    test "calls to withdraw_cash will error with :account_does_not_exist" do
      assert {:error, :account_does_not_exist} == Branch.withdraw_cash(1, 1000, 100)
    end

    test "an account can be opened" do
      assert {:ok, :account_opened} == Branch.open_account(1, 1000)
    end
  end

  describe "given a disconnected Branch with one newly opened account" do
    setup _ctx do
      pid = start_supervised!({Branch, 1})
      {:ok, :account_opened} = Branch.open_account(1, 1000)
      [pid: pid, account_number: 1000]
    end

    test "deposits can be made", ctx do
      assert {:ok, :cash_deposited} == Branch.deposit_cash(1, 1000, 50)
      assert 50 = peek(ctx.pid) |> Map.get(:accounts) |> Map.get(ctx.account_number)
    end

    test "cannot withdraw more than the balance", ctx do
      assert {:error, :insufficient_funds} == Branch.withdraw_cash(1, ctx.account_number, 10)
    end

    test "deposits and withdrawals are reflected in the branch's cash_on_hand", ctx do
      {:ok, :cash_deposited} = Branch.deposit_cash(1, ctx.account_number, 50)
      assert {:ok, 1050} == Branch.check_cash_on_hand(1)

      {:ok, :cash_withdrawn} = Branch.withdraw_cash(1, ctx.account_number, 40)
      assert {:ok, 1010} == Branch.check_cash_on_hand(1)
    end

    test "the balance reflects deposits and withdrawals", ctx do
      assert {:ok, 0} == Branch.check_balance(1, ctx.account_number)
      {:ok, :cash_deposited} = Branch.deposit_cash(1, ctx.account_number, 50)
      assert {:ok, 50} == Branch.check_balance(1, ctx.account_number)
      {:ok, :cash_withdrawn} = Branch.withdraw_cash(1, ctx.account_number, 10)
      assert {:ok, 40} == Branch.check_balance(1, ctx.account_number)
    end

    test "the account can be closed", ctx do
      assert {:ok, :account_closed} == Branch.close_account(1, ctx.account_number)
    end

    test "the account cannot be closed if it has a balance", ctx do
      {:ok, :cash_deposited} = Branch.deposit_cash(1, ctx.account_number, 50)
      assert {:error, :account_balance_not_zero} == Branch.close_account(1, ctx.account_number)
    end
  end

  defp peek(pid) do
    :sys.get_state(pid)
  end
end
