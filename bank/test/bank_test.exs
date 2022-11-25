defmodule BankTest do
  use ExUnit.Case
  doctest Bank

  setup do
    start_supervised!({Bank.Network, %{}})

    []
  end

  test "problem 1: create accounts, make deposits, and withdrawals, verify balances and cash-on-hand" do
    branches = [1, 2, 3]
    atms = [1, 2, 3, 4, 5, 6, 7]

    Bank.Branch.open_account(1, 10001)
    Bank.Branch.open_account(1, 10002)
    Bank.Branch.open_account(2, 20001)
    Bank.Branch.open_account(2, 20002)
    Bank.Branch.open_account(3, 30001)
    Bank.Branch.open_account(3, 30002)

    assert Enum.all?(atms, fn atm -> {:ok, 1000} == Bank.Atm.check_cash_on_hand(atm) end)

    assert Enum.all?(branches, fn branch ->
             {:ok, 1000} == Bank.Branch.check_cash_on_hand(branch)
           end)

    Bank.Branch.deposit_cash(3, 10001, 100)
    Bank.Branch.deposit_cash(2, 10002, 200)
    Bank.Branch.deposit_cash(1, 20001, 300)
    Bank.Atm.deposit_cash(2, 20002, 400)
    Bank.Atm.deposit_cash(4, 30001, 500)
    Bank.Atm.deposit_cash(6, 30002, 600)

    assert {:ok, 400} == Bank.Branch.check_balance(1, 20002)
    assert {:ok, 500} == Bank.Branch.check_balance(2, 30001)
    assert {:ok, 600} == Bank.Branch.check_balance(3, 30002)
    assert {:ok, 100} == Bank.Atm.check_balance(1, 10001)
    assert {:ok, 200} == Bank.Atm.check_balance(3, 10002)
    assert {:ok, 300} == Bank.Atm.check_balance(5, 20001)

    assert {:ok, 1300} = Bank.Branch.check_cash_on_hand(1)
    assert {:ok, 1200} = Bank.Branch.check_cash_on_hand(2)
    assert {:ok, 1100} = Bank.Branch.check_cash_on_hand(3)

    assert {:ok, 1000} = Bank.Atm.check_cash_on_hand(1)
    assert {:ok, 1400} = Bank.Atm.check_cash_on_hand(2)
    assert {:ok, 1000} = Bank.Atm.check_cash_on_hand(3)
    assert {:ok, 1500} = Bank.Atm.check_cash_on_hand(4)
    assert {:ok, 1000} = Bank.Atm.check_cash_on_hand(5)
    assert {:ok, 1600} = Bank.Atm.check_cash_on_hand(6)
    assert {:ok, 1000} = Bank.Atm.check_cash_on_hand(7)

    Bank.Branch.withdraw_cash(3, 10001, 100)
    Bank.Branch.withdraw_cash(2, 10002, 200)
    Bank.Branch.withdraw_cash(1, 20001, 300)
    Bank.Atm.withdraw_cash(2, 20002, 400)
    Bank.Atm.withdraw_cash(4, 30001, 500)
    Bank.Atm.withdraw_cash(6, 30002, 600)

    assert Enum.all?(branches, fn branch ->
             {:ok, 1000} == Bank.Branch.check_cash_on_hand(branch)
           end)
  end

  test "problem 2: implement transfer_money" do
    Bank.Branch.open_account(1, 10001)
    Bank.Branch.open_account(2, 10002)

    Bank.Atm.deposit_cash(5, 10001, 100)
    assert {:ok, 1100} = Bank.Atm.check_cash_on_hand(5)

    assert {:ok, :transferred} == Bank.Branch.transfer_money(3, 10001, 10002, 40)
    assert {:ok, 60} == Bank.Atm.check_balance(3, 10001)
    assert {:ok, 40} == Bank.Atm.check_balance(5, 10002)

    assert {:ok, 1100} = Bank.Atm.check_cash_on_hand(5)
  end

  test "problem 3: close_account behaves well on a good network" do
    Bank.Branch.open_account(1, 10001)
    Bank.Atm.deposit_cash(5, 10001, 100)

    assert {:error, :account_balance_not_zero} == Bank.Branch.close_account(1, 10001)

    Bank.Atm.withdraw_cash(7, 10001, 100)

    assert {:ok, :account_closed} == Bank.Branch.close_account(1, 10001)
    assert {:error, :account_does_not_exist} == Bank.Branch.close_account(1, 10001)

    assert {:error, :account_does_not_exist} == Bank.Atm.check_balance(1, 10001)
  end

  test "problem 4: parallel updates" do
    Bank.Branch.open_account(1, 10001)
    Bank.Branch.deposit_cash(1, 10001, 1000)

    commands =
      [
        1..3 |> Enum.map(fn x -> {Bank.Branch, x, :deposit_cash} end),
        1..3 |> Enum.map(fn x -> {Bank.Branch, x, :withdraw_cash} end),
        1..7 |> Enum.map(fn x -> {Bank.Atm, x, :deposit_cash} end),
        1..7 |> Enum.map(fn x -> {Bank.Atm, x, :withdraw_cash} end)
      ]
      |> List.flatten()

    commands
    |> Enum.shuffle()
    |> Stream.cycle()
    |> Enum.take(200)
    |> Enum.map(fn {module, location_id, function} ->
      Task.async(fn ->
        Process.sleep(:rand.uniform(100))
        apply(module, function, [location_id, 10001, 1])
      end)
    end)
    |> Task.await_many()

    branch_expected = 1..3 |> Enum.map(fn _ -> {:ok, 1000} end)
    atm_expected = 1..7 |> Enum.map(fn _ -> {:ok, 1000} end)

    branch_actual = Enum.map(1..3, fn atm -> Bank.Branch.check_balance(atm, 10001) end)
    atm_actual = Enum.map(1..7, fn atm -> Bank.Atm.check_balance(atm, 10001) end)

    assert branch_expected == branch_actual
    assert atm_expected == atm_actual
  end

  test "problem 5: system heals after temporary net-split between branch 1 and branch 2" do
    Bank.Branch.open_account(1, 10001)
    Bank.Branch.open_account(2, 10002)

    net_split({:branch, 1}, {:branch, 2})
    net_split({:branch, 2}, {:branch, 1})

    Bank.Branch.deposit_cash(1, 10001, 100)
    Bank.Branch.deposit_cash(2, 10001, 50)
    Bank.Branch.close_account(2, 10002)

    # Depending on your implementation these next two line may not be true;
    # If you feel your scheme is so awesome/advanced then comment them out
    # and send a note to the instructors
    assert {:ok, 100} == Bank.Branch.check_balance(1, 10001)
    assert {:ok, 50} == Bank.Branch.check_balance(2, 10001)

    assert {:ok, 150} == Bank.Atm.check_balance(5, 10001)
    assert {:ok, 150} == Bank.Branch.check_balance(3, 10001)
    assert {:error, :account_does_not_exist} == Bank.Branch.check_balance(3, 10002)

    heal_net_split({:branch, 1}, {:branch, 2})
    heal_net_split({:branch, 2}, {:branch, 1})

    Process.sleep(1000)

    assert {:ok, 150} == Bank.Branch.check_balance(1, 10001)
    assert {:ok, 150} == Bank.Branch.check_balance(2, 10001)
    assert {:error, :account_does_not_exist} == Bank.Branch.check_balance(1, 10002)
  end

  test "problem 6: (midterm) create an account at branch-1, deposit at atm-1, check balance at branch-2" do
    {:ok, :account_opened} = Bank.Branch.open_account(1, 1000)

    # This will fail with `{:error, :account_does_not_exist}` until you implement account replication
    assert {:ok, :cash_deposited} = Bank.Atm.deposit_cash(1, 1000, 50)

    # This will fail with `{:error, :account_does_not_exist}` until you implement transaction replication
    assert {:ok, 50} = Bank.Branch.check_balance(2, 1000)
  end

  test "problem 7: (final) during a net-split withdrawals can overdraw by the average of last three deposits" do
    Bank.Branch.open_account(1, 10001)

    Bank.Branch.deposit_cash(1, 10001, 10)

    # Last three deposits will average $8
    Bank.Branch.deposit_cash(1, 10001, 9)
    Bank.Branch.deposit_cash(1, 10001, 13)
    Bank.Branch.deposit_cash(1, 10001, 2)

    assert {:ok, 34} == Bank.Branch.check_balance(2, 10001)

    # net split branch #2 from all ATMs
    1..7
    |> Enum.each(fn x ->
      net_split({:branch, 2}, {:atm, x})
      net_split({:atm, x}, {:branch, 2})
    end)

    # net split branch #2 from all Branches
    [1, 3]
    |> Enum.each(fn x ->
      net_split({:branch, 2}, {:branch, x})
      net_split({:branch, x}, {:branch, 2})
    end)

    assert {:error, :insufficient_funds} == Bank.Branch.withdraw_cash(2, 10001, 43)
    assert {:ok, :cash_withdrawn} == Bank.Branch.withdraw_cash(2, 10001, 42)

    # heal net split of branch #2 with all ATMs
    1..7
    |> Enum.each(fn x ->
      heal_net_split({:branch, 2}, {:atm, x})
      heal_net_split({:atm, x}, {:branch, 2})
    end)

    # heal net split of branch #2 with all Branches
    [1, 3]
    |> Enum.each(fn x ->
      heal_net_split({:branch, 2}, {:branch, x})
      heal_net_split({:branch, x}, {:branch, 2})
    end)

    Process.sleep(1000)

    assert {:error, :insufficient_funds} == Bank.Branch.withdraw_cash(1, 10001, 1)
    assert {:ok, -8} == Bank.Branch.check_balance(1, 10001)
  end

  test "problem 8: (final) behaving well in a ring" do
    split_all_connections()
    heal_net_split({:branch, 1}, {:branch, 2})
    heal_net_split({:branch, 2}, {:branch, 3})
    heal_net_split({:branch, 3}, {:atm, 1})
    heal_net_split({:atm, 1}, {:atm, 2})
    heal_net_split({:atm, 2}, {:atm, 3})
    heal_net_split({:atm, 3}, {:atm, 4})
    heal_net_split({:atm, 4}, {:atm, 5})
    heal_net_split({:atm, 5}, {:atm, 6})
    heal_net_split({:atm, 6}, {:atm, 7})
    heal_net_split({:atm, 7}, {:branch, 1})

    Bank.Branch.open_account(1, 10001)
    Bank.Branch.deposit_cash(1, 10001, 100)

    1..3
    |> Enum.each(fn x ->
      actual = Bank.Branch.check_balance(x, 10001)
      assert {:ok, 100} == actual, "check_balance at Branch #{x} returned #{inspect(actual)}"
    end)

    1..7
    |> Enum.each(fn x ->
      actual = Bank.Atm.check_balance(x, 10001)
      assert {:ok, 100} == actual, "check_balance at ATM #{x} returned #{inspect(actual)}"
    end)
  end

  defp net_split(from, to) do
    :sys.replace_state(Bank.Network, fn state ->
      raw_system_send(from, {:connection_down, to})
      new_broken_routes = MapSet.put(state.broken_routes, {from, to})
      Map.put(state, :broken_routes, new_broken_routes)
    end)
  end

  defp heal_net_split(from, to) do
    :sys.replace_state(Bank.Network, fn state ->
      if MapSet.member?(state.broken_routes, {from, to}) do
        raw_system_send(from, {:connection_up, to})
      end

      new_broken_routes = MapSet.delete(state.broken_routes, {from, to})
      Map.put(state, :broken_routes, new_broken_routes)
    end)
  end

  defp split_all_connections() do
    all_peer_combos()
    |> Enum.each(fn {from, to} ->
      net_split(from, to)
    end)
  end

  defp all_peer_combos() do
    peers = all_peers()
    combos = for from <- peers, to <- peers, do: {from, to}
    combos |> Enum.reject(fn {x, y} -> x == y end)
  end

  defp raw_system_send({to_type, to_id}, message) do
    case Registry.lookup(BankRegistry, {to_type, to_id}) do
      [{pid, _}] -> Process.send(pid, message, [])
      _ -> nil
    end
  end

  defp all_peers() do
    [
      {:branch, 1},
      {:branch, 2},
      {:branch, 3},
      {:atm, 1},
      {:atm, 2},
      {:atm, 3},
      {:atm, 4},
      {:atm, 5},
      {:atm, 6},
      {:atm, 7}
    ]
  end
end
