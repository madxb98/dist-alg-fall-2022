defmodule Bank.Routing do
  require Logger

  def relay_message({from_type, from_id}, {relay_type, relay_id}, {to_type, to_id}, message) do
    Bank.Network.send_message(
      {from_type, from_id},
      {relay_type, relay_id},
      {:relay_message, {from_type, from_id}, {to_type, to_id}, message}
    )
  end
end
