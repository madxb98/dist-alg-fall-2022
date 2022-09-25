defmodule Bank.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    non_test_children = [
      {Bank.Network, %{}}
    ]

    all_env_children = [
      {Registry, [keys: :unique, name: BankRegistry]}
    ]

    children =
      case mix_env() do
        "test" -> all_env_children
        _ -> all_env_children ++ non_test_children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bank.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp mix_env() do
    System.get_env("MIX_ENV")
  end
end
