defmodule Bank.Branch do
  use GenServer
  require Logger

  ### ::: API :::

  @spec start_link(branch_id :: non_neg_integer()) :: {:ok, pid()}
  def start_link(id) do
    GenServer.start_link(__MODULE__, [id], name: via(id))
  end

  @spec check_cash_on_hand(branch_id :: non_neg_integer()) :: {:ok, non_neg_integer()}
  def check_cash_on_hand(id) do
    safe_call(id, :check_cash_on_hand)
  end

  @spec open_account(branch_id :: non_neg_integer(), account_number :: non_neg_integer) ::
          {:ok, :account_opened} | {:error, :account_already_exists}
  def open_account(id, account_number) do
    safe_call(id, {:open_account, account_number})
  end

  @spec close_account(branch_id :: non_neg_integer(), account_number :: non_neg_integer) ::
          {:ok, :account_closed}
          | {:error, :account_does_not_exist}
          | {:error, :account_balance_not_zero}
  def close_account(id, account_number) do
    safe_call(id, {:close_account, account_number})
  end

  @spec check_balance(branch_id :: non_neg_integer(), account_number :: non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :account_does_not_exist}
  def check_balance(id, account_number) do
    safe_call(id, {:check_balance, account_number})
  end

  @spec deposit_cash(
          branch_id :: non_neg_integer(),
          account_number :: non_neg_integer,
          amount :: non_neg_integer
        ) :: {:ok, :cash_deposited} | {:error, :account_does_not_exist}
  def deposit_cash(id, account_number, amount) do
    safe_call(id, {:deposit_cash, account_number, amount})
  end

  @spec withdraw_cash(
          branch_id :: non_neg_integer(),
          account_number :: non_neg_integer,
          amount :: non_neg_integer
        ) ::
          {:ok, :cash_withdrawn}
          | {:error, :account_does_not_exist}
          | {:error, :insufficient_funds}
          | {:error, :not_enough_cash_on_hand_at_this_branch}
  def withdraw_cash(id, account_number, amount) do
    safe_call(id, {:withdraw_cash, account_number, amount})
  end

  def receive_remote_command(branch_id, {:open_account, account_number}) do
    safe_call(branch_id, {:receive_remote_command, {:open_account, account_number}})
  end

  ### ::: GenServer callbacks :::

  def init([id]) do
    state = %{id: id, cash_on_hand: 1_000, accounts: %{}}
    {:ok, state}
  end

  def handle_call({:open_account, account_number}, _from, state) do
    %{state: new_state, reply: reply} = attempt_to_open_account(state, account_number)
    {:reply, reply, new_state}
  end

  def handle_call({:close_account, account_number}, _from, state) do
    case Map.get(state.accounts, account_number) do
      nil ->
        {:reply, {:error, :account_does_not_exist}, state}

      0 = _balance ->
        new_accounts = Map.delete(state.accounts, account_number)
        {:reply, {:ok, :account_closed}, %{state | accounts: new_accounts}}

      _ = _balance ->
        {:reply, {:error, :account_balance_not_zero}, state}
    end
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
    case Map.get(state.accounts, account_number) do
      nil ->
        {:reply, {:error, :account_does_not_exist}, state}

      current_amount ->
        new_accounts = Map.put(state.accounts, account_number, current_amount + amount)

        new_state =
          state
          |> Map.put(:accounts, new_accounts)
          |> Map.put(:cash_on_hand, state.cash_on_hand + amount)

        {:reply, {:ok, :cash_deposited}, new_state}
    end
  end

  def handle_call({:withdraw_cash, account_number, withdrawal_amount}, _from, state) do
    # TODO: Dear Student, please ensure that the branch's cash_on_hand is never negative

    case Map.get(state.accounts, account_number) do
      nil ->
        {:reply, {:error, :account_does_not_exist}, state}

      current_amount when current_amount < withdrawal_amount ->
        {:reply, {:error, :insufficient_funds}, state}

      current_amount ->
        new_accounts = Map.put(state.accounts, account_number, current_amount - withdrawal_amount)

        new_state =
          state
          |> Map.put(:accounts, new_accounts)
          |> Map.put(:cash_on_hand, state.cash_on_hand - withdrawal_amount)

        {:reply, {:ok, :cash_withdrawn}, new_state}
    end
  end

  def handle_call(:check_cash_on_hand, _from, state) do
    reply = {:ok, state.cash_on_hand}
    {:reply, reply, state}
  end

  def handle_call({:receive_remote_command, [:open_account, account_number]}, _from, state) do
    %{state: new_state, reply: reply} = attempt_to_open_account(state, account_number)
    {:reply, reply, new_state}
  end

  def attempt_to_open_account(state, account_number) do
    ##%{state: new_state, reply: reply}
    case Map.get(state.accounts, account_number) do
      nil ->
        new_accounts = Map.put(state.accounts, account_number, 0)
        new_state = %{state | accounts: new_accounts}
        replicate_command(new_state.id, {:open_account, account_number})
        %{state: new_state , reply: {:ok, :account_opened}}

      _exists ->
        %{state: state, reply: {:error, :account_already_exists}}
    end
  end

  def replicate_command(from_branch_id, command_to_send) do
    from_branch_id
    |> get_peers()
    |> Enum.each(fn {peer_module, peer_id} ->
      IO.puts("Here!")
      Bank.Network.remote_call({:branch, from_branch_id}, peer_module, :receive_remote_command, [peer_id, command_to_send]) end)
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

    locations -- [{:branch, from_branch_id}]
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
        "{:branch, #{state.id}}, but have not written a `handle_call` " <>
        "clause in #{__MODULE__} to deal with it."
    )

    {:reply, {:error, :missing_call}, state}
  end

  ## ================================================================
  ## Students, you will want to implement your message handlers here.
  ## ================================================================
  def handle_info({:open_account, account_number}, state) do
    case Map.get(state.accounts, account_number) do
      nil ->
        new_accounts = Map.put(state.accounts, account_number, 0)
        {:noreply, %{state | accounts: new_accounts}}

      _exists ->
        {:noreply, state}
    end
  end

  def handle_info(:another_custom_message, state) do
    {:noreply, state}
  end

  def handle_info(unexpected_message, state) do
    Logger.warn(
      "Dear Student, you have sent a message `#{inspect(unexpected_message)}` to " <>
        "{:branch, #{state.id}}, but have not written a `handle_info` " <>
        "clause in #{__MODULE__} to deal with it."
    )

    {:noreply, state}
  end

  ### ::: Internal helpers :::

  def safe_call(id, call) do
    case(Registry.keys(BankRegistry, self())) do
      [{_pid, _}] ->
        raise "You must use `Bank.Network.remote_call/3` when communicating with a remote branch or atm"

      _ ->
        GenServer.call(via(id), call)
    end
  end

  def via(id), do: {:via, Registry, {BankRegistry, {:branch, id}}}
end
