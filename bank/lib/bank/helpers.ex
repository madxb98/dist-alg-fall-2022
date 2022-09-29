defmodule Helpers do
  @doc """
  Temporarily make the current process (`self()`) behave like a Branch.
  This should ony be used for testing Branch and ATM functionality from within iex.
  """
  def become_bank() do
    Registry.register(BankRegistry, {:branch, 0}, 0)
  end

  @doc """
  Temporarily make the current Bank process behave like a regular process .
  This should ony be used for testing Branch and ATM functionality from within iex.
  """
  def become_customer() do
    Registry.unregister(BankRegistry, {:branch, 0})
  end
end
