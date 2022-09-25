defmodule Bank.Network do
  use GenServer
  require Logger

  ### ::: API :::

  def start_link(args \\ %{}) when is_map(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  This function allows a branch or atm to communicate with a remote branch or atm.

  For example, the local call `Bank.Branch.check_cash_on_hand(1)` can be called
  from the REPL. To make the same call from a remote branch or atm, it must be
  made through the `Bank.Network` module like so:

  `Bank.Network.remote_call(Bank.Branch, :check_cash_on_hand, [1])`.
  """
  def remote_call(module, function, args) when module in [Bank.Atm, Bank.Branch] do
    to_type =
      case module do
        Bank.Atm -> :atm
        Bank.Branch -> :branch
      end

    [to_id | _] = args

    case Registry.keys(BankRegistry, self()) do
      [{from_type, from_id}] when from_type in [:branch, :atm] ->
        GenServer.call(
          __MODULE__,
          {:remote_call, {from_type, from_id}, {to_type, to_id}, function, args}
        )

      _ ->
        Logger.warn("Caller does not appear to be a registered branch or atm")
    end
  end

  def send_message({from_type, from_id}, {to_type, to_id}, message) do
    GenServer.call(__MODULE__, {:send_message, {from_type, from_id}, {to_type, to_id}, message})
  end

  ### ::: GenServer callbacks :::

  def init(args) do
    atm_count = args |> Map.get(:atms, 7)
    branch_count = args |> Map.get(:branches, 3)

    1..atm_count |> Enum.each(fn atm_id -> Bank.Atm.start_link(atm_id) end)
    1..branch_count |> Enum.each(fn branch_id -> Bank.Branch.start_link(branch_id) end)

    state = %{atm_count: atm_count, branch_count: branch_count, broken_routes: MapSet.new()}
    {:ok, state}
  end

  def handle_call({:remote_call, from, {to_type, to_id} = to, function, args}, _from_pid, state) do
    pid =
      case Registry.lookup(BankRegistry, {to_type, to_id}) do
        [{pid, _}] -> pid
        _ -> nil
      end

    if pid == nil or MapSet.member?(state.broken_routes, {from, to}) do
      {:reply, :no_route, state}
    else
      to_module =
        case to_type do
          :atm -> Bank.Atm
          :branch -> Bank.Branch
        end

      result = apply(to_module, function, args)

      {:reply, result, state}
    end
  end

  def handle_call(
        {:send_message, from, {to_type, to_id} = to, message},
        _from,
        state
      ) do
    pid =
      case Registry.lookup(BankRegistry, {to_type, to_id}) do
        [{pid, _}] -> pid
        _ -> nil
      end

    if pid == nil or MapSet.member?(state.broken_routes, {from, to}) do
      {:reply, :no_route, state}
    else
      Process.send(pid, message, [])
      {:reply, {:ok, :sent}, state}
    end
  end

  ### ::: Internal helpers :::
end
