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
    state = %{id: id, cash_on_hand: 1_000, accounts: %{}}
    {:ok, state}
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

  def handle_call({:withdraw_cash, _account_number, _amount}, _from, state) do
    # TODO: Dear Student, you will need to fully implement this one.

    reply = {:error, :account_does_not_exist}
    {:reply, reply, state}
  end

  def handle_call(:check_cash_on_hand, _from, state) do
    reply = {:ok, state.cash_on_hand}
    {:reply, reply, state}
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

  def handle_info(unexpected_message, state) do
    Logger.warn(
      "Dear Student, you have sent a message `#{inspect(unexpected_message)}` to " <>
        "{:atm, #{state.id}}, but have not written a `handle_info` " <>
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

  def via(id), do: {:via, Registry, {BankRegistry, {:atm, id}}}
end
