defmodule Bank.Atm do
  use GenServer
  require Logger

  ### ::: API :::

  @spec start_link(atm_id :: non_neg_integer()) :: {:ok, pid()}
  def start_link(id) do
    GenServer.start_link(__MODULE__, [id], name: via(id))
  end

  @spec check_balance(atm_id :: non_neg_integer(), account_number :: non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :account_does_not_exist}
  def check_balance(id, account_number) do
    safe_call(id, {:check_balance, account_number})
  end

  @spec deposit_cash(
          atm_id :: non_neg_integer(),
          account_number :: non_neg_integer,
          amount :: non_neg_integer
        ) :: {:ok, :cash_deposited} | {:error, :account_does_not_exist}
  def deposit_cash(id, account_number, amount) do
    safe_call(id, {:deposit_cash, account_number, amount})
  end

  @spec withdraw_cash(
          atm_id :: non_neg_integer(),
          account_number :: non_neg_integer,
          amount :: non_neg_integer
        ) ::
          {:ok, :cash_withdrawn}
          | {:error, :account_does_not_exist}
          | {:error, :insufficient_funds}
          | {:error, :not_enough_cash_on_hand_at_this_atm}
  def withdraw_cash(id, account_number, amount) do
    safe_call(id, {:withdraw_cash, account_number, amount})
  end

  @spec check_cash_on_hand(atm_id :: non_neg_integer()) :: {:ok, non_neg_integer()}
  def check_cash_on_hand(id) do
    safe_call(id, :check_cash_on_hand)
  end

  ### ::: GenServer callbacks :::

  def init([id]) do
    connections =
      get_peers(id)
      |> Enum.map(fn {type, id} -> {{type, id}, true} end)
      |> Map.new()
    state = %{id: id, cash_on_hand: 1_000, accounts: %{}, deposits: [], connections: connections}
    {:ok, state}
  end

  def handle_call({:open_account, account_number}, _from, state) do
    %{state: new_state, reply: reply} = attempt_to_open_account(state, account_number)

    replicate_command(new_state.id, {:open_account, account_number})

    {:reply, reply, new_state}
  end

  def handle_call({:check_balance, account_number}, _from, state) do
    reply =
      case Map.get(state.accounts, account_number) do
        nil -> {:error, :account_does_not_exist}
        amount -> {:ok, amount}
      end

    {:reply, reply, state}
  end

  def handle_call({:deposit_cash, account_number, amount}, _from, state) do
    %{state: new_state, reply: reply} =
      attempt_to_make_deposit(state, account_number, amount, :local)
      |> case do
        %{reply: {:ok, :cash_deposited} = reply, state: post_update_state} ->
          new_deposits = [amount] ++ post_update_state.deposits
          if length(new_deposits) > 3 do
            new_deposits
            |> Enum.drop(-1)
          end
          %{reply: reply, state: %{post_update_state | deposits: new_deposits}}
          |> IO.inspect(label: "state")
        %{reply: reply} ->
          {:reply, reply, state: state}
      end


    replicate_command(new_state.id, {:deposit_cash, account_number, amount})

    {:reply, reply, new_state}
  end

  def handle_call({:withdraw_cash, account_number, withdrawal_amount}, _from, state) do
    %{state: new_state, reply: reply} =
      attempt_to_withdraw_cash(state, account_number, withdrawal_amount, :local)

    replicate_command(new_state.id, {:withdraw_cash, account_number, withdrawal_amount})

    {:reply, reply, new_state}
  end

  def handle_call(:check_cash_on_hand, _from, state) do
    reply = {:ok, state.cash_on_hand}
    {:reply, reply, state}
  end

  def handle_call(
        {:transfer_money, sending_account_number, receiving_account_number, amount_to_send},
        _from,
        state
      ) do
    %{state: new_state, reply: reply} =
      attempt_to_transfer_money(
        state,
        sending_account_number,
        receiving_account_number,
        amount_to_send
      )

    replicate_command(
      new_state.id,
      {:transfer_money, sending_account_number, receiving_account_number, amount_to_send}
    )

    {:reply, reply, new_state}
  end

  ## ================================================================
  ## Students, you will want to implement your call handlers here.
  ## ================================================================
  def handle_call({:your_replication_call_bits_here, _payload}, _from, state) do
    {:reply, :your_reply_here, state}
  end

  def handle_call(unexpected_call, _from, state) do
    Logger.warn(
      "Dear Student, you have made a call `#{inspect(unexpected_call)}` to " <>
        "{:atm, #{state.id}}, but have not written a `handle_call` " <>
        "clause in #{__MODULE__} to deal with it."
    )

    {:reply, {:error, :missing_call}, state}
  end

  ## ================================================================
  ## Students, you will want to implement your message handlers here.
  ## ================================================================
  def handle_info({:your_replication_message_bits_here, _payload}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:transfer_money, sending_account_number, receiving_account_number, amount_to_send},
        state
      ) do
    %{state: new_state, reply: _reply} =
      attempt_to_transfer_money(
        state,
        sending_account_number,
        receiving_account_number,
        amount_to_send
      )

    {:noreply, new_state}
  end

  def handle_info({:open_account, account_number}, state) do
    %{state: new_state, reply: _reply} = attempt_to_open_account(state, account_number)

    {:noreply, new_state}
  end

  def handle_info({:close_account, account_number}, state) do
    %{state: new_state, reply: _reply} = attempt_to_close_account(state, account_number)

    {:noreply, new_state}
  end

  def handle_info({:deposit_cash, account_number, amount}, state) do
    new_state =
      attempt_to_make_deposit(state, account_number, amount, :remote)
      |> case do
        %{reply: {:ok, :cash_deposited}, state: post_update_state} ->
          new_deposits = [amount] ++ post_update_state.deposits
          if length(new_deposits) > 3 do
            new_deposits
            |> Enum.drop(-1)
          end
          %{post_update_state | deposits: new_deposits}
          |> IO.inspect(label: "state")
        %{reply: _reply} ->
          state
      end
    {:noreply, new_state}
  end

  def handle_info({:withdraw_cash, account_number, withdrawal_amount}, state) do
    %{state: new_state, reply: _reply} =
      attempt_to_withdraw_cash(state, account_number, withdrawal_amount, :remote)

    {:noreply, new_state}
  end

  def handle_info({:relay_message, {_from_type, _from_id}, {to_type, to_id}, message}, state) do
    if Map.get(state.connections, {to_type, to_id}) do
      Bank.Network.send_message(
        {:atm, state.id},
        {to_type, to_id},
        message
      )
    else
      state.connections
      |> Enum.find(fn {_, true_or_false} -> true_or_false end)
      |> case do
        nil ->
          nil

        {{relay_type, relay_id}, _} ->
          Bank.Routing.relay_message(
            {:atm, state.id},
            {relay_type, relay_id},
            {to_type, to_id},
            message
          )
      end
    end

    {:noreply, state}
  end

  def handle_info({:connection_down, {type, id}}, state) do
    new_connections =
      state.connections
      |> Map.put({type, id}, false)

    {:noreply, %{state | connections: new_connections}}
  end

  def handle_info({:connection_up, {type, id}}, state) do
    new_connections =
      state.connections
      |> Map.put({type, id}, true)

    {:noreply, %{state | connections: new_connections}}
  end

  def handle_info(unexpected_message, state) do
    Logger.warn(
      "Dear Student, you have sent a message `#{inspect(unexpected_message)}` to " <>
        "{:atm, #{state.id}}, but have not written a `handle_info` " <>
        "clause in #{__MODULE__} to deal with it."
    )

    {:noreply, state}
  end

  ### ::: Internal helpers :::
  def attempt_to_close_account(state, account_number) do
    case Map.get(state.accounts, account_number) do
      nil ->
        %{state: state, reply: {:error, :account_does_not_exist}}

      0 = _balance ->
        new_accounts = Map.delete(state.accounts, account_number)
        %{state: %{state | accounts: new_accounts}, reply: {:ok, :account_closed}}

      _ = _balance ->
        %{state: state, reply: {:error, :account_balance_not_zero}}
    end
  end

  def attempt_to_transfer_money(
        state,
        sending_account_number,
        receiving_account_number,
        amount_to_send
      ) do
    sending_current_balance = Map.get(state.accounts, sending_account_number)
    receiving_current_balance = Map.get(state.accounts, receiving_account_number)

    case {sending_current_balance, receiving_current_balance} do
      {nil, _} ->
        %{state: state, reply: {:error, :sending_account_does_not_exist}}

      {_, nil} ->
        %{state: state, reply: {:error, :receiving_account_does_not_exist}}

      sending_current_balance when sending_current_balance < amount_to_send ->
        %{state: state, reply: {:error, :insufficient_funds}}

      _both_exist ->
        new_accounts =
          state.accounts
          |> Map.put(receiving_account_number, receiving_current_balance + amount_to_send)
          |> Map.put(sending_account_number, sending_current_balance - amount_to_send)

        new_state =
          state
          |> Map.put(:accounts, new_accounts)

        %{state: new_state, reply: {:ok, :transferred}}
    end
  end

  def attempt_to_withdraw_cash(state, account_number, withdrawal_amount, local_or_remote) do
    case Map.get(state.accounts, account_number) do
      nil ->
        %{state: state, reply: {:error, :account_does_not_exist}}

      current_amount when current_amount < withdrawal_amount ->
        %{state: state, reply: {:error, :insufficient_funds}}

      _current_amount when state.cash_on_hand < withdrawal_amount ->
        %{state: state, reply: {:error, :not_enough_cash_on_hand_at_this_branch}}

      current_amount ->
        new_accounts = Map.put(state.accounts, account_number, current_amount - withdrawal_amount)

        new_state =
          state
          |> Map.put(:accounts, new_accounts)
          |> adjust_cash_on_hand(withdrawal_amount, local_or_remote)

        %{state: new_state, reply: {:ok, :cash_withdrawn}}
    end
  end

  def adjust_cash_on_hand(state, withdrawal_amount, :local) do
    state
    |> Map.put(:cash_on_hand, state.cash_on_hand - withdrawal_amount)
  end

  def adjust_cash_on_hand(state, _withdrawal_amount, :remote) do
    state
  end

  def attempt_to_open_account(state, account_number) do
    case Map.get(state.accounts, account_number) do
      nil ->
        new_accounts = Map.put(state.accounts, account_number, 0)
        %{state: %{state | accounts: new_accounts}, reply: {:ok, :account_opened}}

      _exists ->
        %{state: state, reply: {:error, :account_already_exists}}
    end
  end

  def attempt_to_make_deposit(state, account_number, amount, local_or_remote) do
    case Map.get(state.accounts, account_number) do
      nil ->
        %{state: state, reply: {:error, :account_does_not_exist}}

      current_amount ->
        new_accounts = Map.put(state.accounts, account_number, current_amount + amount)

        new_state =
          state
          |> Map.put(:accounts, new_accounts)
          |> increase_cash_on_hand(amount, local_or_remote)

        %{state: new_state, reply: {:ok, :cash_deposited}}
    end
  end

  def increase_cash_on_hand(state, deposit_amount, :local) do
    state
    |> Map.put(:cash_on_hand, state.cash_on_hand + deposit_amount)
  end

  def increase_cash_on_hand(state, _deposit_amount, :remote) do
    state
  end

  def replicate_command(from_atm_id, command_to_send) do
    first_pass_results =
      from_atm_id
      |> get_peers()
      |> Enum.map(fn peer ->
        {Bank.Network.send_message(
           {:atm, from_atm_id},
           peer,
           command_to_send
         ), peer}
      end)

    good_node =
      first_pass_results
      |> Enum.find_value(fn {result, peer} -> if result == {:ok, :sent}, do: peer end)

    first_pass_results
    |> Enum.reject(fn {result, _peer} -> result == {:ok, :sent} end)
    |> Enum.map(fn {_result, peer} -> peer end)
    |> Enum.each(fn bad_peer ->
      Bank.Routing.relay_message({:atm, from_atm_id}, good_node, bad_peer, command_to_send)
    end)
  end

  def get_peers(from_branch_id) do
    locations = [
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

    locations -- [{:atm, from_branch_id}]
  end

  def safe_call(id, call) do
    case(Registry.keys(BankRegistry, self())) do
      [{_pid, _}] ->
        raise "You must use `Bank.Network.remote_call/3` when communicating with a remote branch or atm"

      _ ->
        GenServer.call(via(id), call)
    end
  end

  def via(id), do: {:via, Registry, {BankRegistry, {:atm, id}}}
end
